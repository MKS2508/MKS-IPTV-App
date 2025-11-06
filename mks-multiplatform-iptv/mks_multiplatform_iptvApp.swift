import SwiftUI
@main
struct mks_iptv_downloaderApp: App {
    @StateObject var profilesManager = IPTVProfilesManager.shared
    @State private var showingSettings = false
    
    var activeProfile: IPTVProfile? { profilesManager.activeProfile }

    var body: some Scene {
        WindowGroup {
            // Profile selection gating: blocks app until a profile is chosen.
            if let profile = activeProfile {
                ContentView(showingSettings: $showingSettings)
                    .environmentObject(DownloadManager(profile: profile))
                    .environmentObject(profilesManager)
                    .environmentObject(profile)
            } else {
                IPTVProfilesView(manager: profilesManager)
            }
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    showingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandGroup(after: .appSettings) {
                Button("Switch Profile...") {
                    showingSettings = true
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])
            }
        }
        #endif
    }
}

struct ContentView: View {
    @Binding var showingSettings: Bool
    @State private var selectedView: String? = "Movies"
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var profilesManager: IPTVProfilesManager
    @EnvironmentObject private var profile: IPTVProfile
    
    @State private var mediaViewModel: MediaListViewModel?
    @State private var liveChannelViewModel: LiveChannelListViewModel?
    @State private var movieService: MovieService?
    
    #if os(macOS)
    @StateObject private var touchBarManager = TouchBarManager()
    #endif
    
    init(showingSettings: Binding<Bool>) {
        self._showingSettings = showingSettings
        #if os(macOS)
        print("📱 TouchBar: Initializing ContentView with TouchBarManager")
        #endif
    }
    
    @State private var movieCategories: [MovieCategory] = []
    @State private var seriesCategories: [SeriesCategory] = []
    @State private var liveChannelCategories: [LiveChannelCategory] = []
    @State private var isLoading = true
    @State private var loadingStatus = "Initializing..."
    
    // Animation states for loading view
    @State private var animatingScale = false
    @State private var animatingRotation = false
    @State private var animatingOpacity = false
    @State private var animatingDots = [false, false, false]

