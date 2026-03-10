//
//  NavigationCoordinator.swift
//  mks-multiplatform-iptv
//
//  Type-safe navigation coordinator using NavigationPath
//  Target: iOS 26+, macOS 26+
//

import SwiftUI

// MARK: - Navigation Coordinator

/// Observable coordinator for managing navigation state across the app
@MainActor
@Observable
final class NavigationCoordinator {
    // MARK: - Navigation State

    /// Selected sidebar destination
    var selectedDestination: NavigationDestination = .movies

    /// Navigation path for detail navigation
    var detailPath = NavigationPath()

    /// Column visibility for NavigationSplitView
    var columnVisibility: NavigationSplitViewVisibility = .all

    /// Whether detail is presented (for compact layouts)
    var isDetailPresented = false

    // MARK: - Navigation Actions

    /// Navigate to a destination in the detail column
    func navigate(to destination: DetailDestination) {
        detailPath.append(destination)
    }

    /// Navigate back in detail navigation
    func navigateBack() {
        if !detailPath.isEmpty {
            detailPath.removeLast()
        }
    }

    /// Pop to root of detail navigation
    func popToRoot() {
        detailPath.removeLast(detailPath.count)
    }

    /// Select a sidebar destination
    func select(_ destination: NavigationDestination) {
        selectedDestination = destination
        // Clear detail path when switching main destinations
        detailPath.removeLast(detailPath.count)
    }

    /// Toggle sidebar visibility
    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch columnVisibility {
            case .all:
                columnVisibility = .doubleColumn
            case .doubleColumn:
                columnVisibility = .all
            case .automatic:
                columnVisibility = .all
            default:
                columnVisibility = .all
            }
        }
    }

    /// Reset navigation state
    func reset() {
        selectedDestination = .movies
        detailPath.removeLast(detailPath.count)
        columnVisibility = .all
    }
}

// MARK: - Detail Destinations

/// Destinations for detail navigation (push navigation)
enum DetailDestination: Hashable, Identifiable {
    case movieDetail(movieId: Int)
    case seriesDetail(seriesId: Int)
    case liveChannelDetail(channelId: Int)
    case player(contentId: String, title: String)
    case downloadOptions(downloadId: UUID)

    var id: String {
        switch self {
        case .movieDetail(let id):
            return "movie-\(id)"
        case .seriesDetail(let id):
            return "series-\(id)"
        case .liveChannelDetail(let id):
            return "channel-\(id)"
        case .player(let contentId, _):
            return "player-\(contentId)"
        case .downloadOptions(let id):
            return "download-\(id.uuidString)"
        }
    }
}

// MARK: - Environment Key

private struct NavigationCoordinatorKey: EnvironmentKey {
    @MainActor
    static var defaultValue: NavigationCoordinator { NavigationCoordinator() }
}

extension EnvironmentValues {
    /// Access the navigation coordinator from the environment
    var navigationCoordinator: NavigationCoordinator {
        get { self[NavigationCoordinatorKey.self] }
        set { self[NavigationCoordinatorKey.self] = newValue }
    }
}

extension View {
    /// Provide a navigation coordinator to the view hierarchy
    func withNavigationCoordinator(_ coordinator: NavigationCoordinator) -> some View {
        self.environment(\.navigationCoordinator, coordinator)
    }
}
