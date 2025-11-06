//
//  AddDownloadViewMovieiOS.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 20/3/25.
//


// AddDownloadViewMovieiOS.swift - Movie view implementation
import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct AddDownloadViewMovieiOS: View {
    @Binding var selectedView: String?
    let movieDetail: MovieDetail
    let onDismiss: () -> Void
    
    @State private var mediaType = MediaType.movie
    @State private var searchText = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var dominantColor: Color = .black
    @State private var imageHeight: CGFloat = 300
    
    @EnvironmentObject private var downloadManager: DownloadManager
    
    @State private var isModalPresented = false
    @State private var shouldConvertToMOV = true
    @State private var selectedFolder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    @State private var showingDocumentPicker = false
    @State private var imageLoaded = false
    @State private var folderAccessError = false
    
    private let headerHeight: CGFloat = 300
    private let metadataHeight: CGFloat = 100
    
    // iOS compatible dynamic folders
    @State private var dynamicFolders: [URL] = [
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    ]
    
    // Initialize the view and try to restore bookmarked folder
    init(selectedView: Binding<String?>, movieDetail: MovieDetail, onDismiss: @escaping () -> Void) {
        self._selectedView = selectedView
        self.movieDetail = movieDetail
        self.onDismiss = onDismiss
        
        // Try to restore bookmarked folder if available
        if let bookmarkData = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                  options: .withoutUI,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale)
                if !isStale {
                    _selectedFolder = State(initialValue: url)
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    // Content scrollview
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: headerHeight)
                            
                            VStack(spacing: 0) {
                                contentContainer
                                    .background(Color.systemBackground)
                                    .cornerRadius(20)
                                    .offset(y: -30)
                            }
                        }
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("scroll")).minY)
                            }
                        )
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetKey.self) { value in
                        scrollOffset = value
                    }
                    
                    // Header background
                    headerBackgroundView
                        .frame(height: headerHeight)
                        .zIndex(0)
                    
                    // Metadata overlay
                    metadataOverlayView
                        .frame(height: metadataHeight)
                        .offset(y: headerHeight - metadataHeight)
                        .zIndex(1)
                    
                    // Navigation controls
                    navigationControls(geometry: geometry)
                        .zIndex(2)
                }
                .edgesIgnoringSafeArea(.top)
                #if os(iOS)
                .navigationBarHidden(true)
                #endif
                .sheet(isPresented: $isModalPresented) {
                    downloadOptionsModal
                        .background(VisualEffectBlur().edgesIgnoringSafeArea(.all))
                }
                .sheet(isPresented: $showingDocumentPicker) {
                    DocumentPicker(selectedFolder: $selectedFolder)
                }
                .alert(isPresented: $folderAccessError) {
                    Alert(
                        title: Text("Error de Acceso"),
                        message: Text("No se puede acceder a la carpeta seleccionada. Por favor, elija otra ubicación."),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .onAppear {
                    if movieDetail.movieData.name.contains("Matrix") {
                        dominantColor = Color.green.opacity(0.8)
                    }
                    
                    // On iOS, we can only guarantee access to document directory and caches
                    #if os(iOS)
                    dynamicFolders = [
                        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
                        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                    ]
                    
                    // Set default folder to documents directory
                    if !isSelectedFolderAccessible() {
                        selectedFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                    }
                    #endif
                }
            }
        }
    }
    
    // MARK: - iOS Folder Access Functions
    
    private func isSelectedFolderAccessible() -> Bool {
        // For standard system directories
        if dynamicFolders.contains(selectedFolder) {
            return true
        }
        
        // For security-scoped URLs
        let canAccess = selectedFolder.startAccessingSecurityScopedResource()
        if canAccess {
            do {
                let values = try selectedFolder.resourceValues(forKeys: [.isWritableKey])
                let isWritable = values.isWritable ?? false
                selectedFolder.stopAccessingSecurityScopedResource()
                return isWritable
            } catch {
                selectedFolder.stopAccessingSecurityScopedResource()
                return false
            }
        }
        
        return false
    }
    
    // MARK: - View Components
    
    var headerBackgroundView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                AsyncImage(url: URL(string: movieDetail.movieImage)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: headerHeight + (scrollOffset < 0 ? min(-scrollOffset, 100) : 0))
                            .clipped()
                            .overlay(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        .clear,
                                        .clear,
                                        dominantColor.opacity(0.3),
                                        dominantColor.opacity(0.6),
                                        dominantColor.opacity(0.8),
                                        dominantColor.opacity(0.95)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .offset(y: scrollOffset < 0 ? scrollOffset / 2 : 0)
                    } else {
                        ZStack {
                            Color.gray.opacity(0.3)
                            ProgressView()
                        }
                    }
                }
            }
        }
    }
    
    var metadataOverlayView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(movieDetail.movieData.name)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                .lineLimit(2)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    EnhancedInfoPill3(
                        text: movieDetail.genre.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? "Movie",
                        emoji: "🎬",
                        textColor: .white
                    )
                    
                    if let rating = movieDetail.rating {
                        EnhancedInfoPill(
                            text: rating,
                            backgroundColor: .yellow.opacity(0.8),
                            textColor: .black,
                            emoji: "⭐"
                        )
                    }
                    
                    if let year = extractYear(from: movieDetail.releaseDate) {
                        EnhancedInfoPill(
                            text: year,
                            backgroundColor: .gray.opacity(0.8),
                            textColor: .white,
                            emoji: "📅"
                        )
                    }
                    
                    EnhancedInfoPill(
                        text: movieDetail.duration,
                        backgroundColor: .green.opacity(0.8),
                        textColor: .white,
                        emoji: "⏱️"
                    )
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }
    
    var contentContainer: some View {
        VStack(spacing: 25) {
            movieInfoView
                .padding(.top, 80)
                .padding(.horizontal, 10)
            
            actionButtonsView
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
        }
    }
    
    var movieInfoView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(movieDetail.plot)
                .font(.body)
                .foregroundColor(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            
            if !movieDetail.cast.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reparto")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(movieDetail.cast.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.top, 4)
            }
            
            if !movieDetail.director.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Director")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(movieDetail.director)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    var actionButtonsView: some View {
        HStack(spacing: 15) {
            Button(action: {}) {
                HStack {
                    Image(systemName: "play.fill")
                        .font(.body)
                    Text("Reproducir")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(25)
            }
            
            Button(action: { isModalPresented = true }) {
                HStack {
                    Image(systemName: "arrow.down")
                        .font(.body)
                    Text("Descargar")
                        .fontWeight(.medium)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .cornerRadius(25)
            }
        }
        .padding(.vertical, 5)
    }
    
    func navigationControls(geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, geometry.safeAreaInsets.top)
            
            Spacer()
        }
        .frame(height: 100)
    }
    
    var downloadOptionsModal: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Opciones de Descarga")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: { isModalPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            HStack(spacing: 15) {
                AsyncImage(url: URL(string: movieDetail.movieImage)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 120)
                            .cornerRadius(6)
                    } else {
                        Color.secondarySystemBackground
                            .frame(width: 80, height: 120)
                            .cornerRadius(6)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(movieDetail.movieData.name)
                        .font(.headline)
                        .lineLimit(2)
                    
                    Text(movieDetail.duration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let year = extractYear(from: movieDetail.releaseDate) {
                        Text(year)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 15)
            .background(Color.secondarySystemBackground.opacity(0.5))
            .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 15) {
                Toggle(isOn: $shouldConvertToMOV) {
                    Label("Convertir a MOV", systemImage: "film")
                        .font(.subheadline)
                }
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Guardar en:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Menu {
                        ForEach(dynamicFolders, id: \.self) { folder in
                            Button(folder.lastPathComponent) {
                                selectedFolder = folder
                            }
                        }
                        Button {
                            showingDocumentPicker = true
                        } label: {
                            Label("Otra ubicación", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.blue)
                            Text(selectedFolder.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.secondarySystemBackground)
                        .cornerRadius(12)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 10) {
                Button("Descargar Película") {
                    // Check access before downloading
                    if isSelectedFolderAccessible() {
                        // Start accessing the security-scoped resource if needed
                        let needsSecurityAccess = !dynamicFolders.contains(selectedFolder)
                        let canAccess = needsSecurityAccess ? selectedFolder.startAccessingSecurityScopedResource() : true
                        
                        if canAccess {
                            downloadManager.startDownload(
                                vodID: String(movieDetail.movieData.streamId),
                                title: movieDetail.movieData.name,
                                type: mediaType,
                                vodExtension: movieDetail.movieData.containerExtension ?? "mkv",
                                shouldConvertToMOV: shouldConvertToMOV,
                                downloadPathParam: selectedFolder.path
                            )
                            
                            // Stop accessing the security-scoped resource if needed
                            if needsSecurityAccess {
                                selectedFolder.stopAccessingSecurityScopedResource()
                            }
                            
                            selectedView = "Downloads"
                            isModalPresented = false
                            onDismiss()
                        } else {
                            folderAccessError = true
                        }
                    } else {
                        folderAccessError = true
                    }
                }
                .buttonStyle(NeumorphicButtonStyle(color: .blue))
                
                Button("Cancelar") {
                    isModalPresented = false
                }
                .buttonStyle(NeumorphicButtonStyle(color: Color.secondarySystemBackground))
            }
        }
        .padding(25)
        .background(.background)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    }
    
    func extractYear(from dateString: String) -> String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = dateFormatter.date(from: dateString) else { return nil }
        return String(Calendar.current.component(.year, from: date))
    }
}

