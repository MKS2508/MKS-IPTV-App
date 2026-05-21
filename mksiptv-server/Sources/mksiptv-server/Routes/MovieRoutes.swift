//
//  MovieRoutes.swift
//  mksiptv-server
//
//  REST API endpoints for movie management.
//

import Vapor
import IPTVCore

// MARK: - Movie Routes Collection

/// Movie management routes
public struct MovieRoutes: RouteCollection {
    private let profileStore: ProfileStore

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    public func boot(routes: RoutesBuilder) throws {
        // Grouped routes under /movies
        let movies = routes.grouped("movies")

        // List and search endpoints
        movies.get(use: listMovies)

        // Categories endpoint
        movies.get("categories", use: getMovieCategories)

        // Individual movie routes (before :id to avoid conflicts)
        movies.get(":id", use: getMovieDetail)
        movies.get(":id", "stream-url", use: getStreamURL)
    }

    // MARK: - Endpoint Handlers

    /// GET /movies - List movies with optional filtering and pagination
    func listMovies(req: Request) async throws -> MoviesListResponse {
        MKSLog.api.debug("Listing movies")

        // Get active profile
        guard let profile = try await profileStore.getActiveProfile() else {
            throw Abort(.badRequest, reason: "No active profile found")
        }

        // Parse query parameters
        let category = req.query[String.self, at: "category"]
        let search = req.query[String.self, at: "search"]
        let limit = (try? req.query.get(Int.self, at: "limit")) ?? 50
        let offset = (try? req.query.get(Int.self, at: "offset")) ?? 0
        let sort = req.query[String.self, at: "sort"] ?? "name"

        MKSLog.api.debug("Movies query params - category: \(category ?? "all"), search: \(search ?? "none"), limit: \(limit), offset: \(offset), sort: \(sort)")

        // Create IPTVService and fetch movies
        let service = IPTVService(profile: profile)
        var allMovies: [Movie]

        do {
            allMovies = try await service.fetchMovies()
        } catch {
            MKSLog.api.error("Failed to fetch movies from IPTV service: \(error)")
            throw Abort(.badGateway, reason: "Cannot connect to IPTV server")
        }

        // Filter by category if specified
        var filteredMovies = allMovies
        if let categoryId = category, !categoryId.isEmpty {
            filteredMovies = filteredMovies.filter { $0.categoryId == categoryId }
        }

        // Filter by search term if specified
        if let searchTerm = search, !searchTerm.isEmpty {
            filteredMovies = filteredMovies.filter {
                $0.name.localizedCaseInsensitiveContains(searchTerm)
            }
        }

        // Sort results
        switch sort {
        case "name":
            filteredMovies.sort { $0.name < $1.name }
        case "rating":
            filteredMovies.sort {
                guard let r1 = Double($0.rating ?? "0"), let r2 = Double($1.rating ?? "0") else {
                    return false
                }
                return r1 > r2
            }
        case "added":
            filteredMovies.sort {
                guard let d1 = $0.added, let d2 = $1.added else {
                    return false
                }
                return d1 > d2
            }
        default:
            break
        }

        // Calculate pagination
        let total = filteredMovies.count
        let startIndex = min(offset, total)
        let endIndex = min(offset + limit, total)
        let paginatedMovies = Array(filteredMovies[startIndex..<endIndex])

        // Map to response models
        let movieResponses = paginatedMovies.map { MovieResponse(from: $0) }

        let page = (offset / limit) + 1
        return MoviesListResponse(
            movies: movieResponses,
            page: page,
            perPage: limit,
            total: total
        )
    }

    /// GET /movies/categories - Get movie categories
    func getMovieCategories(req: Request) async throws -> [CategoryResponse] {
        MKSLog.api.debug("Fetching movie categories")

        // Get active profile
        guard let profile = try await profileStore.getActiveProfile() else {
            throw Abort(.badRequest, reason: "No active profile found")
        }

        // Create IPTVService and fetch categories
        let service = IPTVService(profile: profile)
        var categories: [MovieCategory]

        do {
            categories = try await service.fetchMovieCategories()
        } catch {
            MKSLog.api.error("Failed to fetch movie categories from IPTV service: \(error)")
            throw Abort(.badGateway, reason: "Cannot connect to IPTV server")
        }

        // Map to response models
        return categories.map { CategoryResponse(from: $0) }
    }

    /// GET /movies/:id - Get movie details
    func getMovieDetail(req: Request) async throws -> MovieDetailResponse {
        guard let idString = req.parameters.get("id"),
              let movieId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid movie ID format")
        }

        MKSLog.api.debug("Fetching movie details for ID: \(idString)")

        // Get active profile
        guard let profile = try await profileStore.getActiveProfile() else {
            throw Abort(.badRequest, reason: "No active profile found")
        }

        // Create IPTVService and fetch movie details
        let service = IPTVService(profile: profile)
        let detail: MovieDetail

        do {
            detail = try await service.fetchMovieDetails(vodId: movieId)
        } catch {
            MKSLog.api.error("Failed to fetch movie details from IPTV service: \(error)")
            throw Abort(.badGateway, reason: "Cannot connect to IPTV server")
        }

        return MovieDetailResponse(from: detail)
    }

    /// GET /movies/:id/stream-url - Get streaming URL for a movie
    func getStreamURL(req: Request) async throws -> StreamURLResponse {
        guard let idString = req.parameters.get("id"),
              let movieId = Int(idString) else {
            throw Abort(.badRequest, reason: "Invalid movie ID format")
        }

        MKSLog.api.debug("Fetching stream URL for movie ID: \(idString)")

        // Get active profile
        guard let profile = try await profileStore.getActiveProfile() else {
            throw Abort(.badRequest, reason: "No active profile found")
        }

        // Fetch movie details to get extension
        let service = IPTVService(profile: profile)
        let detail: MovieDetail

        do {
            detail = try await service.fetchMovieDetails(vodId: movieId)
        } catch {
            MKSLog.api.error("Failed to fetch movie details from IPTV service: \(error)")
            throw Abort(.badGateway, reason: "Cannot connect to IPTV server")
        }

        // Build stream URL using Xtream Codes format
        let streamExtension = detail.movieData.containerExtension ?? "mkv"
        let streamURL = "\(profile.baseURL)/movie/\(profile.username)/\(profile.password)/\(movieId).\(streamExtension)"

        MKSLog.api.debug("Generated stream URL for movie \(movieId): \(streamURL)")

        return StreamURLResponse(
            movieId: movieId,
            url: streamURL,
            streamExtension: streamExtension,
            headers: nil
        )
    }
}
