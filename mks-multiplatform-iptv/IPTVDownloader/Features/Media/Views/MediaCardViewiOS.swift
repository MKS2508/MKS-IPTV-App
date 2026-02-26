//
//  MediaCardViewiOS.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 29/3/25.
//

import SwiftUI

// MARK: - MediaCardType Enum
enum MediaCardType {
    case movie(Movie)
    case serie(Serie)
    
    // Crear un MediaCardType a partir del MediaType existente
    init(mediaType: MediaType, movie: Movie? = nil, serie: Serie? = nil) {
        switch mediaType {
        case .movie:
            guard let movie = movie else {
                fatalError("Movie data is required for MovieType")
            }
            self = .movie(movie)
        case .series:
            guard let serie = serie else {
                fatalError("Serie data is required for SeriesType")
            }
            self = .serie(serie)
        }
    }
    
    var mediaType: MediaType {
        switch self {
        case .movie:
            return .movie
        case .serie:
            return .series
        }
    }
    
    var id: String {
        switch self {
        case .movie(let movie):
            return "movie-\(movie.streamId)"
        case .serie(let serie):
            return "serie-\(serie.seriesId)"
        }
    }
    
    var title: String {
        switch self {
        case .movie(let movie):
            return movie.formattedTitle
        case .serie(let serie):
            return serie.formattedTitle
        }
    }
    
    var posterURL: URL? {
        switch self {
        case .movie(let movie):
            return URL(string: movie.streamIcon ?? "")
        case .serie(let serie):
            return URL(string: serie.cover ?? "")
        }
    }
    
    var rating: String {
        switch self {
        case .movie(let movie):
            if let rating5Based = movie.rating5Based {
                return String(format: "%.1f", rating5Based)
            }
            return movie.rating ?? "N/A"
        case .serie(let serie):
            return serie.rating
        }
    }
    
    var placeholderIcon: String {
        switch self {
        case .movie:
            return "film"
        case .serie:
            return "tv"
        }
    }
    
    var mediaName: String {
        switch self {
        case .movie(let movie):
            return movie.name
        case .serie(let serie):
            return serie.name
        }
    }
    
    func tagProvider(config: CardAppearanceConfig) -> any TagContentProvider {
        switch self {
        case .movie(let movie):
            return MovieTagProvider(movie: movie, config: config)
        case .serie(let serie):
            return SerieTagProvider(serie: serie, config: config)
        }
    }
    
    var defaultConfig: CardAppearanceConfig {
        switch self {
        case .movie:
            return .movieDefault
        case .serie:
            return .seriesDefault
        }
    }
}

// MARK: - MediaCardViewiOS Implementación
struct MediaCardViewiOS: View {
    // MARK: - Propiedades
    let mediaCardType: MediaCardType
    var namespace: Namespace.ID
    var onViewDetails: () -> Void
    
    @Environment(\.cardAppearance) private var configFromEnv
    private var config: CardAppearanceConfig {
        // Usar configuración del Environment si está presente, sino la default para el tipo de media
        return configFromEnv == CardAppearanceConfig.default ? mediaCardType.defaultConfig : configFromEnv
    }
    
    @State private var isTapped = false
    @State private var isAppearing = false
    @State private var isDetailsExpanded = false
    @State private var animateGradient = false
    @State private var pulseScale: CGFloat = 1.0
    
    // Valores basados en la plataforma
    #if os(iOS)
    private let posterAspectRatio: CGFloat = 2/3
    private let overlayBlurRadius: CGFloat = 16
    private let textGlowRadius: CGFloat = 6
    private let detailsPadding: CGFloat = 12
    private let titleFontSize: CGFloat = 16
    private let detailsFontSize: CGFloat = 14
    private let smallDetailsFontSize: CGFloat = 12
    #else
    private let posterAspectRatio: CGFloat = 2/3
    private let overlayBlurRadius: CGFloat = 20
    private let textGlowRadius: CGFloat = 8
    private let detailsPadding: CGFloat = 16
    private let titleFontSize: CGFloat = 15
    private let detailsFontSize: CGFloat = 13
    private let smallDetailsFontSize: CGFloat = 11
    #endif
    
    #if os(iOS)
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    #endif
    
    // MARK: - Inicializadores
    init(mediaCardType: MediaCardType, namespace: Namespace.ID, onViewDetails: @escaping () -> Void = {}) {
        self.mediaCardType = mediaCardType
        self.namespace = namespace
        self.onViewDetails = onViewDetails
    }
    
    // Inicializador conveniente que usa el enum MediaType existente
    init(mediaType: MediaType, movie: Movie? = nil, serie: Serie? = nil, namespace: Namespace.ID, onViewDetails: @escaping () -> Void = {}) {
        let cardType = MediaCardType(mediaType: mediaType, movie: movie, serie: serie)
        self.init(mediaCardType: cardType, namespace: namespace, onViewDetails: onViewDetails)
    }
    
