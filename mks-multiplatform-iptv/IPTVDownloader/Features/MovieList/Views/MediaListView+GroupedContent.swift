//
//  MediaListView+GroupedContent.swift
//  mks-multiplatform-iptv
//
//  Extension for grouped content logic
//

import SwiftUI

extension MediaListView {
    // MARK: - Grouped Content Properties
    
    var groupedItems: [(key: String, items: [MediaIndexItem])]? {
        let items: [MediaIndexItem] = {
            switch contentTypeFilter {
            case .movies: 
                return filteredMovies
            case .series: 
                return filteredSeries
            case .all: 
                return filteredMovies + filteredSeries
            }
        }()
        
        guard !items.isEmpty else { return nil }
        
        switch sortOption {
        case .nameAsc, .nameDesc:
            return groupByAlphabet(items: items)
        case .addedAsc, .addedDesc:
            return groupByDate(items: items)
        }
    }
    
    // MARK: - Private Grouping Methods
    
    private func groupByAlphabet(items: [MediaIndexItem]) -> [(key: String, items: [MediaIndexItem])] {
        let grouped = Dictionary(grouping: items) { item -> String in
            let firstChar = item.name.uppercased().first
            if let char = firstChar, char.isLetter {
                return String(char)
            } else {
                return "#"
            }
        }
        
        let sortedKeys = grouped.keys.sorted { first, second in
            // # goes at the end
            if first == "#" { return false }
            if second == "#" { return true }
            return first < second
        }
        
        return sortedKeys.map { key in
            let sortedItems = grouped[key]!.sorted { first, second in
                switch sortOption {
                case .nameAsc:
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
                case .nameDesc:
                    return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedDescending
                default:
                    return false
                }
            }
            return (key: key, items: sortedItems)
        }
    }
    
    private func groupByDate(items: [MediaIndexItem]) -> [(key: String, items: [MediaIndexItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        formatter.locale = Locale(identifier: "en_US")
        
        let grouped = Dictionary(grouping: items) { item -> String in
            formatter.string(from: item.addedDate)
        }
        
        let sortedKeys = grouped.keys.sorted { first, second in
            guard let firstDate = formatter.date(from: first),
                  let secondDate = formatter.date(from: second) else {
                return first < second
            }
            
            switch sortOption {
            case .addedDesc:
                return firstDate > secondDate
            case .addedAsc:
                return firstDate < secondDate
            default:
                return false
            }
        }
        
        return sortedKeys.map { key in
            let sortedItems = grouped[key]!.sorted { first, second in
                switch sortOption {
                case .addedDesc:
                    return first.addedDate > second.addedDate
                case .addedAsc:
                    return first.addedDate < second.addedDate
                default:
                    return false
                }
            }
            return (key: key, items: sortedItems)
        }
    }
    
    // MARK: - Index Titles
    
    var indexTitles: [String] {
        guard let grouped = groupedItems else { return [] }
        return grouped.map { section in
            switch sortOption {
            case .nameAsc, .nameDesc:
                // For alphabet, show single letter
                return String(section.key.prefix(1))
            case .addedAsc, .addedDesc:
                // For dates, show abbreviated form
                return String(section.key.prefix(3))
            }
        }
    }
    
    // MARK: - Grouped Content View
    
    var groupedContentView: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            if let grouped = groupedItems {
                ForEach(grouped, id: \.key) { section in
                    Section(header: MediaSectionHeader(title: section.key)) {
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                mediaItemCard(for: item)
                            }
                        }
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, verticalPadding)
                    }
                    .id(section.key)
                }
            }
        }
        .padding(.top, 60) // Extra padding for navigation bar
    }
}