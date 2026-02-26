import SwiftUI
import AVKit

/// Modern Live TV grid UI, with adaptive cards, filter bar, search, and efficient layout for both macOS & iOS.
/// Replaces all old list/column UX. Always uses the active profile from ProfilesManager.
struct LiveChannelsGridView: View {
    @EnvironmentObject var profile: IPTVProfile
    @EnvironmentObject var viewModel: LiveChannelListViewModel
    @State private var selectedCategories: Set<String> = []
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var categoriesCache: [LiveChannelCategory] = []
    @Namespace private var animation
    @State private var showingPlayer: Bool = false
    @State private var selectedChannel: LiveChannel? = nil
    @State private var viewMode: ViewMode = .grid
    
    enum ViewMode {
        case grid       // All channels in one grid
        case categories // Grouped by categories with sections
    }

    // Optimized grid layout for mass channel display
    #if os(iOS)
    private let cardMinWidth: CGFloat = 120
    private let cardMaxWidth: CGFloat = 160
    private let gridSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 16
    #else
    private let cardMinWidth: CGFloat = 140
    private let cardMaxWidth: CGFloat = 180
    private let gridSpacing: CGFloat = 14
    private let horizontalPadding: CGFloat = 20
    #endif

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: cardMaxWidth), spacing: gridSpacing, alignment: .top)]
    }


    var body: some View {
        contentView
        .navigationTitle("Live TV")
        .searchable(text: $searchText, prompt: "Search live channels")
        .refreshable {
            await viewModel.refreshChannels()
        }
        .toolbar {
            toolbarContent
        }
        .sheet(item: $selectedChannel) {
            LiveChannelDetailSheet(channel: $0, onClose: { selectedChannel = nil })
        }
        .onAppear {
            if viewModel.liveChannels.isEmpty {
                Task { await viewModel.loadChannels() }
            }
        }
        .onChange(of: searchText) { _, newValue in
            // Debounce search to improve performance
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if searchText == newValue {
                    debouncedSearchText = newValue
                }
            }
        }
    }
    
    // MARK: - Toolbar Content
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // View Mode Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewMode = viewMode == .grid ? .categories : .grid
                    if viewMode == .grid {
                        selectedCategories.removeAll() // Clear filters when switching to grid
                    }
                }
            }) {
                Image(systemName: viewMode == .grid ? "square.grid.3x3" : "list.bullet.below.rectangle")
                    .font(.title2)
            }
            .help(viewMode == .grid ? "Group by Categories" : "Show All in Grid")
            
            // Category Filter Menu (only show in grid mode)
            if viewMode == .grid {
                Menu {
                    Button(action: { selectedCategories.removeAll() }) {
                        Label("Show All (\(viewModel.liveChannels.count))", systemImage: "tv")
                    }
                    
                    Divider()
                    
                    ForEach(Array(categories.prefix(10)), id: \.categoryId) { category in
                        Button(action: {
                            if selectedCategories.contains(category.categoryId) {
                                selectedCategories.remove(category.categoryId)
                            } else {
                                selectedCategories = [category.categoryId]
                            }
                        }) {
                            Label(category.categoryName, systemImage: selectedCategories.contains(category.categoryId) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.title2)
                }
                .help("Filter by category")
            }
        }
    }


    // MARK: - Main Content
    private var contentView: some View {
        Group {
            if viewMode == .grid {
                MediaGridContainer(
                    content: {
                        ForEach(filteredChannels, id: \.streamId) { channel in
                            LiveChannelGridCard(channel: channel)
                                .onTapGesture {
                                    selectedChannel = channel
                                }
                                .id(channel.streamId)
                        }
                    },
                    isEmpty: filteredChannels.isEmpty,
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    onRetry: {
                        Task { await viewModel.refreshChannels() }
                    }
                )
            } else {
                // Category sections view with proper container
                MediaGridContainer(
                    content: {
                        LazyVStack(spacing: 24, pinnedViews: [.sectionHeaders]) {
                            ForEach(categories, id: \.categoryId) { category in
                                let categoryChannels = channelsForCategory(category.categoryId)
                                
                                if !categoryChannels.isEmpty {
                                    Section {
                                        ForEach(categoryChannels, id: \.streamId) { channel in
                                            LiveChannelGridCard(channel: channel)
                                                .onTapGesture {
                                                    selectedChannel = channel
                                                }
                                                .id(channel.streamId)
                                        }
                                    } header: {
                                        categoryHeader(category: category)
                                    }
                                }
                            }
                        }
                    },
                    isEmpty: viewModel.liveChannels.isEmpty,
                    isLoading: viewModel.isLoading,
                    error: viewModel.error,
                    onRetry: {
                        Task { await viewModel.refreshChannels() }
                    }
                )
            }
        }
    }
    
    
    private func categoryHeader(category: LiveChannelCategory) -> some View {
        let channelCount = channelsForCategory(category.categoryId).count
        
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(categoryDisplayName(for: category.categoryId))
                    .font(.title2.bold())
                    .foregroundColor(.white)
                
                Text("\(channelCount) canales")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Category icon
            Image(systemName: categoryIcon(for: category.categoryId))
                .font(.title2)
                .foregroundColor(categoryBadgeColor(for: category.categoryId))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 12)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, horizontalPadding)
    }
    
    private func channelsForCategory(_ categoryId: String) -> [LiveChannel] {
        let filtered = viewModel.filterChannels(searchText: debouncedSearchText)
        return filtered.filter { $0.categoryId == categoryId }
    }
    
    private func categoryIcon(for categoryId: String) -> String {
        let icons: [String: String] = [
            "145": "speaker.wave.3",      // Anuncios  
            "147": "soccerball",          // Deportes
            "148": "newspaper",           // Noticias
            "149": "tv",                  // Entretenimiento
            "150": "globe",               // Internacional
            "151": "music.note",          // Música
            "152": "person.2",            // Infantil
            "153": "book",                // Documentales
            "154": "film"                 // Películas
        ]
        
        return icons[categoryId] ?? "tv"
    }
    
    private func categoryBadgeColor(for categoryId: String) -> Color {
        let colors: [String: Color] = [
            "145": .orange,   // Anuncios
            "147": .blue,     // Deportes  
            "148": .green,    // Noticias
            "149": .purple,   // Entretenimiento
            "150": .cyan,     // Internacional
            "151": .pink,     // Música
            "152": .yellow,   // Infantil
            "153": .brown,    // Documentales
            "154": .red       // Películas
        ]
        
        return colors[categoryId] ?? .gray
    }

    // MARK: - Filtered Data
    private var categories: [LiveChannelCategory] {
        // Use cached categories or generate minimal ones
        if !categoriesCache.isEmpty {
            return categoriesCache
        }
        
        // Extract unique categories from channels with better naming
        let uniqueCategoryIds = Set(viewModel.liveChannels.compactMap { $0.categoryId })
        let result = uniqueCategoryIds.compactMap { categoryId -> LiveChannelCategory? in
            let categoryName = categoryDisplayName(for: categoryId)
            let channelCount = viewModel.liveChannels.filter { $0.categoryId == categoryId }.count
            
            // Only include categories with channels
            guard channelCount > 0 else { return nil }
            
            return LiveChannelCategory(
                categoryId: categoryId,
                categoryName: "\(categoryName) (\(channelCount))",
                parentId: 0
            )
        }.sorted { $0.categoryName < $1.categoryName }
        
        // Cache the result to avoid recomputation
        categoriesCache = result
        return result
    }
    
    private func categoryDisplayName(for categoryId: String) -> String {
        // Map known category IDs to meaningful names
        let categoryNames: [String: String] = [
            "145": "Anuncios",
            "147": "Deportes", 
            "148": "Noticias",
            "149": "Entretenimiento",
            "150": "Internacional",
            "151": "Música",
            "152": "Infantil",
            "153": "Documentales",
            "154": "Películas"
        ]
        
        return categoryNames[categoryId] ?? "Categoría \(categoryId)"
    }

    private var filteredChannels: [LiveChannel] {
        let searchFiltered = viewModel.filterChannels(searchText: debouncedSearchText)
        print("🔍 filteredChannels: searchFiltered count = \(searchFiltered.count)")
        print("🔍 filteredChannels: selectedCategories = \(selectedCategories)")
        print("🔍 filteredChannels: selectedCategories.isEmpty = \(selectedCategories.isEmpty)")
        
        let result = searchFiltered.filter { ch in
            let shouldInclude = selectedCategories.isEmpty || selectedCategories.contains(ch.categoryId ?? "0")
            if !shouldInclude {
                print("🔍 filteredChannels: excluding channel \(ch.name) with categoryId \(ch.categoryId ?? "0")")
            }
            return shouldInclude
        }
        
        print("🔍 filteredChannels: final result count = \(result.count)")
        return result
    }
}

