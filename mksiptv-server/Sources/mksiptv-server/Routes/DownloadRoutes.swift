//
//  DownloadRoutes.swift
//  mksiptv-server
//
//  REST API endpoints for download management.
//

import Vapor
import IPTVCore

// MARK: - Download Routes Collection

/// Download management routes
public struct DownloadRoutes: RouteCollection {
    private let downloadManager: ServerDownloadManager
    private let profileStore: ProfileStore

    public init(downloadManager: ServerDownloadManager, profileStore: ProfileStore) {
        self.downloadManager = downloadManager
        self.profileStore = profileStore
    }

    public func boot(routes: RoutesBuilder) throws {
        // Grouped routes under /downloads
        let downloads = routes.grouped("downloads")

        // List and create endpoints
        downloads.get(use: listDownloads)
        downloads.post(use: initiateDownload)

        // Individual download routes
        downloads.get(":id", use: getDownload)
        downloads.delete(":id", use: cancelDownload)
        downloads.post(":id", "pause", use: pauseDownload)
        downloads.post(":id", "resume", use: resumeDownload)
        downloads.get(":id", "progress", use: getDownloadProgress)

        MKSLog.server.info("Download routes registered")
    }

    // MARK: - Endpoint Handlers

    /// GET /downloads - List all downloads
    func listDownloads(req: Request) async throws -> [DownloadResponse] {
        MKSLog.api.debug("Listing downloads")

        let downloads = await downloadManager.listDownloads()
        return downloads.map { $0.toResponse() }
    }

    /// POST /downloads - Initiate a new download
    func initiateDownload(req: Request) async throws -> DownloadResponse {
        let request = try req.content.decode(InitiateDownloadRequest.self)

        MKSLog.api.info("Initiating download: \(request.contentType.rawValue) \(request.contentId)")

        // Get active profile
        guard let profile = try await profileStore.getActiveProfile() else {
            throw Abort(.badRequest, reason: "No active profile found")
        }

        // Get stream URL and title based on content type
        let (streamURL, title): (URL, String)

        switch request.contentType {
        case .movie:
            // Fetch movies from IPTV service
            let service = IPTVService(profile: profile)
            let movies = try await service.fetchMovies()
            guard let movie = movies.first(where: { $0.streamId == request.contentId }) else {
                throw Abort(.notFound, reason: "Movie not found")
            }
            // Build stream URL
            let streamExtension = profile.fileExtension
            let urlString = "\(profile.baseURL)/movie/\(profile.username)/\(profile.password)/\(movie.streamId).\(streamExtension)"
            guard let url = URL(string: urlString) else {
                throw Abort(.internalServerError, reason: "Failed to construct stream URL")
            }
            streamURL = url
            title = movie.name

        case .series:
            // Fetch series and episodes from IPTV service
            let service = IPTVService(profile: profile)
            let series = try await service.fetchSeries()
            guard let serie = series.first(where: { $0.streamId == request.contentId }) else {
                throw Abort(.notFound, reason: "Serie not found")
            }
            // For series, we need to download a specific episode
            // This is a simplified implementation - in production you'd specify season/episode
            throw Abort(.badRequest, reason: "Series downloads require episode ID. Use contentId as episode.streamId")

        case .liveChannel:
            throw Abort(.badRequest, reason: "Live channels cannot be downloaded")
        }

        // Determine output format
        let outputFormat = request.outputFormat ?? "mp4"

        // Initiate download
        let item = try await downloadManager.initiateDownload(
            contentType: request.contentType,
            contentId: request.contentId,
            title: title,
            streamURL: streamURL,
            outputFormat: outputFormat
        )

        return item.toResponse()
    }

    /// GET /downloads/:id - Get download details
    func getDownload(req: Request) async throws -> DownloadResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid download ID")
        }

        MKSLog.api.debug("Getting download: \(idString)")

        guard let item = await downloadManager.getDownload(id: id) else {
            throw Abort(.notFound, reason: "Download not found")
        }

        return item.toResponse()
    }

    /// DELETE /downloads/:id - Cancel a download
    func cancelDownload(req: Request) async throws -> HTTPStatus {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid download ID")
        }

        MKSLog.api.info("Cancelling download: \(idString)")

        try await downloadManager.cancelDownload(id: id)

        return .noContent
    }

    /// POST /downloads/:id/pause - Pause a download
    func pauseDownload(req: Request) async throws -> DownloadResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid download ID")
        }

        MKSLog.api.info("Pausing download: \(idString)")

        let item = try await downloadManager.pauseDownload(id: id)
        return item.toResponse()
    }

    /// POST /downloads/:id/resume - Resume a paused download
    func resumeDownload(req: Request) async throws -> DownloadResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid download ID")
        }

        MKSLog.api.info("Resuming download: \(idString)")

        let item = try await downloadManager.resumeDownload(id: id)
        return item.toResponse()
    }

    /// GET /downloads/:id/progress - Get detailed progress information
    func getDownloadProgress(req: Request) async throws -> DownloadProgressResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid download ID")
        }

        MKSLog.api.debug("Getting download progress: \(idString)")

        guard let item = await downloadManager.getDownload(id: id) else {
            throw Abort(.notFound, reason: "Download not found")
        }

        return item.toProgressResponse()
    }
}
