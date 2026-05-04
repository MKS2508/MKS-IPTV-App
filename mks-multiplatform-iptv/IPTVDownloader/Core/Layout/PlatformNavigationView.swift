import IPTVCore
//
//  PlatformNavigationView.swift
//  mks-multiplatform-iptv
//
//  Platform-adaptive navigation with native NavigationSplitView and TabView
//  Target: iOS 26+, macOS 26+
//  Refactored for proper native layout handling
//

import SwiftUI

// MARK: - Platform Navigation View

/// Adaptive navigation container that provides platform-appropriate navigation patterns
///
/// On macOS and iPad:
/// - Uses `NavigationSplitView` with sidebar and detail columns
/// - Supports keyboard shortcuts for navigation
/// - Respects system sidebar visibility preferences
///
/// On iPhone:
/// - Uses `TabView` with bottom tabs
/// - Full-screen detail presentation
/// - Swipe-to-navigate support
struct PlatformNavigationView<SidebarContent: View, DetailContent: View>: View {
    @ViewBuilder let sidebarContent: () -> SidebarContent
    @ViewBuilder let detailContent: () -> DetailContent
    /// Destination-based content builder for iPhone TabView.
    /// Each tab renders its own content based on the destination, avoiding shared-state issues.
    var tabContent: ((NavigationDestination) -> AnyView)? = nil
    @Binding var selectedItem: String?

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - State

    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var presentedSheet: SheetDestination?

    // MARK: - Body

    var body: some View {
        #if os(macOS)
        macOSLayout
        #elseif os(iOS)
        iOSLayout
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent()
                .frame(
                    minWidth: Platform.macOS.minSidebarWidth,
                    idealWidth: Platform.macOS.idealSidebarWidth,
                    maxWidth: Platform.macOS.maxSidebarWidth
                )
                .navigationSplitViewColumnWidth(
                    min: Platform.macOS.minSidebarWidth,
                    ideal: Platform.macOS.idealSidebarWidth,
                    max: Platform.macOS.maxSidebarWidth
                )
                .listStyle(.sidebar)
        } detail: {
            detailContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .onKeyDown(.escape) {
            // Escape to toggle sidebar on macOS
            toggleSidebar()
        }
        .background {
            // Hidden button to register Cmd+S keyboard shortcut for sidebar toggle
            Button(action: toggleSidebar) {}
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        }
    }

    private func toggleSidebar() {
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
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    private var iOSLayout: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad: Use split view
                iPadLayout
            } else {
                // iPhone: Use tab view
                iPhoneLayout
            }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent()
                .navigationSplitViewColumnWidth(
                    min: Platform.iPad.minSidebarWidth,
                    ideal: Platform.iPad.idealSidebarWidth,
                    max: Platform.iPad.maxSidebarWidth
                )
                .listStyle(.sidebar)
        } detail: {
            detailContent()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var iPhoneLayout: some View {
        TabView(selection: $selectedItem) {
            ForEach(NavigationDestination.displayable, id: \.rawValue) { destination in
                NavigationStack {
                    if let tabContent {
                        tabContent(destination)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        detailContent()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .tabItem {
                    Label(destination.displayName, systemImage: destination.iconName)
                }
                .tag(destination.rawValue)
            }
        }
        .tint(AppColors.accent)
        #if os(iOS)
        .tabViewStyle(.automatic)
        #endif
    }
    #endif
}

// MARK: - Sheet Destinations

enum SheetDestination: Identifiable {
    case settings
    case profileSelection
    case movieDetail(movieId: Int)
    case seriesDetail(seriesId: Int)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .profileSelection: return "profile-selection"
        case .movieDetail(let id): return "movie-\(id)"
        case .seriesDetail(let id): return "series-\(id)"
        }
    }
}

// MARK: - Keyboard Shortcuts (macOS)

#if os(macOS)
extension View {
    /// Handle keyboard shortcuts with a key event
    @ViewBuilder
    func onKeyDown(_ key: KeyEquivalent, perform action: @escaping () -> Void) -> some View {
        self.onKeyPress(key) {
            action()
            return .handled
        }
    }
}
#endif

// MARK: - Navigation Destination Extension

extension NavigationDestination {
    /// Destinations that should be displayed in TabView (excludes debug)
    static var displayable: [NavigationDestination] {
        #if DEBUG
        return [.home, .movies, .series, .liveChannels, .myContent, .debugStream]
        #else
        return [.home, .movies, .series, .liveChannels, .downloads]
        #endif
    }
}

// MARK: - Platform Detection Helpers

#if canImport(UIKit)
import UIKit
import IPTVCore

extension UIDevice {
    /// Whether the current device is an iPad
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Whether the current device is an iPhone
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    /// Whether the current device is an Apple TV
    static var isAppleTV: Bool {
        UIDevice.current.userInterfaceIdiom == .tv
    }
}
#endif

// MARK: - Preview

#Preview {
    PlatformNavigationView(
        sidebarContent: {
            List {
                Text("Movies")
                Text("Series")
                Text("Live TV")
            }
        },
        detailContent: {
            Text("Detail Content")
        },
        selectedItem: .constant("Movies")
    )
}
