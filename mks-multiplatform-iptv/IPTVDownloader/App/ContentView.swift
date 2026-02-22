//
//  ContentView.swift
//  mks-multiplatform-iptv
//
//  Main content view - now a thin shell composing extracted components
//  Refactored from ~700 lines to ~150 lines
//  Updated: Native layout with NavigationCoordinator
//

import SwiftUI
#if canImport(KSPlayer)
import KSPlayer
#endif

struct ContentView: View {
    @Binding var showingSettings: Bool
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var profilesManager: IPTVProfilesManager
    @EnvironmentObject private var profile: IPTVProfile

    // Navigation state - uses NavigationCoordinator for type-safe navigation
    @State private var navigationCoordinator = NavigationCoordinator()
    @State private var selectedView: String? = "Movies"

    // Data loading
    @State private var dataLoader: AppDataLoader?

    #if os(macOS)
    @StateObject private var touchBarManager = TouchBarManager()
    #endif

    // MARK: - Initialization

    init(showingSettings: Binding<Bool>) {
        self._showingSettings = showingSettings
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundPattern
            mainContent
            #if os(macOS)
            touchBarAccessor
            #endif
        }
        .withNavigationCoordinator(navigationCoordinator)
        .onAppear {
            initializeDataLoader()
        }
        .task {
            await dataLoader?.loadAllData()
            #if os(macOS)
            await MainActor.run {
                setupTouchBarCallbacks()
                updateTouchBarContext(for: selectedView)
            }
            #endif
        }
        #if os(macOS)
        .onChange(of: selectedView) { _, newValue in
            updateTouchBarContext(for: newValue)
        }
        #endif
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(profilesManager)
        }
    }

    // MARK: - View Components

    private var backgroundPattern: some View {
        ZStack {
            // Native dark gradient background
            Color.black.ignoresSafeArea()

            // Subtle gradient for depth
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.04, green: 0.01, blue: 0.01),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle accent glow
            RadialGradient(
                colors: [
                    Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.04),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 600
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if let loader = dataLoader, loader.isLoading {
            // Native launch screen following Apple HIG
            NativeLaunchScreen(loadingStatus: loader.loadingStatus.displayText)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
        } else if let loader = dataLoader {
            PlatformNavigationView(
                sidebarContent: { sidebarContent },
                detailContent: { detailContent(loader: loader) },
                selectedItem: $selectedView
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingSettings = true }) {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings (⌘,)")
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(selection: $selectedView) {
            ForEach(NavigationDestination.allCases) { destination in
                #if DEBUG
                if destination == .debugStream {
                    Section {
                        navigationLink(for: destination)
                    } header: {
                        Text("Development")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    navigationLink(for: destination)
                }
                #else
                if destination != .debugStream {
                    navigationLink(for: destination)
                }
                #endif
            }
        }
        .accessibilityLabel("Main Navigation")
    }

    @ViewBuilder
    private func navigationLink(for destination: NavigationDestination) -> some View {
        NavigationLink(value: destination.rawValue) {
            Label(destination.displayName, systemImage: destination.iconName)
                #if DEBUG
                .foregroundColor(destination == .debugStream ? .orange : .primary)
                #endif
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(loader: AppDataLoader) -> some View {
        if let destination = NavigationDestination(from: selectedView) {
            destinationView(for: destination, loader: loader)
        } else {
            emptySelectionView
        }
    }

    @ViewBuilder
    private func destinationView(for destination: NavigationDestination, loader: AppDataLoader) -> some View {
        switch destination {
        case .movies:
            if let mediaViewModel = loader.mediaViewModel {
                MediaListView(
                    viewModel: mediaViewModel,
                    selectedView: $selectedView,
                    movieCategories: loader.movieCategories,
                    seriesCategories: [],
                    initialContentType: .movies,
                    showContentTypeSelector: false
                )
                #if os(macOS)
                .environmentObject(touchBarManager)
                #endif
            } else {
                loadingPlaceholder
            }

        case .series:
            if let mediaViewModel = loader.mediaViewModel {
                MediaListView(
                    viewModel: mediaViewModel,
                    selectedView: $selectedView,
                    movieCategories: [],
                    seriesCategories: loader.seriesCategories,
                    initialContentType: .series,
                    showContentTypeSelector: false
                )
                #if os(macOS)
                .environmentObject(touchBarManager)
                #endif
            } else {
                loadingPlaceholder
            }

        case .liveChannels:
            if let liveChannelVM = loader.liveChannelViewModel {
                LiveChannelsGridView()
                    .environmentObject(profile)
                    .environmentObject(liveChannelVM)
                    #if os(macOS)
                    .environmentObject(touchBarManager)
                    #endif
                    .navigationTitle("Live TV")
            } else {
                loadingPlaceholder
            }

        case .downloads:
            DownloadsView()
                #if os(macOS)
                .environmentObject(touchBarManager)
                #endif
                .navigationTitle("Downloads")

        #if DEBUG
        case .debugStream:
            if let movieService = loader.movieService {
                DebugStreamingView(movieService: movieService)
                    .navigationTitle("Debug Stream")
            } else {
                loadingPlaceholder
            }
        #endif
        }
    }

    private var loadingPlaceholder: some View {
        Text("Loading...")
            .foregroundColor(.secondary)
    }

    private var emptySelectionView: some View {
        Text("Select a view from the sidebar")
            .font(.title)
            .foregroundColor(.secondary)
    }

    // MARK: - Initialization

    private func initializeDataLoader() {
        if dataLoader == nil {
            dataLoader = AppDataLoader(profile: profile)
        }
    }

    #if os(macOS)
    // MARK: - TouchBar

    private var touchBarAccessor: some View {
        TouchBarAccessor(touchBarManager: touchBarManager)
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(true)
    }

    private func updateTouchBarContext(for view: String?) {
        guard let view = view else { return }

        if dataLoader?.isLoading == true {
            touchBarManager.isRefreshing = true
        }

        switch view {
        case "Movies", "Series":
            touchBarManager.switchToContext(.mediaList)
            updateTouchBarCategories()
        case "LiveChannels":
            touchBarManager.switchToContext(.liveTV)
            updateTouchBarChannels()
        case "Downloads":
            touchBarManager.switchToContext(.downloads)
        default:
            break
        }
    }

    private func setupTouchBarCallbacks() {
        touchBarManager.onCancelDownloads = {
            self.downloadManager.cancelAllDownloads()
        }

        touchBarManager.onPlayPause = {
            self.downloadManager.togglePauseResumeAll()
        }

        touchBarManager.onRefresh = {
            Task {
                await self.dataLoader?.mediaViewModel?.refreshMedia(contentType: .all)
            }
        }

        touchBarManager.onSearchTextChange = { text in
            self.touchBarManager.searchText = text
        }

        touchBarManager.onSortChange = { sortOption in
            Task {
                await MainActor.run {
                    let contentType: MediaListViewModel.ContentType = {
                        switch self.selectedView {
                        case "Movies": return .movies
                        case "Series": return .series
                        default: return .all
                        }
                    }()

                    let vmSortOption: MediaListViewModel.SortOption = {
                        switch sortOption {
                        case .nameAsc: return .nameAsc
                        case .nameDesc: return .nameDesc
                        case .dateAsc: return .addedAsc
                        case .dateDesc: return .addedDesc
                        case .rating: return .addedDesc
                        }
                    }()

                    self.dataLoader?.mediaViewModel?.applySort(vmSortOption, to: contentType)
                }
            }
        }

        touchBarManager.onCategoryToggle = { category in
            self.handleCategoryToggle(category)
        }
    }

    private func handleCategoryToggle(_ category: String) {
        if category.isEmpty {
            touchBarManager.selectedCategoryIDs = Set<String>()
            return
        }

        var categoryId: String?

        switch selectedView {
        case "Movies":
            categoryId = dataLoader?.movieCategories.first { $0.categoryName == category }?.categoryId
        case "Series":
            categoryId = dataLoader?.seriesCategories.first { $0.categoryName == category }?.categoryId
        default:
            categoryId = dataLoader?.movieCategories.first { $0.categoryName == category }?.categoryId ??
                         dataLoader?.seriesCategories.first { $0.categoryName == category }?.categoryId
        }

        if let categoryId = categoryId {
            var newCategories = touchBarManager.selectedCategoryIDs
            if newCategories.contains(categoryId) {
                newCategories.remove(categoryId)
            } else {
                newCategories.insert(categoryId)
            }
            touchBarManager.selectedCategoryIDs = newCategories
        }
    }

    private func updateTouchBarCategories() {
        let categories: [String]

        switch selectedView {
        case "Movies":
            categories = dataLoader?.movieCategories.map { $0.categoryName } ?? []
        case "Series":
            categories = dataLoader?.seriesCategories.map { $0.categoryName } ?? []
        default:
            let allCategories = (dataLoader?.movieCategories.map { $0.categoryName } ?? []) +
                               (dataLoader?.seriesCategories.map { $0.categoryName } ?? [])
            categories = Array(Set(allCategories))
        }

        touchBarManager.updateCategories(categories)
    }

    private func updateTouchBarChannels() {
        let channelNames = dataLoader?.liveChannelViewModel?.liveChannels.map { $0.name } ?? []
        touchBarManager.updateChannels(channelNames)
    }
    #endif
}

// MARK: - Preview

#Preview {
    ContentView(showingSettings: .constant(false))
        .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
        .environmentObject(IPTVProfilesManager.shared)
}
