//
//  NavigationDestination.swift
//  mks-multiplatform-iptv
//
//  Type-safe navigation destinations replacing string-based navigation
//

import SwiftUI

/// Type-safe navigation destinations for the main app
enum NavigationDestination: String, CaseIterable, Identifiable, Codable {
    case home = "Home"
    case movies = "Movies"
    case series = "Series"
    case liveChannels = "LiveChannels"
    case myContent = "MyContent"
    #if DEBUG
    case debugStream = "DebugStream"
    case cacheDebug = "CacheDebug"
    case logsDebug = "LogsDebug"
    #endif

    var id: String { rawValue }

    /// Display name for UI
    var displayName: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .series: return "Series"
        case .liveChannels: return "Live TV"
        case .myContent: return "My Content"
        #if DEBUG
        case .debugStream: return "Debug Stream"
        case .cacheDebug: return "Cache Inspector"
        case .logsDebug: return "Logs Inspector"
        #endif
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film"
        case .series: return "tv"
        case .liveChannels: return "antenna.radiowaves.left.and.right"
        case .myContent: return "folder.fill"
        #if DEBUG
        case .debugStream: return "ant.circle"
        case .cacheDebug: return "internaldrive"
        case .logsDebug: return "doc.text.magnifyingglass"
        #endif
        }
    }

    /// Create from string (for backward compatibility)
    init?(from string: String?) {
        guard let string = string else { return nil }
        // Handle legacy "Downloads" -> "MyContent" migration
        if string == "Downloads" {
            self = .myContent
            return
        }
        self.init(rawValue: string)
    }
}

// MARK: - Navigation State

/// Observable navigation state for the app
@MainActor
@Observable
final class NavigationState {
    var selectedDestination: NavigationDestination? = .home

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
