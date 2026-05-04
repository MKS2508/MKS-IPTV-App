//
//  SortingExtensions.swift
//  mks-multiplatform-iptv
//
//  Shared sorting utilities for media items
//  Consolidates duplicate sorting methods from ViewModels
//

import Foundation
import IPTVCore

// MARK: - Sort Option

/// Common sort options for media lists
enum MediaSortOption: String, CaseIterable {
    case nameAsc = "Name A-Z"
    case nameDesc = "Name Z-A"
    case addedAsc = "Oldest First"
    case addedDesc = "Newest First"
}

// MARK: - Movie Sorting

extension Array where Element == Movie {
    /// Sort movies by name alphabetically (ascending)
    func sortedByNameAsc() -> [Movie] {
        sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    /// Sort movies by name alphabetically (descending)
    func sortedByNameDesc() -> [Movie] {
        sorted { $0.name.localizedLowercase > $1.name.localizedLowercase }
    }

    /// Sort movies by added date (oldest first)
    func sortedByAddedAsc() -> [Movie] {
        sorted { movie1, movie2 in
            guard let date1 = Double(movie1.added ?? "0"),
                  let date2 = Double(movie2.added ?? "0") else {
                return false
            }
            return date1 < date2
        }
    }

    /// Sort movies by added date (newest first)
    func sortedByAddedDesc() -> [Movie] {
        sorted { movie1, movie2 in
            guard let date1 = Double(movie1.added ?? "0"),
                  let date2 = Double(movie2.added ?? "0") else {
                return false
            }
            return date1 > date2
        }
    }

    /// Apply a sort option to the array
    func sorted(by option: MediaSortOption) -> [Movie] {
        switch option {
        case .nameAsc: return sortedByNameAsc()
        case .nameDesc: return sortedByNameDesc()
        case .addedAsc: return sortedByAddedAsc()
        case .addedDesc: return sortedByAddedDesc()
        }
    }

    /// Sort in place by option
    mutating func sort(by option: MediaSortOption) {
        self = sorted(by: option)
    }
}

// MARK: - Serie Sorting

extension Array where Element == Serie {
    /// Sort series by name alphabetically (ascending)
    func sortedByNameAsc() -> [Serie] {
        sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    /// Sort series by name alphabetically (descending)
    func sortedByNameDesc() -> [Serie] {
        sorted { $0.name.localizedLowercase > $1.name.localizedLowercase }
    }

    /// Sort series by last modified date (oldest first)
    func sortedByAddedAsc() -> [Serie] {
        sorted { serie1, serie2 in
            guard let date1 = Double(serie1.lastModified),
                  let date2 = Double(serie2.lastModified) else {
                return false
            }
            return date1 < date2
        }
    }

    /// Sort series by last modified date (newest first)
    func sortedByAddedDesc() -> [Serie] {
        sorted { serie1, serie2 in
            guard let date1 = Double(serie1.lastModified),
                  let date2 = Double(serie2.lastModified) else {
                return false
            }
            return date1 > date2
        }
    }

    /// Apply a sort option to the array
    func sorted(by option: MediaSortOption) -> [Serie] {
        switch option {
        case .nameAsc: return sortedByNameAsc()
        case .nameDesc: return sortedByNameDesc()
        case .addedAsc: return sortedByAddedAsc()
        case .addedDesc: return sortedByAddedDesc()
        }
    }

    /// Sort in place by option
    mutating func sort(by option: MediaSortOption) {
        self = sorted(by: option)
    }
}

// MARK: - LiveChannel Sorting

extension Array where Element == LiveChannel {
    /// Sort channels by name alphabetically (ascending)
    func sortedByNameAsc() -> [LiveChannel] {
        sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    /// Sort channels by name alphabetically (descending)
    func sortedByNameDesc() -> [LiveChannel] {
        sorted { $0.name.localizedLowercase > $1.name.localizedLowercase }
    }

    /// Sort channels by added date (oldest first)
    func sortedByAddedAsc() -> [LiveChannel] {
        sorted { channel1, channel2 in
            guard let date1 = Double(channel1.added),
                  let date2 = Double(channel2.added) else {
                return false
            }
            return date1 < date2
        }
    }

    /// Sort channels by added date (newest first)
    func sortedByAddedDesc() -> [LiveChannel] {
        sorted { channel1, channel2 in
            guard let date1 = Double(channel1.added),
                  let date2 = Double(channel2.added) else {
                return false
            }
            return date1 > date2
        }
    }

    /// Apply a sort option to the array
    func sorted(by option: MediaSortOption) -> [LiveChannel] {
        switch option {
        case .nameAsc: return sortedByNameAsc()
        case .nameDesc: return sortedByNameDesc()
        case .addedAsc: return sortedByAddedAsc()
        case .addedDesc: return sortedByAddedDesc()
        }
    }

    /// Sort in place by option
    mutating func sort(by option: MediaSortOption) {
        self = sorted(by: option)
    }
}
