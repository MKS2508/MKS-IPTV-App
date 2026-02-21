import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AddDownloadViewSerie: View {
    @Binding var selectedView: String?
    let seriesDetail: SerieDetail
    let seriesId: Int?
    let onDismiss: () -> Void
    
    @State private var selectedSeason: String = "1"
    @State private var mediaType = MediaType.series
    @State private var searchText = ""
    @State private var selectedEpisodes: Set<String> = []
    
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject var profile: IPTVProfile
    @State private var viewModel: SerieDetailViewModel?
    
    private var movieService: MovieService {
        MovieService(profile: profile)
    }
    
    @MainActor
    private func initializeViewModelIfNeeded() {
        if viewModel == nil {
            let newViewModel = SerieDetailViewModel(movieService: movieService)
            newViewModel.setSerieDetail(seriesDetail, seriesId: seriesId ?? 0)
            viewModel = newViewModel
        }
    }
    
    @State private var isModalPresented = false
    @State private var currentEpisode: SerieDetail.Episode?
    @State private var shouldConvertToMOV = true
    @State private var selectedFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @State private var customFolder: URL? = nil
    private let otherFolderKey = URL(string: "other")!
    @State private var showInlinePlayer = false
    @State private var player: AVPlayer?
    @State private var currentStreamingEpisode: SerieDetail.Episode?
    
    private let streamManager = StreamManager()

    enum ButtonType {
        case primary
        case cancel
    }

    struct DownloadButtonStyle: ButtonStyle {
        var type: ButtonType
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding()
                .frame(maxWidth: .infinity)
                .background(backgroundColor(configuration.isPressed))
                .foregroundColor(foregroundColor)
                .cornerRadius(8)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
        }
        
        private func backgroundColor(_ isPressed: Bool) -> Color {
            switch type {
            case .primary:
                return isPressed ? Color.accentColor.opacity(0.8) : Color.accentColor
            case .cancel:
                return isPressed ? Color.secondary.opacity(0.05) : Color.secondary.opacity(0.1)
            }
        }
        
        private var foregroundColor: Color {
            switch type {
            case .primary:
                return .white
            case .cancel:
                return .secondary
            }
        }
    }
    @State private var dynamicFolders: [URL] = [
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
    ]
    
    // Default initializer with seriesId
    init(selectedView: Binding<String?>, seriesDetail: SerieDetail, seriesId: Int? = nil, onDismiss: @escaping () -> Void) {
        self._selectedView = selectedView
        self.seriesDetail = seriesDetail
        self.seriesId = seriesId
        self.onDismiss = onDismiss
    }

    
    var episodesForSelectedSeason: [SerieDetail.Episode] {
        // Use viewModel's serieDetail if available (for refresh), otherwise use the passed one
        let detail = viewModel?.serieDetail ?? seriesDetail
        let episodes = detail.episodes[selectedSeason] ?? []
        if searchText.isEmpty {
            return episodes
        } else {
            return episodes.filter { $0.title.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let viewModel = viewModel {
                    mainContentView(viewModel: viewModel)
                } else {
                    // Loading or error state
                    VStack {
                        ProgressView()
                            .frame(width: 32, height: 32)
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        initializeViewModelIfNeeded()
                    }
                }
            }
        }
    }
    
    // MARK: - Main Content View
    @ViewBuilder
    private func mainContentView(viewModel: SerieDetailViewModel) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top toolbar
                HStack {
                    // Refresh button - only show if we have a seriesId
                    if let seriesId = seriesId {
                        Button(action: {
                            Task {
                                await viewModel.refresh(seriesId: seriesId)
                            }
                        }) {
                            Image(systemName: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                                .foregroundColor(.secondary)
                                .imageScale(.large)
                                .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                                .animation(viewModel.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(viewModel.isRefreshing || viewModel.isLoading)
                        .padding([.top, .leading], 20)
                    }
                    
                    Spacer()
                    
                    // Close button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding([.top, .trailing], 20)
                }
                
                // Inline player (when active)
                if showInlinePlayer {
                    inlineEpisodePlayerView
                        .padding(.horizontal)
                        .padding(.top)
                }
                
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error: error)
                } else {
                    // Main content
                    HStack(spacing: 0) {
                        VStack(spacing: 20) {
                            seriesInfoView
                            seasonPickerView
                        }
                        .frame(width: geometry.size.width * 0.35)
                        .padding()
                        
                        VStack(spacing: 0) {
                            searchBarView
                            episodesListView
                        }
                        .frame(width: geometry.size.width * 0.6)
                    }
                }
            }
            .frame(minWidth: 600, minHeight: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .sheet(isPresented: $isModalPresented, content: {
            downloadOptionsModal
        })
        .onChange(of: selectedSeason) { _ in
            selectedEpisodes.removeAll()
        }
    }
    
    // MARK: - Vista de carga
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
                .frame(width: 48, height: 48)
            
            Text("Cargando detalles de la serie...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Vista de error
    private func errorView(error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            
            Text("Error al cargar la serie")
                .font(.title3.bold())
                .foregroundColor(.white)
            
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Reintentar") {
                Task {
                    if let seriesId = seriesId {
                        await viewModel?.refresh(seriesId: seriesId)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var seriesInfoView: some View {
        VStack(spacing: 20) {
            AsyncImage(url: URL(string: seriesDetail.info.cover ?? "")) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay(Image(systemName: "film").font(.largeTitle))
            }
            .frame(height: 300)
            .cornerRadius(10)
            .shadow(radius: 5)
            
            VStack(alignment: .leading, spacing: 10) {
                Text(seriesDetail.info.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack {
                    if let year = extractYear(from: seriesDetail.info.releaseDate) {
                        Label("\(year)", systemImage: "calendar")
                    }
                    Label(seriesDetail.info.episodeRunTime, systemImage: "clock")
                    Label(String(format: "%.1f", seriesDetail.info.rating5Based), systemImage: "star.fill")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private var seasonPickerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select Season")
                .font(.headline)
                .foregroundColor(.primary)

            Picker("Season", selection: $selectedSeason) {
                ForEach(seriesDetail.seasons, id: \.id) { season in
                    Text(season.name)
                        .tag(season.id)
                }
            }
            .pickerStyle(MenuPickerStyle()) // Use a segmented control for a compact and native look
            .padding(.vertical, 8)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    private var searchBarView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search episodes", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // Bulk actions
            if !selectedEpisodes.isEmpty {
                HStack(spacing: 12) {
                    Text("\(selectedEpisodes.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: copySelectedURLs) {
                        Label("Copy URLs", systemImage: "link")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: copySelectedIDs) {
                        Label("Copy IDs", systemImage: "number")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { selectedEpisodes.removeAll() }) {
                        Label("Clear", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }
        }
        .padding()
    }
    
    private var episodesListView: some View {
        ScrollView {
            LazyVStack(spacing: 15) {
                ForEach(episodesForSelectedSeason, id: \.id) { episode in
                    EpisodeRow(
                        episode: episode,
                        isSelected: selectedEpisodes.contains(episode.id),
                        onToggleSelection: {
                            if selectedEpisodes.contains(episode.id) {
                                selectedEpisodes.remove(episode.id)
                            } else {
                                selectedEpisodes.insert(episode.id)
                            }
                        },
                        downloadAction: {
                            currentEpisode = episode
                            isModalPresented = true
                        },
                        playAction: {
                            playEpisode(episode: episode)
                        }
                    )
                }
            }
            .padding()
        }
    }

    
    private var downloadOptionsModal: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                Text("Download Options")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top)
            
            Divider()
                .padding(.horizontal)
            
            // Convert to MOV Toggle
            HStack {
                Image(systemName: "film")
                    .foregroundColor(.secondary)
                    .font(.title3)
                Toggle(isOn: $shouldConvertToMOV) {
                    Text("Convert to MOV")
                        .font(.subheadline)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
            }
            .padding(.horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            .cornerRadius(10)
            .padding(.horizontal)
            
            Divider()
                .padding(.horizontal)
            
            // Save To Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.secondary)
                        .font(.title3)
                    Text("Save to:")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Picker("", selection: $selectedFolder) {
                    ForEach(dynamicFolders, id: \.self) { folder in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(folder.lastPathComponent)
                        }
                        .tag(folder)
                    }
                    HStack {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.secondary)
                        Text("Other")
                    }
                    .tag(URL(string: "other")!)
                }
                .pickerStyle(MenuPickerStyle())
                .padding(8)
                .cornerRadius(10)
                .onChange(of: selectedFolder) { newValue in
                    if newValue == URL(string: "other")! {
                        selectFolder { folderPath in
                            DispatchQueue.main.async {
                                if let folderPath = folderPath {
                                    // Agrega la carpeta seleccionada si no existe
                                    if !dynamicFolders.contains(folderPath) {
                                        dynamicFolders.append(folderPath)
                                    }
                                    customFolder = folderPath
                                    selectedFolder = folderPath
                                } else {
                                    selectedFolder = dynamicFolders.first!
                                }
                            }
                        }
                    }
                }


            }
            .padding(.horizontal)
            
            Divider()
                .padding(.horizontal)
            
            // Action Buttons
            HStack(spacing: 15) {
                Button(action: {
                    isModalPresented = false
                }) {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(DownloadButtonStyle(type: .cancel))
                
                Button(action: {
                    if let episode = currentEpisode {
                        downloadManager.startDownload(
                            vodID: episode.id,
                            title: episode.title,
                            type: mediaType,
                            vodExtension: episode.containerExtension,
                            shouldConvertToMOV: shouldConvertToMOV,
                            downloadPathParam: selectedFolder.path
                        )
                        selectedView = "Downloads"
                        isModalPresented = false
                        onDismiss()
                    }}) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(DownloadButtonStyle(type: .primary))

                
            }
            .padding(.bottom)
        }
        .frame(width: 350)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
    
    private func extractYear(from dateString: String) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: dateString) {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: date)
            return String(year)
        }
        return nil
    }
    
    // Copy selected episode URLs to clipboard
    private func copySelectedURLs() {
        let urls = selectedEpisodes.compactMap { episodeId in
            episodesForSelectedSeason.first { $0.id == episodeId }
        }.map { episode in
            IPTVConfiguration.buildSeriesURL(
                profile: profile,
                vodID: episode.id,
                vodExtension: episode.containerExtension
            )
        }
        
        let urlsText = urls.joined(separator: "\n")
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlsText, forType: .string)
        #else
        UIPasteboard.general.string = urlsText
        #endif
        
        print("Copied \(urls.count) URLs to clipboard")
    }
    
    // Copy selected episode IDs to clipboard in format "id1,id2,id3"
    private func copySelectedIDs() {
        let ids = selectedEpisodes.sorted().joined(separator: ",")
        let formattedIds = "\"\(ids)\""
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedIds, forType: .string)
        #else
        UIPasteboard.general.string = formattedIds
        #endif
        
        print("Copied IDs to clipboard: \(formattedIds)")
    }
}

class LocalObserver: NSObject {
    @objc override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status", let player = object as? AVPlayer {
            if player.status == .failed {
                if let error = player.error as NSError?, error.domain == AVFoundationErrorDomain {
                    print("Server connection failed, retrying in 5 seconds...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        player.replaceCurrentItem(with: player.currentItem)
                        player.play()
                    }
                }
            }
        }
    }
}