    // MARK: - Body
    var body: some View {
        ZStack(alignment: .bottom) {
            // Imagen principal del poster
            posterImage()
            
            // Overlay de detalles
            detailsOverlay
                .padding(detailsPadding)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .background(LiquidGlassAvailability.isAvailable ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial))
                    .blur(radius: isDetailsExpanded ? overlayBlurRadius : 0)
                )
                .opacity(isDetailsExpanded ? 1 : 0)
                .offset(y: isDetailsExpanded ? 0 : 10)
        }
        .aspectRatio(posterAspectRatio, contentMode: .fit)
        .cornerRadius(config.cornerRadius)
        .overlay(borderOverlay)
        .shadow(
            color: .black.opacity(isTapped ? 0.2 : 0.1),
            radius: isTapped ? 8 : 4,
            x: 0,
            y: isTapped ? 4 : 2
        )
        .scaleEffect(isTapped ? 1.02 : 1)
        .brightness(isTapped ? 0.05 : 0)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isTapped)
        .animation(config.expandAnimation, value: isDetailsExpanded)
        .zIndex(isDetailsExpanded ? 1 : 0)
        .contentShape(RoundedRectangle(cornerRadius: config.cornerRadius))
        .simultaneousGesture(tapGesture)
        .simultaneousGesture(longPressGesture)
        .simultaneousGesture(DragGesture().onChanged { _ in }) // Permitir scroll en listas
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        ))
        .onAppear(perform: handleAppear)
        .onChange(of: isDetailsExpanded) { _, newValue in
            handleDetailsExpansionChange(newValue)
        }
    }
    
    // MARK: - Gestos
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { _ in
                withAnimation(config.expandAnimation) {
                    isDetailsExpanded.toggle()
                }
                handleTapFeedback()
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .onChanged { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isTapped = true
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isTapped = false
                }
            }
    }
    
    // MARK: - Subvistas
    private func posterImage() -> some View {
        CachedAsyncImage(url: mediaCardType.posterURL) { phase in
            Group {
                switch phase {
                case .empty:
                    SkeletonLoader()
                        .aspectRatio(posterAspectRatio, contentMode: .fill)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .drawingGroup()
                case .failure:
                    PlaceholderView(
                        systemImage: mediaCardType.placeholderIcon,
                        title: mediaCardType.mediaName,
                        aspectRatio: posterAspectRatio
                    )
                @unknown default:
                    EmptyView()
                }
            }
            .transition(.opacity)
            .clipped()
            .overlay(gradientOverlay)
            .overlay(ratingBadge)
        }
        .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
        .overlay(strokeOverlay)
        .matchedGeometryEffect(id: "\(mediaCardType.id)-cover", in: namespace)
    }
    
    private var detailsOverlay: some View {
        let tagProvider = mediaCardType.tagProvider(config: config)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Título
            Text(mediaCardType.title)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: textGlowRadius, x: 0, y: 2)
                .matchedGeometryEffect(id: "\(mediaCardType.id)-title", in: namespace)
            
            HStack {
                // Tags básicos
                HStack(spacing: 6) {
                    ForEach(Array(tagProvider.basicTags().enumerated()), id: \.offset) { _, tag in
                        TagView(
                            icon: tag.icon,
                            text: tag.text,
                            fontSize: detailsFontSize,
                            backgroundColor: Color(.darkGray).opacity(0.5)
                        )
                    }
                }
                
                Spacer()
                
                if isDetailsExpanded {
                    detailButton
                } else {
                    enhancedRatingView
                }
            }
            .matchedGeometryEffect(id: "\(mediaCardType.id)-details", in: namespace)
            
            if isDetailsExpanded {
                expandedDetails(with: tagProvider)
            }
        }
    }
    
    private func expandedDetails(with provider: any TagContentProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(provider.expandedTags().enumerated()), id: \.offset) { _, tag in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: tag.icon)
                        .font(.system(size: detailsFontSize))
                        .frame(width: 20)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(tag.text)
                        .font(.system(size: detailsFontSize, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Componentes UI
    private var detailButton: some View {
        Button(action: onViewDetails) {
            Text("Details")
                .font(.system(size: detailsFontSize, weight: .semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.appGlassProminent)
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.1), .black.opacity(0.3), .black.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(isDetailsExpanded ? 0 : 0.8)
        .animation(.easeInOut(duration: 0.3), value: isDetailsExpanded)
    }
    
    private var ratingBadge: some View {
        RatingBadgeView(
            rating: mediaCardType.rating,
            style: config.ratingStyle,
            fontSize: smallDetailsFontSize
        )
        .padding(6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.6))
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        )
        .padding(8)
        .opacity(isDetailsExpanded ? 0 : 1)
        .scaleEffect(isDetailsExpanded ? 0.9 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDetailsExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
    
    private var strokeOverlay: some View {
        RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous)
            .stroke(
                Color.secondary.opacity(isTapped ? 0.2 : 0.1),
                lineWidth: isTapped ? 1.5 : 1
            )
            .animation(.easeInOut(duration: 0.2), value: isTapped)
    }
    
    private var borderOverlay: some View {
        Group {
            switch config.borderStyle {
            case .none:
                EmptyView()
                
            case .simple(let color, let width):
                RoundedRectangle(cornerRadius: config.cornerRadius)
                    .stroke(color, lineWidth: isTapped ? width : 0)
                
            case .gradient(let colors, let animated):
                GradientBorderView(
                    cornerRadius: config.cornerRadius,
                    lineWidth: isTapped ? 1.5 : 0,
                    isAnimated: animated && animateGradient,
                    colors: colors
                )
            }
        }
    }
    
    private var enhancedRatingView: some View {
        RatingBadgeView(
            rating: mediaCardType.rating,
            style: config.ratingStyle,
            fontSize: detailsFontSize
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.background))
    }
    
    // MARK: - Métodos de Interacción
    private func handleDetailsExpansionChange(_ expanded: Bool) {
        #if os(iOS)
        if expanded {
            feedbackGenerator.impactOccurred(intensity: 0.7)
        }
        #endif
        
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
            isTapped = expanded
        }
        
        if expanded && !animateGradient {
            withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                animateGradient = true
            }
        }
    }
    
    private func handleTapFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        #endif
    }
    
    private func handleAppear() {
        #if os(iOS)
        feedbackGenerator.prepare()
        #endif
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) {
                isAppearing = true
            }
        }
    }
}