// MARK: - Detail Sheet
struct LiveChannelDetailSheet: View {
    let channel: LiveChannel
    let onClose: () -> Void
    
    @EnvironmentObject var profile: IPTVProfile
    @State private var showInlinePlayer = false
    @State private var activePlayer: (any VideoPlayerProtocol)?
    @State private var isLoading = false
    @State private var showKSPlayerView = false
    @State private var ksPlayerURL: URL?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header with channel info
                VStack(spacing: 12) {
                    // Channel icon
                    CachedAsyncImage(url: URL(string: channel.streamIcon ?? "")) { phase in
                        switch phase {
                        case .empty:
                            SkeletonLoader()
                                .frame(width: 80, height: 80)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        case .failure:
                            Image(systemName: "tv")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    
                    // Channel name and live badge
                    VStack(spacing: 8) {
                        Text(channel.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        
                        HStack(spacing: 12) {
                            Text("LIVE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.red))
                            
                            if !(channel.categoryId?.isEmpty ?? true) {
                                Text("Canal \(channel.categoryId ?? "0")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                // Video player area
                VStack(spacing: 16) {
                    if showInlinePlayer {
                        if let player = activePlayer {
                            MKSPlayerView(player: player)
                                .frame(height: 250)
                                .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                                        .stroke(Color.accentColor, lineWidth: 2)
                                )
                        } else if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Cargando stream...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: 250)
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                        }
                    } else {
                        // Placeholder when not playing
                        VStack(spacing: 16) {
                            Image(systemName: "play.tv")
                                .font(.system(size: 48))
                                .foregroundColor(.accentColor)

                            Text("Toca reproducir para ver el canal en vivo")
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 250)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(12)
                    }
                    
                    // Control buttons
                    VStack(spacing: 16) {
                        // Primary buttons row
                        HStack(spacing: 16) {
                            // Play/Stop button
                            Button(action: togglePlayback) {
                                HStack(spacing: 8) {
                                    Image(systemName: showInlinePlayer ? "stop.fill" : "play.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text(showInlinePlayer ? "Detener" : "Reproducir")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(showInlinePlayer ? Color.red : Color.accentColor)
                                .cornerRadius(25)
                            }
                            .disabled(isLoading)
                            
                            // Copy URL button
                            Button(action: copyChannelURL) {
                                Image(systemName: "link")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.secondary)
                                    .cornerRadius(20)
                            }
                        }
                        
                        // External players row
                        HStack(spacing: 16) {
                            // KSPlayer button (only if available)
                            if KSPlayerImplementation.isAvailable() {
                                Button(action: playWithKSPlayer) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.rectangle")
                                            .font(.system(size: 14, weight: .semibold))
                                        Text("KSPlayer")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(Color.purple)
                                    .cornerRadius(20)
                                }
                            }
                            
                            // Open in VLC button
                            OpenInVLCButton(urlProvider: {
                                return IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                            }, label: "VLC")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(20)
                        }
                        .font(.system(size: 14, weight: .semibold))
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle(channel.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        cleanUpPlayer()
                        onClose()
                    }
                }
            }
        }
        .onDisappear {
            cleanUpPlayer()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showKSPlayerView) {
            if let url = ksPlayerURL {
                KSPlayerFullScreenView(url: url, onClose: {
                    showKSPlayerView = false
                    ksPlayerURL = nil
                })
            }
        }
        #else
        .sheet(isPresented: $showKSPlayerView) {
            if let url = ksPlayerURL {
                KSPlayerFullScreenView(url: url, onClose: {
                    showKSPlayerView = false
                    ksPlayerURL = nil
                })
                .frame(minWidth: 800, minHeight: 600)
            }
        }
        #endif
    }
    
    // MARK: - Functions
    private func togglePlayback() {
        if showInlinePlayer {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        isLoading = true
        LiveLogger.debug("Starting playback for channel: \(channel.name)")

        guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: urlString) else {
            LiveLogger.error("Failed to generate valid stream URL")
            isLoading = false
            return
        }

        let player = PlayerFactory.shared.createPlayer(for: url)
        player.play()
        self.activePlayer = player
        self.showInlinePlayer = true
        self.isLoading = false
        LiveLogger.debug("Playback started via PlayerFactory")
    }
    
    private func stopPlayback() {
        cleanUpPlayer()
    }

    private func cleanUpPlayer() {
        activePlayer?.stop()
        activePlayer = nil
        showInlinePlayer = false
        isLoading = false
    }
    
    private func copyChannelURL() {
        let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        #else
        UIPasteboard.general.string = urlString
        #endif
        
        LiveLogger.debug("URL del canal copiada al portapapeles: \(urlString)")
    }
    
    private func playWithKSPlayer() {
        LiveLogger.debug("Opening channel in KSPlayer: \(channel.name)")
        
        guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: urlString) else {
            LiveLogger.error("Failed to generate valid stream URL for KSPlayer")
            return
        }
        
        LiveLogger.debug("KSPlayer URL: \(url.absoluteString)")
        
        // Set URL and show KSPlayer fullscreen
        ksPlayerURL = url
        showKSPlayerView = true
        
        LiveLogger.debug("KSPlayer fullscreen view presented")
    }
}

// MARK: - KSPlayer FullScreen View
struct KSPlayerFullScreenView: View {
    let url: URL
    let onClose: () -> Void

    @State private var activePlayer: (any VideoPlayerProtocol)?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let player = activePlayer {
                MKSPlayerView(
                    player: player,
                    onDismiss: onClose
                )
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Cargando KSPlayer...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
            }
        }
        .onAppear {
            let player = PlayerFactory.shared.createPlayer(type: .ksplayer, url: url)
            player.play()
            activePlayer = player
        }
        .onDisappear {
            activePlayer?.stop()
            activePlayer = nil
        }
    }
}