// MARK: - Previews
// MARK: - Previews
struct AddDownloadViewMovieiOS_Previews: PreviewProvider {
    static var previews: some View {
        let mockMovie = Movie(
            name: "The Matrix",
            streamType: "movie",
            streamId: 603,
            streamIcon: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg",
            rating: "8.7",
            rating5Based: 4.35,
            added: "1605606675",
            isAdult: "0",
            categoryId: "1",
            containerExtension: "mkv",
            customSid: nil,
            directSource: nil
        )
        
        let mockDetail = MovieDetail(
            movieData: mockMovie,
            movieImage: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg",
            tmdbId: 603,
            backdrop: "https://image.tmdb.org/t/p/original/8ZTVqvKDQ8emSGUEMjsS4yUEwrN.jpg",
            youtubeTrailer: "vKQi3bBA1y8",
            genre: "Sci-Fi/Action",
            plot: "A computer programmer discovers a mysterious world of digital reality...",
            cast: ["Keanu Reeves", "Laurence Fishburne", "Carrie-Anne Moss"],
            rating: "8.7",
            director: "Lana Wachowski, Lilly Wachoski",
            releaseDate: "1999-03-31",
            backdropPath: ["/8ZTVqvKDQ8emSGUEMjsS4yUEwrN.jpg"],
            durationSecs: 8160,
            duration: "02:16:00"
        )
        
        AddDownloadViewMovieiOS(
            selectedView: .constant("Movies"),
            movieDetail: mockDetail,
            onDismiss: {}
        )
        .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
        .previewDevice("iPhone 15 Pro")
    }
}