    var body: some View {
        ZStack {
            // Fondo aplicado aquí
            Image("backgroundPattern")
                .resizable(resizingMode: .tile)
                .ignoresSafeArea()
             
            // Contenido principal
            Group {
                if isLoading {
                    loadingView
                        .transition(.opacity)
                } else {
                    PlatformNavigationView(
                        sidebarContent: { sidebarContent },
                        detailContent: { detailContent },
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
            .animation(.easeInOut(duration: 0.3), value: isLoading)
            
            #if os(macOS)
            // TouchBar Accessor (invisible but enables TouchBar)
            TouchBarAccessor(touchBarManager: touchBarManager)
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(true)
            #endif
        }
        .onAppear {
            initializeViewModelsIfNeeded()
        }
        .task {
            await load_VOD_and_LIVE_categories()
        }
        #if os(macOS)
        .onChange(of: selectedView) { _, newValue in
            updateTouchBarContext(for: newValue)
        }
        .onAppear {
            setupTouchBarCallbacks()
            updateTouchBarContext(for: selectedView)
        }
        #endif
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(profilesManager)
        }
    }
    
    // MARK: - Initialization
    
    private func initializeViewModelsIfNeeded() {
        // Initialize services and ViewModels with the environment profile
        if movieService == nil {
            movieService = MovieService(profile: profile)
        }
        
        if mediaViewModel == nil, let service = movieService {
            mediaViewModel = MediaListViewModel(movieService: service)
        }
        
        if liveChannelViewModel == nil {
            liveChannelViewModel = LiveChannelListViewModel(profile: profile)
        }
    }
    
    private var loadingView: some View {
        ZStack {
            // Background with animated gradient
            #if os(iOS)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.05),  // Near black
                    Color(red: 0.15, green: 0.05, blue: 0.05),  // Dark red tint
                    Color(red: 0.1, green: 0.05, blue: 0.05)    // Darker red tint
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(
                // Subtle red glow overlay
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.15),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 100,
                    endRadius: 400
                )
                .ignoresSafeArea()
            )
            #else
            // macOS background with dark theme
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.05)
                    .ignoresSafeArea()
                
                VisualEffect(blurStyle: .dark, vibrancy: true, opacity: 0.3)
                    .ignoresSafeArea()
                
                // Subtle red glow
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.1),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 100,
                    endRadius: 400
                )
                .ignoresSafeArea()
            }
            #endif
            
            VStack(spacing: 30) {
                // Custom animated logo
                ZStack {
                    // Outer glow circle
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.3),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 50,
                                endRadius: 80
                            )
                        )
                        .frame(width: 140, height: 140)
                        .blur(radius: 10)
                    
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.863, green: 0.165, blue: 0.157),  // Primary red
                                    Color(red: 0.502, green: 0.000, blue: 0.000)   // Dark red
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.5),
                                            Color(red: 0.3, green: 0.0, blue: 0.0).opacity(0.3)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .scaleEffect(animatingScale ? 1.1 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: animatingScale
                        )
                    
                    Image(systemName: "tv.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
                        .rotationEffect(.degrees(animatingRotation ? 5 : -5))
                        .animation(
                            Animation.easeInOut(duration: 2)
                                .repeatForever(autoreverses: true),
                            value: animatingRotation
                        )
                }
                .shadow(color: Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.6), radius: 30, x: 0, y: 15)
                
                VStack(spacing: 12) {
                    Text("IPTV Player")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(animatingOpacity ? 1 : 0.7)
                        .animation(
                            Animation.easeInOut(duration: 1)
                                .repeatForever(autoreverses: true),
                            value: animatingOpacity
                        )
                    
                    Text(loadingStatus)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    // Progress dots animation for both platforms
                    HStack(spacing: 10) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.863, green: 0.165, blue: 0.157),
                                            Color(red: 0.502, green: 0.000, blue: 0.000)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                                .scaleEffect(animatingDots[index] ? 1.5 : 0.8)
                                .opacity(animatingDots[index] ? 1.0 : 0.5)
                                .animation(
                                    Animation.easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                    value: animatingDots[index]
                                )
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .onAppear {
                animatingScale = true
                animatingRotation = true
                animatingOpacity = true
                for index in 0..<3 {
                    animatingDots[index] = true
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading \(loadingStatus)")
    }
   
    private var sidebarContent: some View {
        List(selection: $selectedView) {
            NavigationLink(value: "Movies") {
                Label("Movies", systemImage: "film")
            }
            
            NavigationLink(value: "Series") {
                Label("Series", systemImage: "tv")
            }
            
            NavigationLink(value: "LiveChannels") {
                Label("Live TV", systemImage: "antenna.radiowaves.left.and.right")
            }
            
            NavigationLink(value: "Downloads") {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            
            #if DEBUG
            Section {
                NavigationLink(value: "DebugStream") {
                    Label("Debug Stream", systemImage: "ant.circle")
                        .foregroundColor(.orange)
                }
            } header: {
                Text("Development")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            #endif
        }
        .accessibilityLabel("Main Navigation")
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selectedView = selectedView {
            switch selectedView {
            case "Movies":
                if let mediaViewModel = mediaViewModel {
                    MediaListView(
                        viewModel: mediaViewModel,
                        selectedView: $selectedView,
                        movieCategories: movieCategories,
                        seriesCategories: [],
                        initialContentType: .movies,
                        showContentTypeSelector: false
                    )
                    #if os(macOS)
                    .environmentObject(touchBarManager)
                    #endif
                } else {
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }
            case "Series":
                if let mediaViewModel = mediaViewModel {
                    MediaListView(
                        viewModel: mediaViewModel,
                        selectedView: $selectedView,
                        movieCategories: [],
                        seriesCategories: seriesCategories,
                        initialContentType: .series,
                        showContentTypeSelector: false
                    )
                    #if os(macOS)
                    .environmentObject(touchBarManager)
                    #endif
                } else {
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }
            case "LiveChannels":
                // Switched to new LiveChannelsGridView (fully modern, grid-based UI).
                if let liveChannelVM = liveChannelViewModel {
                    LiveChannelsGridView()
                        .environmentObject(profile)
                        .environmentObject(liveChannelVM)
                    #if os(macOS)
                    .environmentObject(touchBarManager)
                    #endif
                    .navigationTitle("Live TV")
                } else {
                    Text("Loading Live TV...")
                        .foregroundColor(.secondary)
                }
            case "Downloads":
                DownloadsView()
                #if os(macOS)
                .environmentObject(touchBarManager)
                #endif
                .navigationTitle("Downloads")
            #if DEBUG
            case "DebugStream":
                if let movieService = movieService {
                    DebugStreamingView(movieService: movieService)
                        .navigationTitle("Debug Stream")
                } else {
                    Text("Loading...")
                        .foregroundColor(.secondary)
                }
            #endif
            default:
                Text("Select a view from the sidebar")
                    .font(.title)
                    .foregroundColor(.secondary)
            }
        } else {
            Text("Select a view from the sidebar")
                .font(.title)
                .foregroundColor(.secondary)
        }
    }

    private func load_VOD_and_LIVE_categories() async {
        do {
            // Ensure ViewModels are initialized
            initializeViewModelsIfNeeded()
            
            guard let movieService = movieService else {
                loadingStatus = "Profile not available"
                return
            }
            
            loadingStatus = "Connecting to server..."
            async let movieCategoriesTask = movieService.fetchMovieCategories()
            async let seriesCategoriesTask = movieService.fetchSeriesCategories()
            async let liveChannelCategoriesTask = movieService.fetchLiveChannelsCategories()
            
            let (fetchedMovieCategories, fetchedSeriesCategories, fetchedLiveChannelCategories) = try await (movieCategoriesTask, seriesCategoriesTask, liveChannelCategoriesTask)
            
            movieCategories = fetchedMovieCategories
            seriesCategories = fetchedSeriesCategories
            liveChannelCategories = fetchedLiveChannelCategories
            
            print("Categories loaded: \(movieCategories.count) movie categories, \(seriesCategories.count) series categories, \(liveChannelCategories.count) live channels categories")
            
            #if os(macOS)
            // Update TouchBar categories immediately after loading
            await MainActor.run {
                updateTouchBarCategories()
                updateTouchBarChannels()
            }
            #endif
            
            loadingStatus = "Loading your movie library..."
            if let mediaViewModel = mediaViewModel {
                await mediaViewModel.loadMedia(contentType: .all)
            }
            
            loadingStatus = "Preparing live TV channels..."
            if let liveChannelViewModel = liveChannelViewModel {
                await liveChannelViewModel.loadChannels()
            }
            
            #if os(macOS)
            // Update TouchBar again after live channels are loaded
            await MainActor.run {
                updateTouchBarChannels()
            }
            #endif
            
            loadingStatus = "Almost ready..."
            try await Task.sleep(nanoseconds: 800_000_000) // 0.8 second delay for smoother transition
            
            // Add a fade transition on both platforms
            withAnimation(.easeOut(duration: 0.3)) {
                isLoading = false
            }
        } catch {
            print("Error loading data: \(error.localizedDescription)")
            loadingStatus = "Connection error. Please check your internet."
            // Handle the error appropriately, e.g., show an alert to the user
        }
    }
    
    #if os(macOS)
    // MARK: - TouchBar Support
    
    private func getCategoryName(for categoryId: String) -> String? {
        switch selectedView {
        case "Movies":
            return movieCategories.first { $0.categoryId == categoryId }?.categoryName
        case "Series":
            return seriesCategories.first { $0.categoryId == categoryId }?.categoryName
        default:
            // Check both movie and series categories
            return movieCategories.first { $0.categoryId == categoryId }?.categoryName ??
                   seriesCategories.first { $0.categoryId == categoryId }?.categoryName
        }
    }
    
    private func updateTouchBarContext(for view: String?) {
        guard let view = view else { return }
        
        print("TouchBar: Switching context for view: \(view)")
        
        // Add loading state indicator for TouchBar
        if isLoading {
            touchBarManager.isRefreshing = true
        }
        
        switch view {
        case "Movies", "Series":
            print("TouchBar: Switching to mediaList context")
            touchBarManager.switchToContext(.mediaList)
            updateTouchBarCategories()
        case "LiveChannels":
            print("TouchBar: Switching to liveTV context")
            touchBarManager.switchToContext(.liveTV)
            updateTouchBarChannels()
        case "Downloads":
            print("TouchBar: Switching to downloads context")
            touchBarManager.switchToContext(.downloads)
        default:
            print("TouchBar: Unknown view: \(view)")
            break
        }
    }
    
    private func setupTouchBarCallbacks() {
        // Downloads callbacks
        touchBarManager.onCancelDownloads = {
            self.downloadManager.cancelAllDownloads()
        }
        
        touchBarManager.onPlayPause = {
            self.downloadManager.togglePauseResumeAll()
        }
        
        // Media list callbacks
        touchBarManager.onRefresh = {
            Task {
                if let mediaViewModel = self.mediaViewModel {
                    await mediaViewModel.refreshMedia(contentType: .all)
                }
            }
        }
        
        touchBarManager.onSearchTextChange = { text in
            // TouchBarManager will handle the state update
            self.touchBarManager.searchText = text
            print("TouchBar: Search text changed to: \(text)")
        }
        
        touchBarManager.onSortChange = { sortOption in
            // Apply sort to the media view model
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
                        case .rating: return .addedDesc // Default to newest for rating
                        }
                    }()
                    
                    if let mediaViewModel = self.mediaViewModel {
                        mediaViewModel.applySort(vmSortOption, to: contentType)
                    }
                }
            }
            print("TouchBar: Sort option changed to: \(sortOption)")
        }
        
        touchBarManager.onCategoryToggle = { category in
            print("TouchBar: onCategoryToggle called with: '\(category)'")
            
            if category.isEmpty {
                // Show all categories - clear selection
                print("TouchBar: Clearing all category selections")
                self.touchBarManager.selectedCategoryIDs = Set<String>()
            } else {
                // Find the category ID from category name
                var categoryId: String? = nil
                
                switch self.selectedView {
                case "Movies":
                    categoryId = self.movieCategories.first { $0.categoryName == category }?.categoryId
                case "Series":
                    categoryId = self.seriesCategories.first { $0.categoryName == category }?.categoryId
                default:
                    // Check both movie and series categories
                    categoryId = self.movieCategories.first { $0.categoryName == category }?.categoryId ??
                                self.seriesCategories.first { $0.categoryName == category }?.categoryId
                }
                
                print("TouchBar: Found category ID '\(categoryId ?? "nil")' for name '\(category)'")
                
                if let categoryId = categoryId {
                    // Update TouchBarManager's selectedCategoryIDs
                    var newCategories = self.touchBarManager.selectedCategoryIDs
                    if newCategories.contains(categoryId) {
                        newCategories.remove(categoryId)
                        print("TouchBar: Removed category ID '\(categoryId)'")
                    } else {
                        newCategories.insert(categoryId)
                        print("TouchBar: Added category ID '\(categoryId)'")
                    }
                    // Update the TouchBarManager
                    self.touchBarManager.selectedCategoryIDs = newCategories
                }
            }
            print("TouchBar: After toggle - selected IDs: \(self.touchBarManager.selectedCategoryIDs)")
        }
    }
    
    private func updateTouchBarCategories() {
        var categories: [String] = []
        
        // Add categories based on current view
        switch selectedView {
        case "Movies":
            categories = movieCategories.map { $0.categoryName }
            print("TouchBar: Updating with \(categories.count) movie categories")
        case "Series":
            categories = seriesCategories.map { $0.categoryName }
            print("TouchBar: Updating with \(categories.count) series categories")
        default:
            // For other views, combine all categories
            let allCategories = movieCategories.map { $0.categoryName } + 
                               seriesCategories.map { $0.categoryName }
            categories = Array(Set(allCategories))
            print("TouchBar: Updating with \(categories.count) combined categories")
        }
        
        touchBarManager.updateCategories(categories)
    }
    
    private func updateTouchBarChannels() {
        let channelNames = liveChannelViewModel?.liveChannels.map { $0.name } ?? []
        touchBarManager.updateChannels(channelNames)
    }
    #endif
}

// Preview provider with platform-specific previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView(showingSettings: Binding.constant(false))
                .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
                .environmentObject(IPTVProfilesManager.shared)
                .previewDisplayName("macOS")
                
            #if canImport(UIKit)
            ContentView(showingSettings: Binding.constant(false))
                .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
                .environmentObject(IPTVProfilesManager.shared)
                .previewDevice("iPad Pro (12.9-inch) (6th generation)")
                .previewDisplayName("iPad")
                
            ContentView(showingSettings: Binding.constant(false))
                .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
                .environmentObject(IPTVProfilesManager.shared)
                .previewDevice("iPhone 14 Pro")
                .previewDisplayName("iPhone")
            #endif
        }
    }
}

