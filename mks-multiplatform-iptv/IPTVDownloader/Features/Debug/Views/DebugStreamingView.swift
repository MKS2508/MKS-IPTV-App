import SwiftUI
import AVKit
import Combine

#if os(macOS)
import AppKit
#endif

struct DebugStreamingView: View {
    @StateObject private var viewModel: DebugStreamingViewModel
    @EnvironmentObject var profile: IPTVProfile
    @State private var selectedTab = ContentTab.movies
    @State private var selectedItem: DebugStreamItem?
    @State private var showingPlayer = false
    @State private var currentPlayer: AVPlayer?
    @State private var showingEpisodePicker = false
    @State private var selectedSerieForEpisodes: DebugStreamItem?
    @State private var selectedLiveTVCategory: String = "all"
    @State private var showingCategoryURLs = false
    
    // Stream compatibility handler
    private let streamCompatibilityHandler = StreamCompatibilityHandler()
    
    enum ContentTab: String, CaseIterable {
        case movies = "Movies"
        case series = "Series"
        case mixed = "Mixed"
        case liveTV = "Live TV"
        
        var icon: String {
            switch self {
            case .movies: return "film"
            case .series: return "tv"
            case .mixed: return "square.grid.2x2"
            case .liveTV: return "tv.circle"
            }
        }
    }
    
    init(movieService: MovieService) {
        self._viewModel = StateObject(wrappedValue: DebugStreamingViewModel(movieService: movieService))
    }
    
    var body: some View {
        mainContent
            .background(VisualEffect().ignoresSafeArea())
            .sheet(isPresented: $showingPlayer) {
                if let player = currentPlayer {
                    VideoPlayer(player: player)
                        .frame(width: 800, height: 600)
                }
            }
            .task {
                await viewModel.loadContent(type: selectedTab, liveTVCategory: selectedLiveTVCategory)
            }
            .sheet(item: $selectedSerieForEpisodes) { serie in
                SeriesEpisodePickerView(
                    serie: serie,
                    onEpisodeSelected: { episode in
                        testEpisodeStream(serie: serie, episode: episode)
                    },
                    onDismiss: {
                        selectedSerieForEpisodes = nil
                    }
                )
            }
            .sheet(isPresented: $showingCategoryURLs) {
                CategorySelectionView(viewModel: viewModel)
            }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        VSplitView {
            // Top section: Content selector and list
            VStack(spacing: 0) {
                // Tab selector
                tabSelector
                    .padding(.top)
                    .padding(.horizontal)
                
                Divider()
                    .padding(.top, 8)
                
                // Content list
                contentList
            }
            .frame(minHeight: 300)
            
            // Bottom section: Logs and details
            HSplitView {
                // Logs panel
                logsPanel
                    .frame(minWidth: 400)
                
                // Details panel
                if let selectedItem = selectedItem {
                    detailsPanel(for: selectedItem)
                        .frame(minWidth: 300)
                } else {
                    emptyDetailsPanel
                        .frame(minWidth: 300)
                }
            }
            .frame(minHeight: 300)
        }
        #else
        VStack(spacing: 0) {
            // Tab selector
            tabSelector
                .padding(.top)
                .padding(.horizontal)
            
            Divider()
                .padding(.top, 8)
            
            // Content list
            contentList
                .frame(maxHeight: 300)
            
            Divider()
            
            // Logs and details in tabs for iOS
            TabView {
                logsPanel
                    .tabItem {
                        Label("Logs", systemImage: "doc.text")
                    }
                
                if let selectedItem = selectedItem {
                    detailsPanel(for: selectedItem)
                        .tabItem {
                            Label("Details", systemImage: "info.circle")
                        }
                }
            }
        }
        #endif
    }
    