// MARK: - Preview
struct MediaCardViewiOS_Previews: PreviewProvider {
    @Namespace static var previewNamespace
    
    static var previews: some View {
        Group {
            // Movie preview
            MediaCardViewiOS(
                mediaCardType: .movie(sampleMovie),
                namespace: previewNamespace
            )
            .frame(width: 180)
            .previewDisplayName("Movie Card")
            
            // Serie preview
            MediaCardViewiOS(
                mediaCardType: .serie(sampleSerie),
                namespace: previewNamespace
            )
            .frame(width: 180)
            .previewDisplayName("Serie Card")
            
            // Ejemplo usando el enum MediaType existente
            MediaCardViewiOS(
                mediaType: .movie,
                movie: sampleMovie,
                namespace: previewNamespace
            )
            .frame(width: 180)
            .previewDisplayName("Using MediaType Enum")
            
            // Grid preview with custom config
            mediaGridWithCustomConfig
        }
        .previewLayout(.sizeThatFits)
        .background(.background)
    }
    
    // Ejemplo de grid con configuración personalizada
    private static var mediaGridWithCustomConfig: some View {
        let customConfig = CardAppearanceConfig(
            expandAnimation: .spring(response: 0.4, dampingFraction: 0.8),
            cornerRadius: 20,
            maxVisibleTags: 3,
            iconMappings: ["quality": "checkmark.seal", "year": "calendar.circle"],
            ratingStyle: .stars,
            borderStyle: .gradient(colors: [.red.opacity(0.7), .orange.opacity(0.7)], animated: true)
        )
        
        return LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)
        ], spacing: 12) {
            // Movie card
            MediaCardViewiOS(
                mediaCardType: .movie(sampleMovie),
                namespace: previewNamespace
            )
            
            // Serie card
            MediaCardViewiOS(
                mediaCardType: .serie(sampleSerie),
                namespace: previewNamespace
            )
        }
        .padding()
        .frame(maxWidth: 600)
        .environment(\.cardAppearance, customConfig)
        .previewDisplayName("Custom Config Grid")
    }
    
    // Datos de ejemplo
    private static let sampleMovie = Movie(
        name: "The Matrix (1999) 4K",
        streamType: "movie",
        streamId: 101,
        tmdbId: nil,
        streamIcon: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg",
        rating: "8.7",
        rating5Based: 4.35,
        added: "2024-01-01",
        isAdult: "0",
        categoryId: "1",
        containerExtension: "mp4",
        customSid: nil,
        directSource: nil
    )
    
    private static let sampleSerie = Serie(
        number: 1,
        name: "Stranger Things (2016)",
        seriesId: 101,
        cover: "https://image.tmdb.org/t/p/original/wemvhUukbaW0HRVkivFXZdjFpmw.jpg",
        plot: "A group of kids uncover a supernatural mystery.",
        cast: "Winona Ryder, David Harbour",
        director: "Duffer Brothers",
        genre: "Sci-Fi, Drama",
        releaseDate: "2016-07-15",
        lastModified: "2024-10-30",
        rating: "8.7",
        rating5Based: 4.35,
        backdropPath: [],
        youtubeTrailer: nil,
        episodeRunTime: "45 min",
        categoryId: "1"
    )
}
