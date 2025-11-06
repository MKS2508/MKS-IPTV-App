import SwiftUI
import AVKit
import UniformTypeIdentifiers

// Protocolo para unificar SerieDetail y MovieDetail
protocol MediaItem {
    var title: String { get }
    var coverImageUrl: String { get }
    var plotSummary: String { get }
    var genreText: String { get }
    var releaseDateText: String { get }
    var castText: String { get }
    var ratingValue: String { get }
    var rating5BasedValue: Double { get }
    var mediaType: MediaType { get }
    var durationText: String { get }
    var backdropPaths: [String] { get }
}

// Extensión para que SerieDetail conforme al protocolo MediaItem
extension SerieDetail: MediaItem {
    var title: String { return info.name }
    var coverImageUrl: String { return info.cover ?? "" }
    var plotSummary: String { return info.plot }
    var genreText: String { return info.genre }
    var releaseDateText: String { return info.releaseDate }
    var castText: String { return info.cast }
    var ratingValue: String { return info.rating }
    var rating5BasedValue: Double { return info.rating5Based }
    var mediaType: MediaType { return .series }
    var durationText: String { return info.episodeRunTime }
    var backdropPaths: [String] { return info.backdropPath }
}

// Extensión para que MovieDetail conforme al protocolo MediaItem
extension MovieDetail: MediaItem {
    var title: String { return movieData.name }
    var coverImageUrl: String { return movieImage }
    var plotSummary: String { return plot }
    var genreText: String { return genre }
    var releaseDateText: String { return releaseDate }
    var castText: String { return cast.joined(separator: ", ") }
    var ratingValue: String { return rating ?? "N/A" }
    var rating5BasedValue: Double { return Double(rating ?? "") ?? 0 }
    var mediaType: MediaType { return .movie }
    var durationText: String {
        let parts = duration.split(separator: ":")
        if parts.count >= 2 {
            return "\(parts[0])"
        }
        return "0"
    }
    var backdropPaths: [String] { return backdropPath ?? [] }
}

struct AddDownloadMediaViewiOS: View {
    @Binding var selectedView: String?
    let mediaItem: MediaItem
    let onDismiss: () -> Void
    
    // Estado para Series
    @State private var selectedSeason: String = "1"
    @State private var serieDetail: SerieDetail?
    @State private var searchText = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var dominantColor: Color = .black
    @State private var imageLoaded = false
    @State private var initialScrollOffset: CGFloat?
    
    // Estado para la modal de descarga
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var isModalPresented = false
    @State private var currentEpisode: SerieDetail.Episode?
    @State private var shouldConvertToMOV = true
    @State private var selectedFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    @State private var customFolder: URL? = nil
    @State private var showingDocumentPicker = false
    @State private var headerHeight: CGFloat = 300 // Initial value matches maxHeaderHeight
    private let maxExpandedHeight: CGFloat = 350
    private let headerDampeningFactor: CGFloat = 0.6
    private let pillCollapsedHeight: CGFloat = 40
    private let pillExpandedCornerRadius: CGFloat = 0
    private let pillCollapsedCornerRadius: CGFloat = 25
    private let pillBorderWidth: CGFloat = 1

    // Header height constants
    private let maxHeaderHeight: CGFloat = 300
    private let minHeaderHeight: CGFloat = 100
    private let metadataHeightExpanded: CGFloat = 100
    private let metadataHeightCollapsed: CGFloat = 60
    private let otherFolderKey = URL(string: "other")!
    

    private var titleFontSize: CGFloat {
        let maxSize: CGFloat = 32
        let minSize: CGFloat = 22
        let progress = min(1, max(0,
            (headerHeight - minHeaderHeight) / (maxHeaderHeight - minHeaderHeight)
        ))
        return minSize + (maxSize - minSize) * progress
    }

    // Update metadata height calculation
    private var metadataHeight: CGFloat {
        let progress = min(1, max(0,
            (headerHeight - minHeaderHeight) / (maxHeaderHeight - minHeaderHeight)
        ))
        return metadataHeightCollapsed + (metadataHeightExpanded - metadataHeightCollapsed) * progress
    }
    
