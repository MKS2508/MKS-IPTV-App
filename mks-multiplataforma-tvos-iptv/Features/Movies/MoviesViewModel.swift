//
//  MoviesViewModel.swift
//  mks-multiplataforma-tvos-iptv
//
//  Loads movies + categories from IPTVService, exposes grouped sections.
//

import Foundation
import SwiftUI
import IPTVCore

@MainActor
final class MoviesViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var featured: Movie?
    @Published private(set) var sections: [MovieSection] = []

    struct MovieSection: Identifiable, Equatable {
        let id: String
        let title: String
        let movies: [Movie]
    }

    func load(profile: IPTVProfile) async {
        state = .loading
        let service = IPTVService(profile: profile)

        do {
            async let moviesTask = service.fetchMovies()
            async let categoriesTask = service.fetchMovieCategories()
            let (movies, categories) = try await (moviesTask, categoriesTask)

            MKSLog.app.info("MoviesVM loaded \(movies.count) movies, \(categories.count) categories")

            featured = pickFeatured(from: movies)
            sections = buildSections(movies: movies, categories: categories)
            state = .loaded
        } catch {
            MKSLog.app.error("MoviesVM load failed: \(error)")
            state = .failed("\(error)")
        }
    }

    private func pickFeatured(from movies: [Movie]) -> Movie? {
        movies
            .filter { ($0.streamIcon?.isEmpty == false) && ($0.rating5Based ?? 0) >= 4 }
            .randomElement()
        ?? movies.first
    }

    private func buildSections(movies: [Movie], categories: [MovieCategory]) -> [MovieSection] {
        var sections: [MovieSection] = []

        let recent = movies
            .filter { $0.added != nil }
            .sorted { (Int($0.added ?? "0") ?? 0) > (Int($1.added ?? "0") ?? 0) }
            .prefix(20)
        if !recent.isEmpty {
            sections.append(.init(id: "recent", title: "Recently Added", movies: Array(recent)))
        }

        let topRated = movies
            .filter { ($0.rating5Based ?? 0) >= 4.5 }
            .shuffled()
            .prefix(20)
        if !topRated.isEmpty {
            sections.append(.init(id: "top", title: "Top Rated", movies: Array(topRated)))
        }

        let grouped = Dictionary(grouping: movies, by: { $0.categoryId })
        let topCategories = categories
            .map { ($0, grouped[$0.categoryId]?.count ?? 0) }
            .filter { $0.1 >= 5 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        for (cat, _) in topCategories {
            let items = grouped[cat.categoryId] ?? []
            sections.append(.init(
                id: "cat-\(cat.categoryId)",
                title: cat.categoryName,
                movies: Array(items.prefix(20))
            ))
        }

        return sections
    }
}
