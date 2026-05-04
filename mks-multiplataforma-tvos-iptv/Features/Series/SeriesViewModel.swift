//
//  SeriesViewModel.swift
//  mks-multiplataforma-tvos-iptv
//

import Foundation
import SwiftUI
import IPTVCore

@MainActor
final class SeriesViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var featured: Serie?
    @Published private(set) var sections: [SerieSection] = []

    struct SerieSection: Identifiable, Equatable {
        let id: String
        let title: String
        let series: [Serie]
    }

    func load(profile: IPTVProfile) async {
        state = .loading
        let service = IPTVService(profile: profile)
        do {
            async let seriesTask = service.fetchSeries()
            async let categoriesTask = service.fetchSeriesCategories()
            let (series, categories) = try await (seriesTask, categoriesTask)

            MKSLog.app.info("SeriesVM loaded \(series.count) series, \(categories.count) categories")

            featured = series
                .filter { ($0.cover?.isEmpty == false) && $0.rating5Based >= 4 }
                .randomElement()
                ?? series.first

            sections = buildSections(series: series, categories: categories)
            state = .loaded
        } catch {
            MKSLog.app.error("SeriesVM load failed: \(error)")
            state = .failed("\(error)")
        }
    }

    private func buildSections(series: [Serie], categories: [SeriesCategory]) -> [SerieSection] {
        var sections: [SerieSection] = []

        let recent = series
            .filter { Int($0.lastModified) ?? 0 > 0 }
            .sorted { (Int($0.lastModified) ?? 0) > (Int($1.lastModified) ?? 0) }
            .prefix(20)
        if !recent.isEmpty {
            sections.append(.init(id: "recent", title: "Recently Updated", series: Array(recent)))
        }

        let topRated = series
            .filter { $0.rating5Based >= 4.5 }
            .shuffled()
            .prefix(20)
        if !topRated.isEmpty {
            sections.append(.init(id: "top", title: "Top Rated", series: Array(topRated)))
        }

        let grouped = Dictionary(grouping: series, by: { $0.categoryId })
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
                series: Array(items.prefix(20))
            ))
        }

        return sections
    }
}
