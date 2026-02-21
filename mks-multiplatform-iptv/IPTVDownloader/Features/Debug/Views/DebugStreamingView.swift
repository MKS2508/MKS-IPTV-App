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
    @State private var activePlayerView: AnyView?
    @State private var activePlayerLabel: String = ""
    @State private var showingEpisodePicker = false
    @State private var selectedSerieForEpisodes: DebugStreamItem?
    @State private var selectedLiveTVCategory: String = "all"
    @State private var showingCategoryURLs = false
    @State private var activeProxySession: StreamProxy.ProxySession?

    /// Threshold for URL length above which we use the proxy.
    /// FFmpeg n6.1 has a buffer overflow on URLs >~500 chars.
    private let proxyURLLengthThreshold = 500

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
                playerSheet
            }
            .task {
                await viewModel.loadContent(type: selectedTab, liveTVCategory: selectedLiveTVCategory)
            }
            .sheet(item: $selectedSerieForEpisodes) { serie in
                SeriesEpisodePickerView(
                    serie: serie,
                    onEpisodeSelected: { episode in
                        playEpisode(serie: serie, episode: episode)
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

    // MARK: - Player Sheet

    @ViewBuilder
    private var playerSheet: some View {
        if let playerView = activePlayerView {
            VStack(spacing: 0) {
                HStack {
                    Text(activePlayerLabel)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Close") {
                        showingPlayer = false
                        activePlayerView = nil
                        // Cleanup proxy session if active
                        if let session = activeProxySession {
                            StreamProxy.shared.stop(sessionID: session.id)
                            activeProxySession = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.9))

                playerView
            }
            .frame(width: 800, height: 600)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        #if os(macOS)
        VSplitView {
            VStack(spacing: 0) {
                tabSelector
                    .padding(.top)
                    .padding(.horizontal)

                Divider()
                    .padding(.top, 8)

                contentList
            }
            .frame(minHeight: 300)

            HSplitView {
                VStack(spacing: 0) {
                    systemInfoBar
                    logsPanel
                }
                .frame(minWidth: 400)

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
            tabSelector
                .padding(.top)
                .padding(.horizontal)

            Divider()
                .padding(.top, 8)

            contentList
                .frame(maxHeight: 300)

            Divider()

            TabView {
                VStack(spacing: 0) {
                    systemInfoBar
                    logsPanel
                }
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

    // MARK: - System Info Bar

    private var systemInfoBar: some View {
        HStack(spacing: 12) {
            Text("Players:")
                .font(.caption2)
                .foregroundColor(.secondary)

            ForEach(PlayerType.allCases, id: \.self) { type in
                let available = PlayerFactory.availablePlayers().contains(type)
                Text(type.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(available ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                    )
                    .foregroundColor(available ? .green : .secondary.opacity(0.5))
            }

            Divider()
                .frame(height: 14)

            Text("FFprobe:")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(FFProbeUtilities.isAvailable() ? "Available" : "N/A")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(FFProbeUtilities.isAvailable() ? .green : .orange)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Content Type", selection: $selectedTab) {
                    ForEach(ContentTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 400)

                if selectedTab == .liveTV {
                    liveTVCategoryPicker
                }

                Spacer()
            }

            toolbarButtons
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    private var liveTVCategoryPicker: some View {
        Picker("Category", selection: $selectedLiveTVCategory) {
            Text("All").tag("all")
            ForEach(viewModel.liveTVCategories, id: \.categoryId) { category in
                Text(category.categoryName).tag(category.categoryId)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .frame(width: 150)
    }

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            Button("Refresh", systemImage: "arrow.clockwise") { refreshContent() }
                .buttonStyle(.bordered)
            Button("System Info", systemImage: "info.circle") { logSystemInfo() }
                .buttonStyle(.bordered)
            Button("Copy Logs", systemImage: "doc.on.doc") { copyLogsToClipboard() }
                .buttonStyle(.bordered)
            Button("Export", systemImage: "square.and.arrow.up") { exportLogs() }
                .buttonStyle(.bordered)
            Button("URLs", systemImage: "doc.on.doc.fill") { showingCategoryURLs = true }
                .buttonStyle(.bordered)
            Spacer()
            Button("Clear", systemImage: "trash") { viewModel.clearLogs() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }

    private func refreshContent() {
        Task { await viewModel.loadContent(type: selectedTab, liveTVCategory: selectedLiveTVCategory) }
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
                        onSmartPlay: { playItem(item) },
                        onForcePlay: { type in playItemWith(item, playerType: type) },
                        onAnalyze: { analyzeWithFFprobe(item) },
                        onShowURLs: { showURLs(item) },
                        onGetDetails: { getDetails(item) },
                        onCopyURL: { url in copyToClipboard(url) },
                        onOpenInVLC: { openInVLC(item) }
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
                    .toggleStyle(.checkbox)
                    #else
                    .toggleStyle(SwitchToggleStyle())
                    #endif

                Toggle("Verbose", isOn: $viewModel.verboseMode)
                    #if os(macOS)
                    .toggleStyle(.checkbox)
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
                    basicInfoSection(item: item)
                    urlsSection(item: item)
                    if item.hasBeenTested {
                        streamingInfoSection(item: item)
                        performanceSection(item: item)
                    }
                }
                .padding()
            }
        }
        .background(VisualEffect())
    }

    private func basicInfoSection(item: DebugStreamItem) -> some View {
        let typeLabel: String = item.type == MediaType.movie ? "Movie" : "Series"
        return detailSection(title: "Basic Info") {
            DetailRow(label: "Title", value: item.title)
            DetailRow(label: "ID", value: String(item.id))
            DetailRow(label: "Type", value: typeLabel)
            DetailRow(label: "Extension", value: item.fileExtension)
            DetailRow(label: "Added", value: formatDate(item.added))
            DetailRow(label: "Category", value: item.categoryId)
            if let rating = item.rating {
                DetailRow(label: "Rating", value: String(format: "%.1f", rating))
            }
        }
    }

    private func urlsSection(item: DebugStreamItem) -> some View {
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
    }

    private func streamingInfoSection(item: DebugStreamItem) -> some View {
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
    }

    private func performanceSection(item: DebugStreamItem) -> some View {
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

    // MARK: - Smart Play (extension-based → PlayerFactory → play)
    // NOTE: FFprobe is NOT used here to avoid double-connection issues.
    // IPTV servers often limit concurrent connections per user, and even sequential
    // connections can fail if the TCP socket lingers in TIME_WAIT.
    // Use "Analyze with FFprobe" separately when you need codec details.

    private func playItem(_ item: DebugStreamItem) {
        if item.type == .series {
            selectedSerieForEpisodes = item
            return
        }

        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("Invalid stream URL", type: .error)
            return
        }

        viewModel.log("Playing \"\(item.title)\" [\(item.fileExtension)]", type: .info)
        viewModel.updateItemState(item.id, hasBeenTested: true)

        Task {
            // Preflight: validate stream reachability before creating a player
            viewModel.log("Preflight check: \(urlString)", type: .info)
            let preflight = await StreamPreflight.check(url: url)
            viewModel.log("Preflight: \(preflight.summary)", type: preflight.isReachable ? .success : .error)

            if preflight.wasRedirected, let finalURL = preflight.finalURL {
                viewModel.log("Redirected to: \(finalURL.host ?? "?"):\(finalURL.port ?? 80)", type: .info)
            }

            guard preflight.isReachable else {
                viewModel.log("Stream unreachable — skipping player creation", type: .error)
                viewModel.updateItemState(item.id, httpStatusCode: preflight.httpStatus)
                return
            }

            if let httpStatus = preflight.httpStatus {
                viewModel.updateItemState(item.id, httpStatusCode: httpStatus)
            }

            // If the server redirects (common with Cloudflare-fronted IPTV),
            // resolve a fresh direct URL so KSPlayer/FFmpeg doesn't need to
            // handle the 302 itself (FFmpeg's URL parser chokes on long token URLs)
            var playbackURL = url
            var needsProxy = false
            if preflight.wasRedirected {
                viewModel.log("Resolving redirect for direct playback...", type: .info)
                let resolved = await StreamPreflight.resolveRedirects(url: url)
                if resolved != url {
                    viewModel.log("Resolved to: \(resolved.host ?? "?"):\(resolved.port ?? 80)/...\(resolved.lastPathComponent)", type: .success)
                    playbackURL = resolved
                    // Check if URL is too long for FFmpeg n6.1 (>500 chars causes buffer overflow)
                    needsProxy = resolved.absoluteString.count > proxyURLLengthThreshold
                    if needsProxy {
                        viewModel.log("URL is long (\(resolved.absoluteString.count) chars) — using proxy", type: .info)
                    }
                }
            }

            // Use proxy for long URLs to avoid FFmpeg buffer overflow
            if needsProxy {
                do {
                    let session = try await StreamProxy.shared.startProxy(for: playbackURL)
                    activeProxySession = session
                    viewModel.log("Proxy started: \(session.localURL.absoluteString)", type: .success)
                    playbackURL = session.localURL
                } catch {
                    viewModel.log("Proxy failed: \(error.localizedDescription) — trying direct URL", type: .warning)
                }
            }

            let startTime = Date()

            // PlayerFactory auto-selects best player based on file extension
            let player = PlayerFactory.shared.createPlayer(for: playbackURL)
            let playerType = detectPlayerType(player)
            let initTime = Date().timeIntervalSince(startTime)

            viewModel.log("Selected player: \(playerType.displayName)", type: .success)
            viewModel.log("Player created in \(String(format: "%.0f", initTime * 1000))ms", type: .info)
            viewModel.updateItemState(item.id, totalLatency: initTime)

            player.play()
            activePlayerLabel = "\(item.title) — \(playerType.displayName) — \(item.fileExtension)"
            activePlayerView = AnyView(player.playerView())
            showingPlayer = true
            viewModel.log("Playback started", type: .success)
        }
    }

    // MARK: - Force Play with Specific Player

    private func playItemWith(_ item: DebugStreamItem, playerType: PlayerType) {
        if item.type == .series {
            selectedSerieForEpisodes = item
            return
        }

        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("Invalid stream URL", type: .error)
            return
        }

        viewModel.log("Forcing \(playerType.displayName) for \"\(item.title)\"", type: .info)
        viewModel.updateItemState(item.id, hasBeenTested: true)

        Task {
            // Preflight: validate stream reachability
            let preflight = await StreamPreflight.check(url: url)
            viewModel.log("Preflight: \(preflight.summary)", type: preflight.isReachable ? .success : .error)

            guard preflight.isReachable else {
                viewModel.log("Stream unreachable — skipping player creation", type: .error)
                return
            }

            // Resolve redirect for direct playback if needed
            var playbackURL = url
            var needsProxy = false
            if preflight.wasRedirected {
                let resolved = await StreamPreflight.resolveRedirects(url: url)
                if resolved != url {
                    viewModel.log("Resolved redirect → \(resolved.host ?? "?"):\(resolved.port ?? 80)", type: .info)
                    playbackURL = resolved
                    needsProxy = resolved.absoluteString.count > proxyURLLengthThreshold
                    if needsProxy {
                        viewModel.log("URL is long (\(resolved.absoluteString.count) chars) — using proxy", type: .info)
                    }
                }
            }

            // Use proxy for long URLs to avoid FFmpeg buffer overflow
            if needsProxy {
                do {
                    let session = try await StreamProxy.shared.startProxy(for: playbackURL)
                    activeProxySession = session
                    viewModel.log("Proxy started: \(session.localURL.absoluteString)", type: .success)
                    playbackURL = session.localURL
                } catch {
                    viewModel.log("Proxy failed: \(error.localizedDescription) — trying direct URL", type: .warning)
                }
            }

            let player = PlayerFactory.shared.createPlayer(type: playerType, url: playbackURL)
            let actualType = detectPlayerType(player)

            if actualType != playerType {
                viewModel.log("\(playerType.displayName) not available, fell back to \(actualType.displayName)", type: .warning)
            }

            player.play()
            activePlayerLabel = "\(item.title) — \(actualType.displayName) (forced) — \(item.fileExtension)"
            activePlayerView = AnyView(player.playerView())
            showingPlayer = true
            viewModel.log("Playback started with \(actualType.displayName)", type: .success)
        }
    }

    // MARK: - Play Episode

    private func playEpisode(serie: DebugStreamItem, episode: SerieDetail.Episode) {
        viewModel.log("Playing \"\(serie.title)\" S\(episode.episodeNum) — \(episode.title)", type: .info)

        let urlString = IPTVConfiguration.buildSeriesURL(
            profile: profile,
            vodID: episode.id,
            vodExtension: episode.containerExtension
        )

        guard let url = URL(string: urlString) else {
            viewModel.log("Invalid episode URL", type: .error)
            return
        }

        viewModel.log("Episode URL: \(urlString)", type: .info)

        Task {
            let preflight = await StreamPreflight.check(url: url)
            viewModel.log("Preflight: \(preflight.summary)", type: preflight.isReachable ? .success : .error)

            guard preflight.isReachable else {
                viewModel.log("Episode stream unreachable — skipping", type: .error)
                return
            }

            var playbackURL = url
            var needsProxy = false
            if preflight.wasRedirected {
                let resolved = await StreamPreflight.resolveRedirects(url: url)
                if resolved != url {
                    playbackURL = resolved
                    needsProxy = resolved.absoluteString.count > proxyURLLengthThreshold
                    if needsProxy {
                        viewModel.log("URL is long (\(resolved.absoluteString.count) chars) — using proxy", type: .info)
                    }
                }
            }

            // Use proxy for long URLs to avoid FFmpeg buffer overflow
            if needsProxy {
                do {
                    let session = try await StreamProxy.shared.startProxy(for: playbackURL)
                    activeProxySession = session
                    viewModel.log("Proxy started: \(session.localURL.absoluteString)", type: .success)
                    playbackURL = session.localURL
                } catch {
                    viewModel.log("Proxy failed: \(error.localizedDescription) — trying direct URL", type: .warning)
                }
            }

            let player = PlayerFactory.shared.createPlayer(for: playbackURL)
            let playerType = detectPlayerType(player)
            player.play()

            activePlayerLabel = "\(serie.title) — \(episode.title) — \(playerType.displayName)"
            activePlayerView = AnyView(player.playerView())
            showingPlayer = true
            viewModel.log("Episode playback started with \(playerType.displayName)", type: .success)
        }
    }

    // MARK: - FFprobe Analysis (logs only, no playback)

    private func analyzeWithFFprobe(_ item: DebugStreamItem) {
        viewModel.log("Analyzing \"\(item.title)\" with FFprobe", type: .info)

        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("Invalid stream URL for analysis", type: .error)
            return
        }

        Task {
            guard FFProbeUtilities.isAvailable() else {
                viewModel.log("FFmpeg C API (Libavformat) not available", type: .error)
                return
            }

            do {
                let startTime = Date()
                let metadata = try await FFProbeUtilities.analyzeMKVStream(from: url)
                let analysisTime = Date().timeIntervalSince(startTime)

                viewModel.log("Analysis completed in \(String(format: "%.2f", analysisTime))s", type: .success)
                viewModel.log("Stream Analysis Results:", type: .info)
                viewModel.log("  Format: \(metadata.formatName)", type: .info)
                viewModel.log("  Video Codec: \(metadata.videoCodec ?? "none")", type: .info)
                viewModel.log("  Audio Codec: \(metadata.audioCodec ?? "none")", type: .info)
                viewModel.log("  AVPlayer Compatible: \(metadata.isCompatibleWithAVPlayer ? "Yes" : "No")", type: metadata.isCompatibleWithAVPlayer ? .success : .warning)

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
                    viewModel.log("  Audio: \(audioSampleRate)Hz, \(audioBitrate / 1000)kbps, \(audioChannels)ch", type: .info)
                }

                // Recommendations
                if !metadata.isCompatibleWithAVPlayer {
                    viewModel.log("Stream is NOT compatible with AVPlayer", type: .warning)
                    let recommended = PlayerFactory.availablePlayers().first { $0 != .avplayer && $0.supports(format: item.fileExtension) }
                    if let recommended = recommended {
                        viewModel.log("Recommended player: \(recommended.displayName)", type: .info)
                    }
                }
            } catch {
                viewModel.log("FFprobe error: \(error.localizedDescription)", type: .error)
            }
        }
    }

    // MARK: - System Info

    private func logSystemInfo() {
        viewModel.log("=== System Info ===", type: .info)

        let available = PlayerFactory.availablePlayers()
        viewModel.log("Available players (\(available.count)):", type: .info)
        for player in PlayerType.allCases {
            let isAvailable = available.contains(player)
            let formats = player.supportedFormats.joined(separator: ", ")
            viewModel.log("  \(player.displayName): \(isAvailable ? "Available" : "Not Available") — [\(formats)]", type: isAvailable ? .success : .warning)
            viewModel.log("    PiP: \(player.hasPiPSupport) | AirPlay: \(player.hasAirPlaySupport)", type: .info)
        }

        viewModel.log("FFprobe (Libavformat): \(FFProbeUtilities.isAvailable() ? "Available" : "Not Available")", type: FFProbeUtilities.isAvailable() ? .success : .warning)
        viewModel.log("KSPlayer module: \(KSPlayerImplementation.isAvailable() ? "Linked" : "Not Linked")", type: .info)
        viewModel.log("VLCKit module: \(VLCPlayerImplementation.isAvailable() ? "Linked" : "Not Linked")", type: .info)
        viewModel.log("==================", type: .info)
    }

    // MARK: - URL & Details Actions

    private func showURLs(_ item: DebugStreamItem) {
        viewModel.log("URLs for \"\(item.title)\":", type: .info)
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
        viewModel.log("Fetching details for \"\(item.title)\"", type: .info)
        Task {
            await viewModel.fetchDetails(for: item)
        }
    }

    private func openInVLC(_ item: DebugStreamItem) {
        guard let urlString = item.streamURL else {
            viewModel.log("No stream URL available for VLC", type: .error)
            return
        }
        viewModel.log("Opening in system VLC: \"\(item.title)\"", type: .info)
        VLCHelper.openInVLC(url: urlString)
        viewModel.log("Sent to VLC", type: .success)
    }

    // MARK: - Helpers

    private func detectPlayerType(_ player: any VideoPlayerProtocol) -> PlayerType {
        if player is KSPlayerImplementation { return .ksplayer }
        if player is VLCPlayerImplementation { return .vlc }
        if player is FFmpegPlayerImplementation { return .ffmpeg }
        return .avplayer
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
        viewModel.log("Copied to clipboard: \(text)", type: .success)
    }

    private func copyLogsToClipboard() {
        let logContent = viewModel.exportLogsAsText()
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logContent, forType: .string)
        #else
        UIPasteboard.general.string = logContent
        #endif
        viewModel.log("All logs copied to clipboard (\(viewModel.logs.count) entries)", type: .success)
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
                    viewModel.log("Logs exported to: \(url.path)", type: .success)
                } catch {
                    viewModel.log("Failed to export logs: \(error.localizedDescription)", type: .error)
                }
            }
        }
        #else
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            let activityVC = UIActivityViewController(activityItems: [logContent], applicationActivities: nil)
            rootViewController.present(activityVC, animated: true)
            viewModel.log("Sharing logs...", type: .info)
        }
        #endif
    }
}

// MARK: - Supporting Views

struct DebugStreamItemRow: View {
    let item: DebugStreamItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onSmartPlay: () -> Void
    let onForcePlay: (PlayerType) -> Void
    let onAnalyze: () -> Void
    let onShowURLs: () -> Void
    let onGetDetails: () -> Void
    let onCopyURL: (String) -> Void
    let onOpenInVLC: () -> Void

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
                // Primary action: Smart Play
                Button(action: onSmartPlay) {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.small)

                // Secondary actions menu
                Menu {
                    Section("Force Player") {
                        ForEach(PlayerFactory.availablePlayers(), id: \.self) { type in
                            Button("Play with \(type.displayName)") {
                                onForcePlay(type)
                            }
                        }
                    }

                    Divider()

                    Button("Analyze with FFprobe") { onAnalyze() }

                    Divider()

                    Button("Show URLs") { onShowURLs() }
                    if let streamURL = item.streamURL {
                        Button("Copy Stream URL") { onCopyURL(streamURL) }
                    }
                    Button("Fetch Details") { onGetDetails() }

                    if VLCHelper.isVLCInstalled() {
                        Divider()
                        Button("Open in VLC App") { onOpenInVLC() }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
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