    // MARK: - Tab Selector
    private var tabSelector: some View {
        HStack {
            Picker("Content Type", selection: $selectedTab) {
                ForEach(ContentTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 400)
            
            // Live TV Category Picker
            if selectedTab == .liveTV {
                Picker("Category", selection: $selectedLiveTVCategory) {
                    Text("All").tag("all")
                    ForEach(viewModel.liveTVCategories, id: \.categoryId) { category in
                        Text(category.categoryName).tag(category.categoryId)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: { Task { await viewModel.loadContent(type: selectedTab, liveTVCategory: selectedLiveTVCategory) } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button(action: { copyLogsToClipboard() }) {
                    Label("Copy Logs", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                
                Button(action: { exportLogs() }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                
                Button(action: { showingCategoryURLs = true }) {
                    Label("Copy Category URLs", systemImage: "doc.on.doc.fill")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.blue)
                
                Button(action: { viewModel.clearLogs() }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
    }
    
    // MARK: - Content List
    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.items) { item in
                    DebugStreamItemRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        onSelect: { selectedItem = item },
                        onTestStream: { testStream(item) },
                        onTestDirectPlayback: { testDirectPlayback(item) },
                        onTestWithCompatibility: { testWithCompatibility(item) },
                        onTestWithKSPlayer: { testWithKSPlayer(item) },
                        onTestWithVLC: { testWithVLC(item) },
                        onTestAsMP4: { testAsMP4(item) },
                        onTestAsHLS: { testAsHLS(item) },
                        onOpenInVLC: { openInVLC(item) },
                        onShowURLs: { showURLs(item) },
                        onGetDetails: { getDetails(item) },
                        onCopyURL: { url in copyToClipboard(url) },
                        onAnalyzeWithFFprobe: { analyzeWithFFprobe(item) }
                    )
                }
            }
            .padding()
        }
        .onChange(of: selectedTab) {
            Task { await viewModel.loadContent(type: selectedTab, liveTVCategory: selectedLiveTVCategory) }
        }
        .onChange(of: selectedLiveTVCategory) {
            if selectedTab == .liveTV {
                Task { await viewModel.loadContent(type: selectedTab, liveTVCategory: selectedLiveTVCategory) }
            }
        }
    }
    
    // MARK: - Logs Panel
    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Logs")
                    .font(.headline)
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $viewModel.autoScroll)
                    #if os(macOS)
                    .toggleStyle(CheckboxToggleStyle())
                    #else
                    .toggleStyle(SwitchToggleStyle())
                    #endif
                
                Toggle("Verbose", isOn: $viewModel.verboseMode)
                    #if os(macOS)
                    .toggleStyle(CheckboxToggleStyle())
                    #else
                    .toggleStyle(SwitchToggleStyle())
                    #endif
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.logs) { log in
                            DebugLogRow(log: log)
                                .id(log.id)
                        }
                    }
                    .padding(8)
                }
                .background(VisualEffect())
                .onChange(of: viewModel.logs.count) {
                    if viewModel.autoScroll, let lastLog = viewModel.logs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Details Panel
    private func detailsPanel(for item: DebugStreamItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Basic info
                    detailSection(title: "Basic Info") {
                        DetailRow(label: "Title", value: item.title)
                        DetailRow(label: "ID", value: String(item.id))
                        DetailRow(label: "Type", value: item.type == .movie ? "Movie" : "Series")
                        DetailRow(label: "Extension", value: item.fileExtension)
                        DetailRow(label: "Added", value: formatDate(item.added))
                        DetailRow(label: "Category", value: item.categoryId)
                        if let rating = item.rating {
                            DetailRow(label: "Rating", value: String(format: "%.1f", rating))
                        }
                    }
                    
                    // URLs
                    detailSection(title: "URLs") {
                        if let streamURL = item.streamURL {
                            DetailRow(label: "Stream URL", value: streamURL, isMonospaced: true)
                        }
                        if let downloadURL = item.downloadURL {
                            DetailRow(label: "Download URL", value: downloadURL, isMonospaced: true)
                        }
                        if let resolvedURL = item.resolvedURL {
                            DetailRow(label: "Resolved URL", value: resolvedURL, isMonospaced: true)
                        }
                    }
                    
                    // Streaming info
                    if item.hasBeenTested {
                        detailSection(title: "Streaming Info") {
                            if let status = item.playerStatus {
                                DetailRow(label: "Player Status", value: status.description)
                            }
                            if let httpStatus = item.httpStatusCode {
                                DetailRow(label: "HTTP Status", value: String(httpStatus))
                            }
                            DetailRow(label: "Redirects", value: String(item.redirectCount))
                            if let errorCount = item.errors?.count, errorCount > 0 {
                                DetailRow(label: "Errors", value: "\(errorCount) error(s)")
                            }
                        }
                        
                        // Performance metrics
                        detailSection(title: "Performance Metrics") {
                            if let urlTime = item.urlResolutionTime {
                                DetailRow(label: "URL Resolution", value: String(format: "%.2f ms", urlTime * 1000))
                            }
                            if let initTime = item.playerInitTime {
                                DetailRow(label: "Player Init", value: String(format: "%.2f ms", initTime * 1000))
                            }
                            if let totalTime = item.totalLatency {
                                DetailRow(label: "Total Latency", value: String(format: "%.2f ms", totalTime * 1000))
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(VisualEffect())
    }
    
    private var emptyDetailsPanel: some View {
        VStack {
            Text("Select an item to view details")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect())
    }
    
    // MARK: - Helper Views
    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            content()
        }
    }
    
    // MARK: - Actions
    private func testStream(_ item: DebugStreamItem) {
        // For series, show episode picker
        if item.type == .series {
            selectedSerieForEpisodes = item
            return
        }
        
        viewModel.log("🎬 Starting stream test for \"\(item.title)\"", type: .info)
        viewModel.log("📋 Item details:", type: .info)
        viewModel.log("  - ID: \(item.id)", type: .info)
        viewModel.log("  - Type: \(item.type)", type: .info)
        viewModel.log("  - Extension: \(item.fileExtension)", type: .info)
        
        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("❌ Invalid stream URL", type: .error)
            viewModel.log("  - Stream URL was: \(item.streamURL ?? "nil")", type: .error)
            return
        }
        
        viewModel.log("📍 Original URL: \(urlString)", type: .info)
        
        // Check if it's a live stream
        let isLiveStream = item.fileExtension == "ts" || urlString.contains("/live/")
        if isLiveStream {
            viewModel.log("🔴 LIVE CHANNEL detected", type: .info)
        }
        
        // Update item state
        viewModel.updateItemState(item.id, hasBeenTested: true)
        
        // Use DebugStreamManager to resolve and play with metrics
        let streamManager = DebugStreamManager()
        let startTime = Date()
        
        // For live streams, try direct playback first
        if isLiveStream {
            viewModel.log("🔴 Attempting direct live stream playback", type: .info)
            streamManager.setupStreamPlayerWithMetrics(with: url) { player, playerMetrics in
                DispatchQueue.main.async {
                    if let player = player {
                        let totalTime = Date().timeIntervalSince(startTime)
                        viewModel.log("🎮 Live stream player initialized", type: .success)
                        viewModel.log("📊 Total latency: \(String(format: "%.2f ms", totalTime * 1000))", type: .info)
                        
                        self.currentPlayer = player
                        self.showingPlayer = true
                        player.play()
                        viewModel.log("▶️ Live stream playback started", type: .info)
                    } else {
                        viewModel.log("❌ Failed to initialize live stream player", type: .error)
                        if let error = playerMetrics.error {
                            viewModel.log("\(error.type.icon) Player Error: \(error.description)", type: .error)
                        }
                        // If direct playback fails, try URL resolution
                        viewModel.log("🔄 Falling back to URL resolution", type: .warning)
                        self.resolveAndPlay(item: item, url: url, streamManager: streamManager, startTime: startTime)
                    }
                }
            }
        } else {
            // For non-live streams, use the standard resolution process
            self.resolveAndPlay(item: item, url: url, streamManager: streamManager, startTime: startTime)
        }
    }
    
    private func resolveAndPlay(item: DebugStreamItem, url: URL, streamManager: DebugStreamManager, startTime: Date) {
        streamManager.resolveStreamURLWithMetrics(from: url) { resolvedUrl, metrics in
            DispatchQueue.main.async {
                if let resolvedUrl = resolvedUrl {
                    viewModel.log("✅ Resolved URL: \(resolvedUrl.absoluteString)", type: .success)
                    viewModel.log("📊 Resolution time: \(String(format: "%.2f ms", (metrics.urlResolutionTime ?? 0) * 1000))", type: .info)
                    viewModel.log("🔄 Redirects: \(metrics.redirectCount)", type: .info)
                    if let statusCode = metrics.httpStatusCode {
                        viewModel.log("📡 HTTP Status: \(statusCode)", type: .info)
                    }
                    
                    viewModel.updateItemState(item.id, 
                        resolvedURL: resolvedUrl.absoluteString,
                        urlResolutionTime: metrics.urlResolutionTime,
                        httpStatusCode: metrics.httpStatusCode,
                        redirectCount: metrics.redirectCount
                    )
                    
                    viewModel.log("🔧 Setting up player...", type: .info)
                    streamManager.setupStreamPlayerWithMetrics(with: resolvedUrl) { player, playerMetrics in
                        DispatchQueue.main.async {
                        if let player = player {
                            let totalTime = Date().timeIntervalSince(startTime)
                            viewModel.log("🎮 Player initialized successfully", type: .success)
                            viewModel.log("📊 Player init time: \(String(format: "%.2f ms", (playerMetrics.playerInitTime ?? 0) * 1000))", type: .info)
                            viewModel.log("📊 Total latency: \(String(format: "%.2f ms", totalTime * 1000))", type: .info)
                            
                            viewModel.updateItemState(item.id,
                                playerInitTime: playerMetrics.playerInitTime,
                                totalLatency: totalTime
                            )
                            
                            self.currentPlayer = player
                            self.showingPlayer = true
                            player.play()
                            viewModel.log("▶️ Playback started", type: .info)
                        } else {
                            viewModel.log("❌ Failed to initialize player", type: .error)
                            if let error = playerMetrics.error {
                                viewModel.log("\(error.type.icon) Player Error: \(error.description)", type: .error)
                                if let context = error.context {
                                    viewModel.log("   Context: \(context)", type: .error)
                                }
                            }
                        }
                    }
                    }
                } else {
                    viewModel.log("❌ Failed to resolve stream URL", type: .error)
                    if let error = metrics.error {
                        viewModel.log("\(error.type.icon) Error: \(error.description)", type: .error)
                        if let context = error.context {
                            viewModel.log("   Context: \(context)", type: .error)
                        }
                        viewModel.addError(to: item.id, error: error)
                    }
                    if let statusCode = metrics.httpStatusCode {
                        viewModel.log("📡 Last HTTP Status: \(statusCode)", type: .error)
                    }
                }
            }
        }
    }
    
    private func showURLs(_ item: DebugStreamItem) {
        viewModel.log("📋 URLs for \"\(item.title)\":", type: .info)
        if let streamURL = item.streamURL {
            viewModel.log("  Stream: \(streamURL)", type: .info)
        }
        if let downloadURL = item.downloadURL {
            viewModel.log("  Download: \(downloadURL)", type: .info)
        }
        if let resolvedURL = item.resolvedURL {
            viewModel.log("  Resolved: \(resolvedURL)", type: .info)
        }
    }
    
    private func getDetails(_ item: DebugStreamItem) {
        viewModel.log("🔍 Fetching details for \"\(item.title)\"", type: .info)
        Task {
            await viewModel.fetchDetails(for: item)
        }
    }
    
    private func testDirectPlayback(_ item: DebugStreamItem) {
        viewModel.log("🎯 Testing DIRECT playback for \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("❌ Invalid stream URL", type: .error)
            return
        }
        
        viewModel.log("📍 Direct URL: \(urlString)", type: .info)
        
        // Use simple stream manager
        let simpleManager = DebugStreamManagerSimple()
        
        simpleManager.testDirectPlayback(with: url) { player in
            DispatchQueue.main.async {
                guard let player = player else {
                    viewModel.log("❌ Failed to create direct player", type: .error)
                    return
                }
                
                viewModel.log("🎮 Direct player created", type: .success)
                currentPlayer = player
                showingPlayer = true
                player.play()
                viewModel.log("▶️ Direct playback started", type: .info)
                
                // Monitor player status
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let rate = player.rate
                    let status = player.currentItem?.status ?? .unknown
                    viewModel.log("📊 Player rate: \(rate), Status: \(status.rawValue)", type: .info)
                    
                    if let error = player.currentItem?.error {
                        viewModel.log("❌ Player error: \(error.localizedDescription)", type: .error)
                    }
                }
            }
        }
    }
    
    private func testAsMP4(_ item: DebugStreamItem) {
        viewModel.log("🔄 Testing as MP4 format for \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL else {
            viewModel.log("❌ No stream URL available", type: .error)
            return
        }
        
        // Replace .mkv with .mp4
        let mp4URL = urlString.replacingOccurrences(of: ".mkv", with: ".mp4")
        viewModel.log("📍 MP4 URL: \(mp4URL)", type: .info)
        
        guard let url = URL(string: mp4URL) else {
            viewModel.log("❌ Invalid MP4 URL", type: .error)
            return
        }
        
        // Try direct playback with MP4
        let simpleManager = DebugStreamManagerSimple()
        simpleManager.testDirectPlayback(with: url) { player in
            DispatchQueue.main.async {
                guard let player = player else {
                    viewModel.log("❌ Failed to create MP4 player", type: .error)
                    return
                }
                
                viewModel.log("🎮 MP4 player created", type: .success)
                currentPlayer = player
                showingPlayer = true
                player.play()
                viewModel.log("▶️ MP4 playback started", type: .info)
            }
        }
    }
    
    private func openInVLC(_ item: DebugStreamItem) {
        viewModel.log("🎬 Opening in VLC: \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL else {
            viewModel.log("❌ No stream URL available", type: .error)
            return
        }
        
        viewModel.log("📍 VLC URL: \(urlString)", type: .info)
        
        VLCHelper.openInVLC(url: urlString)
        viewModel.log("✅ Sent to VLC", type: .success)
    }
    
    private func testAsHLS(_ item: DebugStreamItem) {
        viewModel.log("🔄 Testing as HLS format for \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL else {
            viewModel.log("❌ No stream URL available", type: .error)
            return
        }
        
        // Try HLS variant - replace extension with .m3u8
        let hlsURL: String
        if item.fileExtension == "ts" {
            // For live streams, replace .ts with .m3u8
            hlsURL = urlString.replacingOccurrences(of: ".ts", with: ".m3u8")
        } else {
            // For other formats like mkv
            hlsURL = urlString.replacingOccurrences(of: ".\(item.fileExtension)", with: ".m3u8")
        }
        viewModel.log("📍 HLS URL: \(hlsURL)", type: .info)
        
        guard let url = URL(string: hlsURL) else {
            viewModel.log("❌ Invalid HLS URL", type: .error)
            return
        }
        
        // Try direct playback with HLS
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        
        viewModel.log("🎮 HLS player created", type: .success)
        currentPlayer = player
        showingPlayer = true
        player.play()
        viewModel.log("▶️ HLS playback started", type: .info)
        
        // Monitor player status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let rate = player.rate
            let status = player.currentItem?.status ?? .unknown
            viewModel.log("📊 HLS Player rate: \(rate), Status: \(status.rawValue)", type: .info)
            
            if let error = player.currentItem?.error {
                viewModel.log("❌ HLS Player error: \(error.localizedDescription)", type: .error)
            }
        }
    }
    
