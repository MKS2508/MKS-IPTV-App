//
//  NavigationDestination.swift
//  mks-multiplatform-iptv
//
//  Type-safe navigation destinations replacing string-based navigation
//

import SwiftUI

/// Type-safe navigation destinations for the main app
enum NavigationDestination: String, CaseIterable, Identifiable, Codable {
    case movies = "Movies"
    case series = "Series"
    case liveChannels = "LiveChannels"
    case downloads = "Downloads"
    #if DEBUG
    case debugStream = "DebugStream"
    #endif

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .movies: return "Movies"
        case .series: return "Series"
        case .liveChannels: return "Live TV"
        case .downloads: return "Downloads"
        #if DEBUG
        case .debugStream: return "Debug Stream"
        #endif
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .movies: return "film"
        case .series: return "tv"
        case .liveChannels: return "antenna.radiowaves.left.and.right"
        case .downloads: return "arrow.down.circle"
        #if DEBUG
        case .debugStream: return "ant.circle"
        #endif
        }
    }

    /// Create from string (for backward compatibility)
    init?(from string: String?) {
        guard let string = string else { return nil }
        self.init(rawValue: string)
    }
}

// MARK: - Navigation State

/// Observable navigation state for the app
@MainActor
@Observable
final class NavigationState {
    var selectedDestination: NavigationDestination? = .movies

    func select(_ destination: NavigationDestination) {
        selectedDestination = destination
    }

    func select(from string: String?) {
        selectedDestination = NavigationDestination(from: string)
    }
}

// MARK: - View Extensions

extension NavigationLink where Destination == Never {
    /// Creates a navigation link with a navigation destination
    init(
        destination: NavigationDestination,
        @ViewBuilder label: () -> Label
    ) {
        self.init(value: destination.rawValue, label: label)
    }
}

extension Label where Title == Text, Icon == Image {
    /// Creates a label for a navigation destination
    init(destination: NavigationDestination) {
        self.init(destination.displayName, systemImage: destination.iconName)
    }
}