// MARK: - Streaming Functions
extension AddDownloadViewSerie {
    private func playEpisode(episode: SerieDetail.Episode) {
        showInlinePlayer ? closePlayer() : initializeEpisodePlayback(episode: episode)
    }
    
    private func initializeEpisodePlayback(episode: SerieDetail.Episode) {
        LiveLogger.debug("Initializing stream for episode: \(episode.title)")
        
        guard let urlString = IPTVConfiguration.buildSeriesURL(
            profile: profile,
            vodID: episode.id,
            vodExtension: episode.containerExtension
        ).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let originalUrl = URL(string: urlString) else {
            LiveLogger.error("Failed to generate valid stream URL for episode")
            return
        }
        
        LiveLogger.debug("Initial Episode Stream URL: \(originalUrl.absoluteString)")
        
        currentStreamingEpisode = episode
        
        streamManager.resolveStreamURL(from: originalUrl) { resolvedUrl in
            guard let resolvedUrl = resolvedUrl else {
                LiveLogger.error("Failed to resolve episode stream URL")
                return
            }
            
            streamManager.setupStreamPlayer(with: resolvedUrl) { player in
                DispatchQueue.main.async {
                    if let player = player {
                        self.player = player
                        self.showInlinePlayer = true
                        player.play()
                        LiveLogger.debug("✅ Episode stream started successfully")
                    } else {
                        LiveLogger.error("Failed to set up player for episode")
                        self.closePlayer()
                    }
                }
            }
        }
    }
    