    @State private var dynamicFolders: [URL] = [
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!,
    ]
    private var backgroundView: some View {
        ZStack {
            Image("backgroundPattern")
                .resizable()            .aspectRatio(contentMode: .fill)  // This will make it fill the space while maintaining aspect ratio
                .ignoresSafeArea()
                
                
            VisualEffect(blurStyle: .dark,
                         vibrancy: true, cornerRadius: 0,
                         opacity: 0.85).ignoresSafeArea(edges: .all)
        }
    }
    var episodesForSelectedSeason: [SerieDetail.Episode] {
        guard let serieDetail = self.mediaItem as? SerieDetail else { return [] }
        
        let episodes = serieDetail.episodes[selectedSeason] ?? []
        if searchText.isEmpty {
            return episodes
        } else {
            return episodes.filter { $0.title.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    
                    // Main scrolling content
                    ScrollView {
                        VStack(spacing: 0) {
                            GeometryReader { headerProxy in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: headerProxy.frame(in: .global).minY
                                    )
                            }
                            .frame(height: headerHeight / 1.2) // Updated to dynamic height
                            .zIndex(2)
                            
                            // Content container
                            contentContainer
                               
                        }
                    }
                    .background(backgroundView)
                    
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        if initialScrollOffset == nil {
                            initialScrollOffset = value
                        }
                        
                        if let initialOffset = initialScrollOffset {
                            let newOffset = value - initialOffset
                            
                            withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.2)) {
                                if newOffset > 0 {
                                    // Expand with dampening
                                    let expansion = newOffset * headerDampeningFactor
                                    headerHeight = min(maxHeaderHeight + expansion, maxExpandedHeight)
                                } else {
                                    // Collapse normally
                                    headerHeight = max(maxHeaderHeight + newOffset, minHeaderHeight)
                                }
                            }
                        }
                    }
                    
                    // Header container
                    VStack(spacing: 0) {
                        ZStack {
                            // Blur background when collapsed
                            if headerHeight <= minHeaderHeight * 1.5 {
                                VisualEffectBlur()
                                    .frame(height: minHeaderHeight)
                            }
                            #if os(iOS) || os(tvOS)
                            headerBackgroundView
                            #endif
                         
                        }
                        Spacer()
                    }
                    .frame(height: headerHeight)
                    .zIndex(3)
                    .hCenter()
                    
                    // Metadata overlay
                    metadataOverlayView
                        .zIndex(4)
                        .offset(y: headerHeight > minHeaderHeight ? 0 : pillCollapsedHeight * 0.5)
                        .animation(.easeInOut, value: headerHeight)
                    
                    navigationControls(geometry: geometry)
                        .zIndex(5)
                }
                .ignoresSafeArea(.all, edges: .top)
            }
            .ignoresSafeArea(.all, edges: .top)
        }
        #if os(iOS)
        .navigationBarHidden(true)
        .scrollIndicators(.hidden)
        #endif
        .sheet(isPresented: $isModalPresented) {
            downloadOptionsModal
                .background(VisualEffectBlur().edgesIgnoringSafeArea(.all))
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(selectedFolder: $selectedFolder)
        }
        .onAppear {
            // Initialize dominant color
            if mediaItem.title.contains("Robot") {
                dominantColor = Color.red.opacity(0.8)
            }
            
            // Si es una serie, guardamos la referencia para acceso más sencillo
            if let serie = mediaItem as? SerieDetail {
                self.serieDetail = serie
                self.selectedSeason = serie.seasons.first?.id ?? "1"
            }
        }
    }

    // MARK: - View Components
    
    private func pillsContent(pillScale: CGFloat, opacity: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                EnhancedInfoPill(
                    text: mediaItem.genreText.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? (mediaItem.mediaType == .series ? "TV Show" : "Movie"),
                    backgroundColor: .blue.opacity(0.9),
                    textColor: .white,
                    emoji: mediaItem.mediaType == .series ? "📺" : "🎬"
                )
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                .scaleEffect(pillScale)
                
                EnhancedInfoPill(
                    text: "\(String(format: "%.1f", mediaItem.rating5BasedValue))",
                    backgroundColor: .yellow.opacity(0.9),
                    textColor: .black,
                    emoji: "⭐"
                )
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                .scaleEffect(pillScale)
                
                // More aggressive threshold for these additional pills
                if headerHeight > minHeaderHeight + 40 {
                    Group {
                        if mediaItem.mediaType == .series, let seriesDetail = mediaItem as? SerieDetail {
                            EnhancedInfoPill(
                                text: "\(seriesDetail.seasons.count) Temporadas",
                                backgroundColor: .purple.opacity(0.9),
                                textColor: .white,
                                emoji: "🎬"
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        
                        if let year = extractYear(from: mediaItem.releaseDateText) {
                            EnhancedInfoPill(
                                text: year,
                                backgroundColor: .gray.opacity(0.9),
                                textColor: .white,
                                emoji: "📅"
                            )
                            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        
                        EnhancedInfoPill(
                            text: "\(mediaItem.durationText) min",
                            backgroundColor: .green.opacity(0.9),
                            textColor: .white,
                            emoji: "⏱️"
                        )
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    }
                    .scaleEffect(pillScale)
                }
            }
            .padding(.horizontal, 20)
            .opacity(opacity)
            // Add a subtle horizontal translation for enhanced animation
            .offset(x: (1 - opacity) * -20, y: 0)
        }
    }

    var metadataOverlayView: some View {
        let isCollapsed = headerHeight <= minHeaderHeight * 1.1
        let isExpanded = headerHeight >= minHeaderHeight * 1.5
        let isTransitioning = !isCollapsed && !isExpanded
        
        // Calculate progress for expanded state elements with smoother transition
        let expandedProgress = isExpanded ?
            1.0 :
            max(0, (headerHeight - minHeaderHeight * 1.3) / (minHeaderHeight * 0.2))
        
        // Enhanced scale factor for pills with better curve
        let pillScale = 0.8 + (0.2 * pow(expandedProgress, 0.7))
        
        return VStack {
            Spacer()
            
            // Content container - Modifica esto para que el blur solo aplique a la parte inferior
            VStack(alignment: .leading, spacing: 0) {
                // Solo mostrar el espacio vacío en la parte superior cuando no está colapsado
                if !isCollapsed {
                    Spacer()
                }
                
                // Solo mostrar contenido expandido cuando está en transición a expandido o completamente expandido
                if !isCollapsed {
                    // Contenedor para el contenido con blur solo en la parte inferior
                    ZStack(alignment: .leading) {
                        // Blur con altura fija para la parte inferior
                        VisualEffect(
                            blurStyle: .systemThinMaterial,
                            vibrancy: true,
                            opacity: 0.35
                        )
                        .cornerRadius(16 * expandedProgress, corners: [.topLeft, .topRight])
                        
                        // Content overlay
                        VStack(alignment: .leading, spacing: 12 * expandedProgress) {
                            Text(mediaItem.title)
                                .font(.system(size: titleFontSize * max(expandedProgress, 0.7), weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
                            
                            // Solo mostrar pills cuando estamos cerca o en estado expandido con transición mejorada
                            if expandedProgress > 0.9 {
                                pillsContent(
                                    pillScale: pillScale,
                                    opacity: pow((expandedProgress - 0.7) / 0.3, 0.8) // Fade-in más suave
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16 * expandedProgress)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Define una altura específica para el área de blur (ajusta según necesites)
                    .frame(height: min(160, headerHeight * 0.4))
                }
            }
            .opacity(expandedProgress)
        }
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
        // Usa una curva de animación más responsiva con mejor física
        .animation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0), value: headerHeight)
    }
    private var pillCornerRadius: CGFloat {
        // Define the threshold where we start changing corner radius
        let transitionThreshold: CGFloat = minHeaderHeight * 1.5
        let snapThreshold: CGFloat = minHeaderHeight * 1.2
        
        // Implement a snapping behavior rather than continuous transition
        if headerHeight <= snapThreshold {
            return 16 // Fully rounded when collapsed or near collapsed
        } else if headerHeight >= transitionThreshold {
            return 0 // No corner radius when fully expanded
        } else {
            // Create a more decisive transition in the middle range
            // Use a cubic easing function to accelerate the transition
            let progress = 1.0 - ((headerHeight - snapThreshold) / (transitionThreshold - snapThreshold))
            let easedProgress = pow(progress, 3) // Cubic easing for faster transition
            return 16 * easedProgress
        }
    }
    
    #if os(iOS)
    // Adjust header progress calculation to be used for various animations
    var headerBackgroundView: some View {
        let isCollapsed = headerHeight <= minHeaderHeight * 1.1 // Slightly higher threshold
        let isExpanded = headerHeight >= minHeaderHeight * 1.5
        let isTransitioning = !isCollapsed && !isExpanded
        
        // Calculate dynamic width with snapping behavior
        let dynamicWidth: CGFloat
        if isCollapsed {
            dynamicWidth = UIScreen.main.bounds.width * 0.4 // Pill width when collapsed
        } else if isExpanded {
            dynamicWidth = UIScreen.main.bounds.width // Full width when expanded
        } else {
            // More decisive transition in between states
            let progress = (headerHeight - minHeaderHeight * 1.1) / (minHeaderHeight * 0.4)
            let easedProgress = 1 - pow(1 - min(max(progress, 0), 1), 2) // Quadratic ease-out
            dynamicWidth = UIScreen.main.bounds.width * 0.4 + (UIScreen.main.bounds.width * 0.6) * easedProgress
        }
        
        // Calculate a refined cornerRadius with smooth transition
        let pillCornerRadius: CGFloat = isCollapsed ?
            pillCollapsedCornerRadius :
            max(pillExpandedCornerRadius, pillCollapsedCornerRadius - (pillCollapsedCornerRadius * (headerHeight - minHeaderHeight) / (maxHeaderHeight - minHeaderHeight)))
        
        return ZStack {
            // Background image with enhanced blur effect when collapsed
            AsyncImage(url: URL(string: mediaItem.coverImageUrl)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: headerHeight , alignment: .center)
                        // Apply dynamic blur effect for smoother transition
                        .blur(radius: isCollapsed ? 15 : isExpanded ? 0 : 15 * (1 - (headerHeight - minHeaderHeight) / (maxHeaderHeight - minHeaderHeight)))
                        // Use the refined pillCornerRadius property
                        .clipShape(
                            RoundedRectangle(cornerRadius: 0)
                        )
                        
                        // Add a subtle inner shadow for depth
                } else {
                    LoadingPlaceholderView()
                        .clipShape(RoundedRectangle(cornerRadius: pillCornerRadius))
                }
            }
        }
        .overlay(collapsedTitleOverlay)
        // Use a more responsive animation curve with longer duration for smoother transitions
        .animation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0), value: headerHeight)
    }
    #endif
    // Propiedad collapsedTitleOverlay refactorizada
    private var collapsedTitleOverlay: some View {
        Group {
            let isCollapsed = headerHeight <= minHeaderHeight * 1.1
            let isExpanded = headerHeight >= minHeaderHeight * 1.5
            let isTransitioning = !isCollapsed && !isExpanded
            
            // Mostrar el título colapsado cuando estamos cerca o en estado colapsado
            if isCollapsed || (isTransitioning && headerHeight < minHeaderHeight * 1.3) {
                // Calcular opacidad basada en qué tan cerca estamos del estado colapsado
                let titleOpacity = isCollapsed ?
                    1.0 :
                    1.0 - ((headerHeight - minHeaderHeight) / (minHeaderHeight * 0.3))
                
                CollapsedTitleBadgeView(
                    title: mediaItem.title,
                    imageURL: mediaItem.coverImageUrl,
                    opacity: titleOpacity
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(y: headerHeight - pillCollapsedHeight * 1.5)
                // Efectos de transición mejorados
                .scaleEffect(isCollapsed ? 1.0 : 0.95)
                .blur(radius: isCollapsed ? 0 : 0.5)
                // Animación suave con efecto de rebote
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isCollapsed)
            }
        }
    }
    
    // Update the collapsedTitleOverlay to create a seamless transition with the expanded title
    private var headerProgress: CGFloat {
        let transitionThreshold: CGFloat = minHeaderHeight * 1.2
        
        if headerHeight > transitionThreshold {
            return 1.0 // Fully expanded
        } else if headerHeight <= minHeaderHeight {
            return 0.0 // Fully collapsed
        } else {
            // Linear progress between transition threshold and min height
            return (headerHeight - minHeaderHeight) / (transitionThreshold - minHeaderHeight)
        }
    }
    
    private func handleScrollOffset(_ value: CGFloat) {
        if initialScrollOffset == nil { initialScrollOffset = value }
        
        guard let initialOffset = initialScrollOffset else { return }
        let newOffset = value - initialOffset
        
        // Define thresholds for state transitions
        let collapsedThreshold: CGFloat = -20 // Small negative scroll to trigger collapse
        let expandedThreshold: CGFloat = 20 // Small positive scroll to trigger expansion
        
        // Determine target height based on scroll direction and velocity
        let targetHeight: CGFloat
        if newOffset < collapsedThreshold {
            // Collapse to minimum height
            targetHeight = minHeaderHeight
        } else if newOffset > expandedThreshold {
            // Expand with dampening
            let expansion = newOffset * headerDampeningFactor
            targetHeight = min(maxHeaderHeight + expansion, maxExpandedHeight)
        } else {
            // Stay at current height with small adjustments
            targetHeight = max(maxHeaderHeight + newOffset, minHeaderHeight)
        }
        
        // Apply animation with improved spring parameters for more responsive feel
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0)) {
            headerHeight = targetHeight
        }
    }
    
    var contentContainer: some View {
        
        ZStack {
     
            VStack(spacing: 25) {
                
                // Media description and cast
                mediaInfoView
                    .padding(.top, 80)
                    .padding(.horizontal, 10)
                
                // Action buttons
                actionButtonsView
                    .padding(.horizontal, 20)
                
                // Series-specific content (conditional display)
                if mediaItem.mediaType == .series {
                    // Season selector
                    seasonSelectorView
                    
                    // Episodes list
                    episodesListView
                        .padding(.bottom, 30)
                }
            }.zIndex(20)
        }
    }
    
    var mediaInfoView: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Plot description - Remove the fixedSize modifier that's blocking scrolling
            Text(mediaItem.plotSummary)
                .font(.headline)
                .foregroundColor(.primary.opacity(0.8))
                .padding(.bottom, 8)
                .allowsHitTesting(false) // Add this to prevent the text from capturing gestures
            
            if !mediaItem.castText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reparto")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(mediaItem.castText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .allowsHitTesting(false) // Add this to prevent the text from capturing gestures
                }
                .padding(.top, 4)
                .allowsHitTesting(false) // Add this to prevent the container from capturing gestures
            }
        }
        .contentShape(Rectangle()) // Add this to ensure the entire area responds to gestures properly
    }
    
    var actionButtonsView: some View {
        HStack(spacing: 20) {
            // Botón de Reproducción
            Button(action: playAction) {
                buttonContent(
                    icon: "play.fill",
                    label: "Reproducir",
                    style: .primary,
                    iconSize: 18,  // Tamaño aumentado
                    labelSize: 18  // Tamaño aumentado
                )
         
            }
            
            // Botón de Descarga
            Button(action: handleDownloadAction) {
                buttonContent(
                    icon: "arrow.down",
                    label: downloadButtonLabel,
                    style: .secondary,
                    iconSize: 20,  // Tamaño aumentado
                    labelSize: 10  // Tamaño aumentado
                )
              
            }
        }
    }

    // Variables computadas para mejor organización
    private var downloadButtonLabel: String {
        mediaItem.mediaType == .series ? "Descargar Todo" : "Descargar"
    }

    private func playAction() {
        // Lógica de reproducción común
    }

    private func handleDownloadAction() {
        if mediaItem.mediaType == .movie {
            isModalPresented = true
        } else {
//            downloadSeasonContent()
        }
    }

    // Función buttonContent modificada para soportar tamaños
    func buttonContent(
        icon: String,
        label: String,
        style: ButtonStyleType,
        iconSize: CGFloat = 14,
        labelSize: CGFloat = 15
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
            
            Text(label)
                .font(.system(size: labelSize, weight: .semibold))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(buttonBackground(for: style))
        .foregroundColor(style == .primary ? .white : .white.opacity(0.9))
    }
    
    private struct SeasonButton: View {
        let name: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(
                        isSelected ? Color.red : Color.secondarySystemBackground
                    )
                    .foregroundColor(isSelected ? .white : .primary)
                    .cornerRadius(12)
            }
        }
    }
    private struct SeasonsScrollView: View {
        let seasons: [SerieDetail.Season]
        @Binding var selectedSeason: String
        
        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(seasons, id: \.id) { season in
                        SeasonButton(
                            name: season.name,
                            isSelected: selectedSeason == season.id,
                            action: { selectedSeason = season.id }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 5)
            }
            .scrollDisablesDrag(false)
        }
    }
    
    var seasonSelectorView: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("TEMPORADAS")
                .sectionHeaderStyle()
            
            if let serieDetail = serieDetail {
                SeasonsScrollView(
                    seasons: serieDetail.seasons,
                    selectedSeason: $selectedSeason
                )
            }
        }
        .padding(.bottom, 10)
    }
    var episodesListView: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText)
                .padding(.horizontal, 20)
                .padding(.bottom, 15)
            
            if episodesForSelectedSeason.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "tv.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("No hay episodios disponibles")
                        .font(.headline)
                    
                    if !searchText.isEmpty {
                        Text("Intenta con otra búsqueda")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 50)
            } else {
                LazyVStack(spacing: 15) {
                    ForEach(episodesForSelectedSeason, id: \.id) { episode in
                        EpisodeCard(
                            episode: episode,
                            downloadAction: {
                                currentEpisode = episode
                                isModalPresented = true
                            },
                            playAction: {
                                // Play action
                            }
                        )
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
        }
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
            .padding(.top, 40)
            
            Spacer()
        }
        .frame(height: 100)
    }
    
    var downloadOptionsModal: some View {
        VStack(spacing: 20) {
            // Header with close button
            HStack {
                Text("Opciones de Descarga")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    isModalPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Media info (condicional según el tipo)
            if mediaItem.mediaType == .series, let episode = currentEpisode {
                HStack(spacing: 15) {
                    AsyncImage(url: URL(string: episode.info.movieImage)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 45)
                                .cornerRadius(6)
                        } else {
                            Color.secondarySystemBackground
                                .frame(width: 80, height: 45)
                                .cornerRadius(6)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(mediaItem.title) • S\(episode.season)E\(episode.episodeNum)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(episode.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(episode.info.duration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 15)
                .background(Color.secondarySystemBackground.opacity(0.5))
                .cornerRadius(10)
            } else if mediaItem.mediaType == .movie, let movie = mediaItem as? MovieDetail {
                HStack(spacing: 15) {
                    AsyncImage(url: URL(string: movie.movieImage)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 45)
                                .cornerRadius(6)
                        } else {
                            Color.secondarySystemBackground
                                .frame(width: 80, height: 45)
                                .cornerRadius(6)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.genre)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(movie.movieData.name)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(movie.duration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 15)
                .background(Color.secondarySystemBackground.opacity(0.5))
                .cornerRadius(10)
            }
            
            // Options
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
                        .background(Color
                            .secondarySystemBackground)
                        .cornerRadius(12)
                    }
                }
            }
            
            Spacer()
            
            // Action buttons (condicionales según el tipo)
            VStack(spacing: 10) {
                if mediaItem.mediaType == .series {
                    Button("Descargar Episodio") {
                        if let episode = currentEpisode {
                            downloadManager.startDownload(
                                vodID: episode.id,
                                title: episode.title,
                                type: mediaItem.mediaType,
                                vodExtension: episode.containerExtension,
                                shouldConvertToMOV: shouldConvertToMOV,
                                downloadPathParam: selectedFolder.path
                            )
                            selectedView = "Downloads"
                            isModalPresented = false
                            onDismiss()
                        }
                    }
                    .buttonStyle(NeumorphicButtonStyle(color: .blue))
                } else if let movie = mediaItem as? MovieDetail {
                    Button("Descargar Película") {
                        downloadManager.startDownload(
                            vodID: String(movie.tmdbId),
                            title: movie.movieData.name,
                            type: mediaItem.mediaType,
                            vodExtension: movie.movieData.containerExtension ?? "mkv",
                            shouldConvertToMOV: shouldConvertToMOV,
                            downloadPathParam: selectedFolder.path
                        )
                        selectedView = "Downloads"
                        isModalPresented = false
                        onDismiss()
                    }
                    .buttonStyle(NeumorphicButtonStyle(color: .blue))
                }
                
                Button("Cancelar") {
                    isModalPresented = false
                }
                .buttonStyle(NeumorphicButtonStyle(color: Color.secondarySystemBackground))
            }
        }
        .padding(25)
        .background(Color.systemBackground)
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

extension Text {
    func sectionHeaderStyle() -> some View {
        self
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
    }
}

// MARK: - Previews
struct AddDownloadMediaViewiOS_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview con SerieDetail
            let mockSerieDetail = SerieDetail(
                seasons: [
                    SerieDetail.Season(airDate: "", episodeCount: 10, id: "1", name: "Temporada 1", seasonNumber: 1, overview: "", cover: "", coverBig: ""),
                    SerieDetail.Season(airDate: "", episodeCount: 10, id: "2", name: "Temporada 2", seasonNumber: 2, overview: "", cover: "", coverBig: "")
                ],
                info: SerieDetail.SerieInfo(
                    name: "Mr. Robot",
                    cover: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/oKIBhzZzDX07SoE2bOLhq2EE8rf.jpg",
                    youtubeTrailer: "",
                    genre: "Drama",
                    releaseDate: "2015-05-27",
                    plot: "Sigue a un misterioso anarquista que recluta a un joven programador de computadoras...",
                    cast: "Rami Malek, Christian Slater",
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
                            title: "Pilot",
                            containerExtension: "mkv",
                            added: "1605606675",
                            info: SerieDetail.EpisodeInfo(
                                movieImage: "https://image.tmdb.org/t/p/w300/lNXkxjiVwWKXalBcDCpntXBBfOh.jpg",
                                releaseDate: "2015-06-24",
                                youtubeTrailer: "",
                                plot: "Elliot sufre un trastorno de ansiedad social...",
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
                            title: "Pilot2",
                            containerExtension: "mkv",
                            added: "1605606675",
                            info: SerieDetail.EpisodeInfo(
                                movieImage: "https://image.tmdb.org/t/p/w300/lNXkxjiVwWKXalBcDCpntXBBfOh.jpg",
                                releaseDate: "2015-06-24",
                                youtubeTrailer: "",
                                plot: "Elliot sufre un trastorno de ansiedad social...",
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
                        )
                    ],
                    "2": [
                        SerieDetail.Episode(
                            id: "25572",
                            episodeNum: 1,
                            title: "fsociety.dat",
                            containerExtension: "mkv",
                            added: "1605606675",
                            info: SerieDetail.EpisodeInfo(
                                movieImage: "https://image.tmdb.org/t/p/w300/lNXkxjiVwWKXalBcDCpntXBBfOh.jpg",
                                releaseDate: "2015-06-24",
                                youtubeTrailer: "",
                                plot: "Elliot sufre un trastorno de ansiedad social...",
                                cast: "",
                                rating: 8,
                                rating5Based: 4,
                                director: "",
                                durationSecs: 3900,
                                duration: "01:05:00"
                            ),
                            season: 2,
                            customSid: "",
                            directSource: ""
                        )
                    ]
                ]
            )
            
            AddDownloadMediaViewiOS(
                selectedView: .constant("Series"),
                mediaItem: mockSerieDetail,
                onDismiss: {}
            )
            .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
            .previewDisplayName("Series View")
            
            // Preview con MovieDetail
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
            
            let mockMovieDetail = MovieDetail(
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
            
            AddDownloadMediaViewiOS(
                selectedView: .constant("Movies"),
                mediaItem: mockMovieDetail,
                onDismiss: {}
            )
            .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
            .previewDisplayName("Movie View")
        }
    }
}