    private func formatDate(_ timestamp: String) -> String {
        if let timeInterval = TimeInterval(timestamp) {
            let date = Date(timeIntervalSince1970: timeInterval)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return timestamp
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        viewModel.log("📋 Copied to clipboard: \(text)", type: .success)
    }
    
    private func copyLogsToClipboard() {
        let logContent = viewModel.exportLogsAsText()
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logContent, forType: .string)
        #else
        UIPasteboard.general.string = logContent
        #endif
        
        viewModel.log("📋 All logs copied to clipboard (\(viewModel.logs.count) entries)", type: .success)
    }
    
    private func testEpisodeStream(serie: DebugStreamItem, episode: SerieDetail.Episode) {
        viewModel.log("🎬 Starting stream test for \"\(serie.title)\" - Episode \(episode.episodeNum)", type: .info)
        
        let urlString = IPTVConfiguration.buildSeriesURL(
            profile: profile,
            vodID: episode.id,
            vodExtension: episode.containerExtension
        )
        
        guard let url = URL(string: urlString) else {
            viewModel.log("❌ Invalid episode URL", type: .error)
            return
        }
        
        viewModel.log("📍 Episode URL: \(urlString)", type: .info)
        viewModel.log("📺 Episode: \(episode.title)", type: .info)
        viewModel.log("⏱️ Duration: \(episode.info.duration)", type: .info)
        
        // Use the same streaming logic
        let streamManager = DebugStreamManager()
        let startTime = Date()
        
        streamManager.resolveStreamURLWithMetrics(from: url) { resolvedUrl, metrics in
            
            if let resolvedUrl = resolvedUrl {
                viewModel.log("✅ Resolved episode URL: \(resolvedUrl.absoluteString)", type: .success)
                viewModel.log("📊 Resolution time: \(String(format: "%.2f ms", (metrics.urlResolutionTime ?? 0) * 1000))", type: .info)
                
                streamManager.setupStreamPlayerWithMetrics(with: resolvedUrl) { player, playerMetrics in
                    DispatchQueue.main.async {
                        if let player = player {
                            let totalTime = Date().timeIntervalSince(startTime)
                            viewModel.log("🎮 Episode player initialized", type: .success)
                            viewModel.log("📊 Total latency: \(String(format: "%.2f ms", totalTime * 1000))", type: .info)
                            
                            self.currentPlayer = player
                            self.showingPlayer = true
                            player.play()
                            viewModel.log("▶️ Episode playback started", type: .info)
                        } else {
                            viewModel.log("❌ Failed to initialize episode player", type: .error)
                        }
                    }
                }
            } else {
                viewModel.log("❌ Failed to resolve episode URL", type: .error)
                if let error = metrics.error {
                    viewModel.log("\(error.type.icon) Error: \(error.description)", type: .error)
                }
            }
        }
    }
    