    private func closePlayer() {
        LiveLogger.debug("Stopping episode stream playback")
        streamManager.cleanUpPlayer()
        player = nil
        showInlinePlayer = false
        currentStreamingEpisode = nil
    }
    
    private var inlineEpisodePlayerView: some View {
        VStack {
            if let player = player, let episode = currentStreamingEpisode {
                VStack(spacing: 8) {
                    Text("Episode \(episode.episodeNum): \(episode.title)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VideoPlayer(player: player)
                        .frame(height: 250)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                }
            } else {
                VStack {
                    ProgressView()
                        .frame(width: 32, height: 32)
                        .padding(.bottom, 8)
                    Text("Configurando reproductor...")
                        .foregroundColor(.secondary)
                }
                .frame(height: 250)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            
            Button(action: closePlayer) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.white)
                    Text("Cerrar Reproducción")
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Selector de Carpeta
extension View {
    func selectFolder(completion: @escaping (URL?) -> Void) {
        #if os(macOS)
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Select"

            panel.begin { result in
                if result == .OK {
                    completion(panel.url)
                } else {
                    completion(nil)
                }
            }
        }
        #else
        print("Folder selection is not supported on iOS.")
        completion(nil)
        #endif
    }
}

struct EpisodeRow: View {
    let episode: SerieDetail.Episode
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let downloadAction: () -> Void
    let playAction: () -> Void
    
    @EnvironmentObject var profile: IPTVProfile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Checkbox
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading) {
                    Text("Episode \(episode.episodeNum)")
                        .font(.headline)
                    Text(episode.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                DownloadButton(action: downloadAction)
                
                Button(action: {
                    playAction()
                }) {
                    Image(systemName: "play.circle")
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
                
                // VLC button
                OpenInVLCButton(urlProvider: {
                    return IPTVConfiguration.buildSeriesURL(
                        profile: profile,
                        vodID: episode.id,
                        vodExtension: episode.containerExtension
                    )
                }, label: "VLC")
                .controlSize(.small)
                .padding(.leading, 8)
                
                // Copy URL button
                Button(action: {
                    let url = IPTVConfiguration.buildSeriesURL(
                        profile: profile,
                        vodID: episode.id,
                        vodExtension: episode.containerExtension
                    )
                    
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    #else
                    UIPasteboard.general.string = url
                    #endif
                    
                    print("URL copiada al portapapeles: \(url)")
                }) {
                    Image(systemName: "link")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
                .help("Copiar URL")
            }
            
            Text("Extension: \(episode.containerExtension)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !episode.info.plot.isEmpty {
                Text(episode.info.plot)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}



struct AddDownloadViewSerie_Previews: PreviewProvider {
    static var previews: some View {
        let mockSerieDetail = SerieDetail(
            seasons: [
                SerieDetail.Season(airDate: "", episodeCount: 10, id: "1", name: "Season 1", seasonNumber: 1, overview: "", cover: "", coverBig: ""),
                SerieDetail.Season(airDate: "", episodeCount: 12, id: "2", name: "Season 2", seasonNumber: 2, overview: "", cover: "", coverBig: ""),
                SerieDetail.Season(airDate: "", episodeCount: 10, id: "3", name: "Season 3", seasonNumber: 3, overview: "", cover: "", coverBig: ""),
                SerieDetail.Season(airDate: "", episodeCount: 13, id: "4", name: "Season 4", seasonNumber: 4, overview: "", cover: "", coverBig: "")
            ],
            info: SerieDetail.SerieInfo(
                name: "Mr. Robot(1080p-x265)",
                cover: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/oKIBhzZzDX07SoE2bOLhq2EE8rf.jpg",
                youtubeTrailer: "",
                genre: "Crimen / Drama",
                releaseDate: "2015-05-27",
                plot: "Sigue a un misterioso anarquista que recluta a un joven programador de computadoras (Malek) que sufre de un trastorno antisocial y se conecta a la gente pirateándolos.",
                cast: "Rami Malek, Christian Slater, Carly Chaikin, Martin Wallström, Michael Cristofer",
                rating: "8",
                rating5Based: 4,
                director: "",
                backdropPath: [],
                lastModified: "",
                episodeRunTime: "43",
                categoryId: "126"
            ),
            episodes: [
                "1": [
                    SerieDetail.Episode(
                        id: "25571",
                        episodeNum: 1,
                        title: "Mr. Robot - S01E01 - ep.1.0_holamigo.mov",
                        containerExtension: "mkv",
                        added: "1605606675",
                        info: SerieDetail.EpisodeInfo(
                            movieImage: "https://image.tmdb.org/t/p/w300/lNXkxjiVwWKXalBcDCpntXBBfOh.jpg",
                            releaseDate: "2015-06-24",
                            youtubeTrailer: "",
                            plot: "Elliot sufre un trastorno de ansiedad social que le hace un bicho raro. Retraído, obsesivo y paranoico, su única manera de conectar con la gente es hackeando sus vidas.",
                            cast: "",
                            rating: 8,
                            rating5Based: 4,
                            director: "",
                            durationSecs: 3900,
                            duration: "01:05:00"
                        ),
                        season: 1,
                        customSid: "",
                        directSource: ""
                    ),
                    SerieDetail.Episode(
                        id: "25572",
                        episodeNum: 2,
                        title: "Mr. Robot - S01E02 - ep.1.0_holamigo.mov",
                        containerExtension: "mkv",
                        added: "1605606675",
                        info: SerieDetail.EpisodeInfo(
                            movieImage: "https://image.tmdb.org/t/p/w300/lNXkxjiVwWKXalBcDCpntXBBfOh.jpg",
                            releaseDate: "2015-07-01",
                            youtubeTrailer: "",
                            plot: "Elliot es reclutado por un misterioso líder, Mr. Robot, para unirse a un grupo de hacktivistas. Elliot debe decidir cuánto está dispuesto a comprometerse con la causa.",
                            cast: "",
                            rating: 8,
                            rating5Based: 4,
                            director: "",
                            durationSecs: 3600,
                            duration: "01:00:00"
                        ),
                        season: 1,
                        customSid: "",
                        directSource: ""
                    ),
                ]
            ]
        )

        AddDownloadViewSerie(
            selectedView: .constant("Series"),
            seriesDetail: mockSerieDetail,
            onDismiss: {}
        )
        .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
        .environmentObject(IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
        .previewDevice("Macbook Pro")
        .frame(width: 800, height: 400)
    }
}

