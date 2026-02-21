import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct AddDownloadView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject var profile: IPTVProfile
    @State private var viewModel: MovieDetailViewModel?
    
    private var movieService: MovieService {
        MovieService(profile: profile)
    }
    
    @Binding var selectedView: String?
    let movie: Movie
    let initialMovieDetail: MovieDetail?
    let onDismiss: () -> Void
    
    @State private var mediaType = MediaType.movie
    @State private var isModalPresented = false
    @State private var shouldConvertToMOV = false
    @State private var selectedFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @State private var customFolder: URL? = nil
    @State private var skipFetching: Bool = false
    @State private var showInlinePlayer = false
    @State private var player: AVPlayer?
    
    // Constructor original para Movie
    init(selectedView: Binding<String?>, movie: Movie, onDismiss: @escaping () -> Void) {
        self._selectedView = selectedView
        self.movie = movie
        self.initialMovieDetail = nil
        self.onDismiss = onDismiss
    }
    
    // Nuevo constructor para MovieDetail
    init(selectedView: Binding<String?>, movieDetail: MovieDetail, onDismiss: @escaping () -> Void) {
        self._selectedView = selectedView
        self.movie = movieDetail.movieData
        self.initialMovieDetail = movieDetail
        self.onDismiss = onDismiss
        self._skipFetching = State(initialValue: true)
    }
    
    var availableFolders: [URL] {
        [
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!,
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
        ]
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top toolbar
                HStack {
                    // Refresh button
                    Button(action: {
                        Task {
                            await viewModel?.refresh(movieId: movie.streamId)
                        }
                    }) {
                        Image(systemName: viewModel?.isRefreshing ?? false ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                            .foregroundColor(.secondary)
                            .imageScale(.large)
                            .rotationEffect(.degrees(viewModel?.isRefreshing ?? false ? 360 : 0))
                            .animation((viewModel?.isRefreshing ?? false) ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel?.isRefreshing ?? false)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(viewModel?.isRefreshing ?? false || viewModel?.isLoading ?? false)
                    .padding([.top, .leading], 20)
                    
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
                
                // Main content
                Group {
                    if let viewModel = viewModel {
                        contentViewState(viewModel: viewModel, geometry: geometry)
                    } else {
                        initializingView()
                    }
                }
                .frame(minWidth: 600, minHeight: 400)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isModalPresented) {
            DownloadOptionsModal(
                isModalPresented: $isModalPresented,
                selectedFolder: $selectedFolder,
                shouldConvertToMOV: $shouldConvertToMOV,
                availableFolders: availableFolders,
                onDownload: startDownload
            )
        }
        .onAppear {
            print("🚀 AddDownloadView onAppear - movie: \(movie.name)")
            print("🔍 Estado inicial - viewModel: \(viewModel != nil), skipFetching: \(skipFetching)")
            print("🔍 Estado inicial - initialMovieDetail: \(initialMovieDetail != nil)")
            
            // Inicializar el ViewModel si no existe
            if viewModel == nil {
                print("🔧 Creando nuevo MovieDetailViewModel")
                viewModel = MovieDetailViewModel(movieService: movieService)
                
                // Si recibimos un MovieDetail directamente, lo asignamos
                if let detail = initialMovieDetail {
                    print("📋 Asignando MovieDetail inicial: \(detail.movieData.name)")
                    viewModel?.setMovieDetail(detail)
                }
            }
        }
        .task {
            print("📝 AddDownloadView task - skipFetching: \(skipFetching)")
            print("🔍 Task state - initialMovieDetail: \(initialMovieDetail != nil), viewModel: \(viewModel != nil)")
            
            // Solo hacemos fetch si no tenemos un MovieDetail inicial y el ViewModel está inicializado
            if initialMovieDetail == nil && viewModel != nil {
                print("🔄 Iniciando fetch para movieId: \(movie.streamId)")
                await viewModel?.fetchMovieDetails(for: movie.streamId)
                print("✅ Fetch completado para movieId: \(movie.streamId)")
            } else {
                print("⏭️ Omitiendo fetch - initialMovieDetail: \(initialMovieDetail != nil), viewModel: \(viewModel != nil)")
            }
        }
    }
    
    // MARK: - View States
    
    @ViewBuilder
    private func contentViewState(viewModel: MovieDetailViewModel, geometry: GeometryProxy) -> some View {
        if viewModel.isLoading && !skipFetching {
            DownloadViews.loadingView()
        } else if let error = viewModel.error {
            DownloadViews.errorView(error: error) {
                Task {
                    print("🔄 Reintentando fetch para movieId: \(movie.streamId)")
                    await viewModel.fetchMovieDetails(for: movie.streamId)
                }
            }
        } else if let movieDetail = viewModel.movieDetail {
            VStack(spacing: 0) {
                // Inline player (when active)
                if showInlinePlayer {
                    VStack {
                        if let player = player {
                            VStack(spacing: 8) {
                                Text("Reproduciendo: \(movieDetail.movieData.name)")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                VideoPlayer(player: player)
                                    .frame(height: 250)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                                    )
                                
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
                    }
                    .padding(.horizontal)
                    .padding(.top)
                }
                
                DownloadViews.contentView(
                    geometry: geometry, 
                    movieDetail: movieDetail,
                    profile: profile,
                    onPlay: {
                        showInlinePlayer ? closePlayer() : startMoviePlayback(movieDetail: movieDetail)
                    },
                    onDownload: {
                        isModalPresented = true
                    },
                    onCopyURL: {
                        DownloadActions.copyURLToClipboard(movieDetail: movieDetail, profile: profile)
                    },
                    onOptions: {
                        isModalPresented = true
                    },
                    onCancel: onDismiss
                )
            }
        } else {
            emptyStateView(viewModel: viewModel)
        }
    }
    
    @ViewBuilder
    private func initializingView() -> some View {
        VStack {
            ProgressView()
            Text("Inicializando...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func emptyStateView(viewModel: MovieDetailViewModel) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No hay información disponible")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Cargar datos") {
                Task {
                    print("🔄 Fetch manual para movieId: \(movie.streamId)")
                    await viewModel.fetchMovieDetails(for: movie.streamId)
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
    
    // MARK: - Actions
    
    private func startMoviePlayback(movieDetail: MovieDetail) {
        DownloadActions.playAction(movieDetail: movieDetail, profile: profile) { player in
            self.player = player
            self.showInlinePlayer = true
        }
    }
    
    private func closePlayer() {
        player?.pause()
        player = nil
        showInlinePlayer = false
    }
    
    private func startDownload() {
        print("⬇️ Iniciando descarga de: \(movie.name)")
        print("📁 Carpeta: \(selectedFolder.path)")
        print("🔄 Convertir a MOV: \(shouldConvertToMOV)")

        // Start download directly using DownloadManager (same pattern as series)
        downloadManager.startDownload(
            vodID: String(movie.streamId),
            title: movie.name,
            type: mediaType,
            vodExtension: movie.containerExtension ?? "mp4",
            shouldConvertToMOV: shouldConvertToMOV,
            downloadPathParam: selectedFolder.path
        )
        print("✅ Descarga iniciada correctamente")

        onDismiss()
    }
}

// MARK: - Preview

struct AddDownloadView_Previews: PreviewProvider {
    static var previews: some View {
        let exampleMovie = Movie(
            name: "Si yo fuera rico (2019)",
            streamType: nil,
            streamId: 1007,
            streamIcon: nil,
            rating: "5.9",
            rating5Based: 5.9,
            added: nil,
            isAdult: "no",
            categoryId: "122",
            containerExtension: "mp4",
            customSid: nil,
            directSource: nil
        )
        let downloadManager = DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
        
        AddDownloadView(selectedView: .constant("Movies"), movie: exampleMovie, onDismiss: {})
            .environmentObject(downloadManager)
            .environmentObject(IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
            .frame(width: 800, height: 600)
            .previewDisplayName("AddDownloadView Preview")
    }
}