    private func exportLogs() {
        let logContent = viewModel.exportLogsAsText()
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let filename = "debug-logs-\(timestamp).txt"
        
        #if os(macOS)
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [.plainText]
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try logContent.write(to: url, atomically: true, encoding: .utf8)
                    viewModel.log("✅ Logs exported to: \(url.path)", type: .success)
                } catch {
                    viewModel.log("❌ Failed to export logs: \(error.localizedDescription)", type: .error)
                }
            }
        }
        #else
        // For iOS, we'll use a share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            let activityVC = UIActivityViewController(activityItems: [logContent], applicationActivities: nil)
            rootViewController.present(activityVC, animated: true)
            viewModel.log("📤 Sharing logs...", type: .info)
        }
        #endif
    }
    
    private func testWithCompatibility(_ item: DebugStreamItem) {
        viewModel.log("🔄 Starting compatibility check for \"\(item.title)\"", type: .info)
        
        Task {
            // Use the stream compatibility handler
            if let player = await streamCompatibilityHandler.testStreamWithCompatibility(
                item: item,
                viewModel: viewModel
            ) {
                // Success - show player
                DispatchQueue.main.async {
                    self.currentPlayer = player
                    self.showingPlayer = true
                    player.play()
                    viewModel.log("▶️ Playback started with compatibility handler", type: .success)
                }
            } else {
                viewModel.log("❌ Failed to create compatible player", type: .error)
            }
        }
    }
    
    private func testWithKSPlayer(_ item: DebugStreamItem) {
        viewModel.log("🎬 Testing with KSPlayer for \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("❌ Invalid stream URL for KSPlayer test", type: .error)
            return
        }
        
        viewModel.log("📍 KSPlayer URL: \(urlString)", type: .info)
        viewModel.log("📊 Format: \(item.fileExtension)", type: .info)
        
        // Check if KSPlayer is available
        guard KSPlayerImplementation.isAvailable() else {
            viewModel.log("❌ KSPlayer is not available", type: .error)
            viewModel.log("💡 Check KSPlayer package dependencies", type: .info)
            return
        }
        
        // Create KSPlayer instance using PlayerFactory
        viewModel.log("🔧 Creating KSPlayer instance...", type: .info)
        
        // Use PlayerManager to handle the KSPlayer
        PlayerManager.shared.loadVideo(url: url, preferredPlayer: .ksplayer)
        
        // Monitor player status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let currentPlayer = PlayerManager.shared.currentPlayer {
                let playerType = PlayerManager.shared.currentPlayerType
                
                viewModel.log("📊 Created Player Type: \(playerType.displayName)", type: .info)
                
                if playerType == .ksplayer {
                    viewModel.log("✅ KSPlayer successfully created", type: .success)
                    
                    if let ksPlayer = currentPlayer as? KSPlayerImplementation {
                        let isReady = ksPlayer.isReady
                        let isPlaying = ksPlayer.isPlaying
                        let hasError = ksPlayer.error != nil
                        
                        viewModel.log("📊 KSPlayer Status:", type: .info)
                        viewModel.log("  - Ready: \(isReady)", type: .info)
                        viewModel.log("  - Playing: \(isPlaying)", type: .info)
                        viewModel.log("  - Has Error: \(hasError)", type: .info)
                        
                        if let error = ksPlayer.error {
                            viewModel.log("❌ KSPlayer Error: \(error.localizedDescription)", type: .error)
                        } else {
                            viewModel.log("✅ KSPlayer ready for playback", type: .success)
                            
                            // For demo purposes, create an AVPlayer to show in the existing player view
                            // In production, you'd use UniversalPlayerView with KSPlayer
                            let avPlayer = AVPlayer(url: url)
                            self.currentPlayer = avPlayer
                            self.showingPlayer = true
                            avPlayer.play()
                            viewModel.log("▶️ KSPlayer test playback started (AVPlayer proxy)", type: .success)
                            viewModel.log("💡 Note: Using AVPlayer for demo - KSPlayer created successfully", type: .info)
                        }
                    }
                } else {
                    viewModel.log("⚠️ PlayerFactory selected \(playerType.displayName) instead of KSPlayer", type: .warning)
                    viewModel.log("💡 This might be due to format compatibility or availability", type: .info)
                }
            } else {
                viewModel.log("❌ Failed to create any player", type: .error)
            }
        }
    }
    
    private func testWithVLC(_ item: DebugStreamItem) {
        viewModel.log("🎬 Testing with VLCKit for \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("❌ Invalid stream URL for VLC test", type: .error)
            return
        }
        
        viewModel.log("📍 VLC URL: \(urlString)", type: .info)
        viewModel.log("📊 Format: \(item.fileExtension)", type: .info)
        
        // Check if VLC is available
        guard VLCPlayerImplementation.isAvailable() else {
            viewModel.log("❌ VLCKit is not available (not installed)", type: .error)
            viewModel.log("💡 Install VLCKit via Swift Package Manager to test", type: .info)
            return
        }
        
        // Create VLC instance using PlayerFactory
        viewModel.log("🔧 Creating VLCKit instance...", type: .info)
        
        // Use PlayerManager to handle the VLC player
        PlayerManager.shared.loadVideo(url: url, preferredPlayer: .vlc)
        
        // Monitor player status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let currentPlayer = PlayerManager.shared.currentPlayer {
                let playerType = PlayerManager.shared.currentPlayerType
                
                viewModel.log("📊 Created Player Type: \(playerType.displayName)", type: .info)
                
                if playerType == .vlc {
                    viewModel.log("✅ VLCKit successfully created", type: .success)
                    
                    if let vlcPlayer = currentPlayer as? VLCPlayerImplementation {
                        let isReady = vlcPlayer.isReady
                        let isPlaying = vlcPlayer.isPlaying
                        let hasError = vlcPlayer.error != nil
                        let currentTime = vlcPlayer.currentTime
                        let duration = vlcPlayer.duration
                        let volume = vlcPlayer.volume
                        
                        viewModel.log("📊 VLCKit Status:", type: .info)
                        viewModel.log("  - Ready: \(isReady)", type: .info)
                        viewModel.log("  - Playing: \(isPlaying)", type: .info)
                        viewModel.log("  - Has Error: \(hasError)", type: .info)
                        viewModel.log("  - Current Time: \(String(format: "%.2f", currentTime))s", type: .info)
                        viewModel.log("  - Duration: \(String(format: "%.2f", duration))s", type: .info)
                        viewModel.log("  - Volume: \(String(format: "%.2f", volume))", type: .info)
                        
                        if let error = vlcPlayer.error {
                            viewModel.log("❌ VLCKit Error: \(error.localizedDescription)", type: .error)
                        } else {
                            viewModel.log("✅ VLCKit ready for playback", type: .success)
                            
                            // For demo purposes, create an AVPlayer to show in the existing player view
                            // In production, you'd use UniversalPlayerView with VLC
                            let avPlayer = AVPlayer(url: url)
                            self.currentPlayer = avPlayer
                            self.showingPlayer = true
                            avPlayer.play()
                            viewModel.log("▶️ VLCKit test playback started (AVPlayer proxy)", type: .success)
                            viewModel.log("💡 Note: Using AVPlayer for demo - VLCKit created successfully", type: .info)
                            
                            // Monitor VLC player progress
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                let updatedTime = vlcPlayer.currentTime
                                let updatedPlaying = vlcPlayer.isPlaying
                                viewModel.log("📊 VLCKit after 3s: Playing: \(updatedPlaying), Time: \(String(format: "%.2f", updatedTime))s", type: .info)
                            }
                        }
                    }
                } else {
                    viewModel.log("⚠️ PlayerFactory selected \(playerType.displayName) instead of VLCKit", type: .warning)
                    viewModel.log("💡 This might be due to format compatibility or availability", type: .info)
                }
            } else {
                viewModel.log("❌ Failed to create any player", type: .error)
            }
        }
    }
    
    private func analyzeWithFFprobe(_ item: DebugStreamItem) {
        viewModel.log("🔍 Analyzing stream with FFprobe: \"\(item.title)\"", type: .info)
        
        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("❌ Invalid stream URL for FFprobe analysis", type: .error)
            return
        }
        
        Task {
            do {
                #if os(macOS)
                // Check if ffprobe is available
                if let ffprobePath = FFProbeUtilities.findFFProbe() {
                    viewModel.log("✅ Found ffprobe at: \(ffprobePath)", type: .success)
                } else {
                    viewModel.log("⚠️ FFprobe not found, attempting analysis anyway...", type: .warning)
                }
                #else
                viewModel.log("ℹ️ FFprobe analysis is only available on macOS", type: .info)
                viewModel.log("📱 iOS does not support external binary execution", type: .info)
                return
                #endif
                
                // Analyze the stream
                viewModel.log("🔄 Starting FFprobe analysis...", type: .info)
                let startTime = Date()
                
                let metadata = try await FFProbeUtilities.analyzeMKVStream(from: url)
                
                let analysisTime = Date().timeIntervalSince(startTime)
                viewModel.log("✅ FFprobe analysis completed in \(String(format: "%.2f", analysisTime))s", type: .success)
                
                // Log results
                viewModel.log("📊 Stream Analysis Results:", type: .info)
                viewModel.log("  Format: \(metadata.formatName)", type: .info)
                viewModel.log("  Video Codec: \(metadata.videoCodec ?? "none")", type: .info)
                viewModel.log("  Audio Codec: \(metadata.audioCodec ?? "none")", type: .info)
                viewModel.log("  AVPlayer Compatible: \(metadata.isCompatibleWithAVPlayer ? "✅ Yes" : "❌ No")", type: metadata.isCompatibleWithAVPlayer ? .success : .error)
                
                if let duration = metadata.duration {
                    let hours = Int(duration) / 3600
                    let minutes = (Int(duration) % 3600) / 60
                    let seconds = Int(duration) % 60
                    viewModel.log("  Duration: \(String(format: "%02d:%02d:%02d", hours, minutes, seconds))", type: .info)
                }
                
                if let width = metadata.videoWidth, let height = metadata.videoHeight {
                    viewModel.log("  Resolution: \(width)x\(height)", type: .info)
                    if let fps = metadata.videoFrameRate {
                        viewModel.log("  Frame Rate: \(String(format: "%.2f", fps)) fps", type: .info)
                    }
                }
                
                if let bitrate = metadata.bitrate {
                    let mbps = Double(bitrate) / 1_000_000
                    viewModel.log("  Bitrate: \(String(format: "%.2f", mbps)) Mbps", type: .info)
                }
                
                if let audioBitrate = metadata.audioBitrate,
                   let audioSampleRate = metadata.audioSampleRate,
                   let audioChannels = metadata.audioChannels {
                    viewModel.log("  Audio: \(audioSampleRate)Hz, \(audioBitrate/1000)kbps, \(audioChannels)ch", type: .info)
                }
                
                // Provide recommendations based on compatibility
                if !metadata.isCompatibleWithAVPlayer {
                    viewModel.log("⚠️ Stream is not compatible with AVPlayer", type: .warning)
                    
                    if metadata.videoCodec?.lowercased().contains("vp9") == true {
                        viewModel.log("  - VP9 codec is not supported by AVPlayer", type: .warning)
                        viewModel.log("  - Consider transcoding to H.264 or using VLC", type: .info)
                    }
                    
                    if metadata.audioCodec?.lowercased().contains("dts") == true {
                        viewModel.log("  - DTS audio is not supported by AVPlayer", type: .warning)
                        viewModel.log("  - Consider transcoding to AAC audio", type: .info)
                    }
                    
                    viewModel.log("💡 Try opening in VLC for better codec support", type: .info)
                }
                
            } catch let error as FFProbeError {
                viewModel.log("❌ FFprobe error: \(error.localizedDescription)", type: .error)
                
                // Provide specific guidance based on error type
                switch error {
                case .ffprobeNotFound:
                    #if os(macOS)
                    viewModel.log("💡 Install FFmpeg using: brew install ffmpeg", type: .info)
                    #else
                    viewModel.log("💡 FFprobe analysis is only supported on macOS", type: .info)
                    #endif
                case .networkError:
                    viewModel.log("💡 Check if the stream URL is accessible", type: .info)
                case .invalidURL:
                    viewModel.log("💡 Ensure the URL is properly formatted", type: .info)
                default:
                    break
                }
            } catch {
                viewModel.log("❌ Unexpected error: \(error.localizedDescription)", type: .error)
            }
        }
    }
}

// MARK: - Supporting Views

struct DebugStreamItemRow: View {
    let item: DebugStreamItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onTestStream: () -> Void
    let onTestDirectPlayback: () -> Void
    let onTestWithCompatibility: () -> Void
    let onTestWithKSPlayer: () -> Void
    let onTestWithVLC: () -> Void
    let onTestAsMP4: () -> Void
    let onTestAsHLS: () -> Void
    let onOpenInVLC: () -> Void
    let onShowURLs: () -> Void
    let onGetDetails: () -> Void
    let onCopyURL: (String) -> Void
    let onAnalyzeWithFFprobe: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label(String(item.id), systemImage: "number")
                    Label(item.fileExtension, systemImage: "doc")
                    Label(item.type == .movie ? "Movie" : "Series", systemImage: item.type == .movie ? "film" : "tv")
                    if let rating = item.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .foregroundColor(.yellow)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Menu {
                    Button("Test Stream") { onTestStream() }
                    Button("Test Direct Playback") { onTestDirectPlayback() }
                    Button("Test with Compatibility Check") { onTestWithCompatibility() }
                    Divider()
                    Button("Test with KSPlayer") { onTestWithKSPlayer() }
                    if VLCPlayerImplementation.isAvailable() {
                        Button("Test with VLC") { onTestWithVLC() }
                            .foregroundColor(.orange)
                    }
                    Divider()
                    Button("Analyze with FFprobe") { onAnalyzeWithFFprobe() }
                    if item.fileExtension == "mkv" {
                        Divider()
                        Button("Try as MP4") { onTestAsMP4() }
                        Button("Try as HLS") { onTestAsHLS() }
                    }
                    if item.fileExtension == "ts" {
                        Divider()
                        Button("Try as HLS/M3U8") { onTestAsHLS() }
                    }
                    if VLCHelper.isVLCInstalled() {
                        Divider()
                        Button("Open in VLC") { 
                            onOpenInVLC() 
                        }
                        .foregroundColor(.orange)
                    }
                } label: {
                    Text("Test")
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.small)
                
                Menu {
                    Button("Show All URLs") { onShowURLs() }
                    Divider()
                    if let streamURL = item.streamURL {
                        Button("Copy Stream URL") { 
                            onCopyURL(streamURL)
                        }
                    }
                    if let downloadURL = item.downloadURL {
                        Button("Copy Download URL") { 
                            onCopyURL(downloadURL)
                        }
                    }
                    if let resolvedURL = item.resolvedURL {
                        Button("Copy Resolved URL") { 
                            onCopyURL(resolvedURL)
                        }
                    }
                } label: {
                    Text("URLs")
                }
                .buttonStyle(BorderlessButtonStyle())
                .controlSize(.small)
                
                Button("Details") { onGetDetails() }
                    .buttonStyle(BorderlessButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .onTapGesture { onSelect() }
    }
}

struct DebugLogRow: View {
    let log: DebugLog
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(log.timestamp)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
            
            Text(log.message)
                .font(.system(size: 12))
                .foregroundColor(log.type.color)
                .textSelection(.enabled)
            
            Spacer()
        }
        .contextMenu {
            Button(action: {
                let logText = "[\(log.timestamp)] \(log.message)"
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logText, forType: .string)
                #else
                UIPasteboard.general.string = logText
                #endif
            }) {
                Label("Copy Log Entry", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(log.message, forType: .string)
                #else
                UIPasteboard.general.string = log.message
                #endif
            }) {
                Label("Copy Message Only", systemImage: "doc.plaintext")
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .textSelection(.enabled)
        }
    }
}

// MARK: - Extensions

extension AVPlayer.Status {
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .readyToPlay: return "Ready to Play"
        case .failed: return "Failed"
        @unknown default: return "Unknown Status"
        }
    }
}

extension DebugLog.LogType {
    var color: Color {
        switch self {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Preview

struct DebugStreamingView_Previews: PreviewProvider {
    static var previews: some View {
        DebugStreamingView(movieService: MovieService(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
            .environmentObject(IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
            .frame(width: 1000, height: 800)
    }
}