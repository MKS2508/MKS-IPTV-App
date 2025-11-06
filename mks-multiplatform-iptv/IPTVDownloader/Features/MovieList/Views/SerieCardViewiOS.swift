import SwiftUI

// MARK: - SerieCardViewiOS optimizado para iOS
struct SerieCardViewiOS: View {
    let serie: Serie
    @State private var isTapped = false
    @State private var isAppearing = false
    @State private var isDetailsExpanded = false
    @State private var animateGradient = false
    @State private var pulseScale: CGFloat = 1.0
    var namespace: Namespace.ID
    var onViewDetails: () -> Void
    
    init(serie: Serie, namespace: Namespace.ID, onViewDetails: @escaping () -> Void = {}) {
        self.serie = serie
        self.namespace = namespace
        self.onViewDetails = onViewDetails
    }
    
    #if os(iOS)
    private let posterAspectRatio: CGFloat = 2/3
    private let cornerRadius: CGFloat = 16
    private let minPosterWidth: CGFloat = 140
    private let overlayBlurRadius: CGFloat = 16
    private let textGlowRadius: CGFloat = 6
    private let detailsPadding: CGFloat = 12
    private let titleFontSize: CGFloat = 16
    private let detailsFontSize: CGFloat = 14
    private let smallDetailsFontSize: CGFloat = 12
    #else
    private let posterAspectRatio: CGFloat = 2/3
    private let cornerRadius: CGFloat = 12
    private let minPosterWidth: CGFloat = 160
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
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Main poster image
                posterImage(width: geometry.size.width)
                    .frame(width: geometry.size.width)
                
                // Details overlay optimizado
                detailsOverlay
                    .padding(detailsPadding)
                    .frame(width: geometry.size.width)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .black.opacity(0.4),
                                .black.opacity(0.85)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .background(.ultraThinMaterial)
                        .blur(radius: isDetailsExpanded ? overlayBlurRadius : 0)
                    )
                    .opacity(isDetailsExpanded ? 1 : 0)
                    .offset(y: isDetailsExpanded ? 0 : 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.width / posterAspectRatio)
            .cornerRadius(cornerRadius)
            .overlay(gradientBorder)
            .shadow(
                color: .black.opacity(isTapped ? 0.2 : 0.1),
                radius: isTapped ? 8 : 4,
                x: 0,
                y: isTapped ? 4 : 2
            )
            .scaleEffect(isTapped ? 1.02 : 1)
            .brightness(isTapped ? 0.05 : 0)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isTapped)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDetailsExpanded)
            .zIndex(isDetailsExpanded ? 1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .simultaneousGesture(tapGesture)
            .simultaneousGesture(longPressGesture)
            .simultaneousGesture(
                DragGesture().onChanged { _ in } // Permite el scroll
            )
        }
        .aspectRatio(posterAspectRatio, contentMode: .fit)
        .frame(minWidth: minPosterWidth)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        ))
        .onAppear(perform: handleAppear)
        .onChange(of: isDetailsExpanded) { newValue in
            handleDetailsExpansionChange(newValue)
        }
    }
    
    // MARK: - Gestures optimizados
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded { _ in
                withAnimation(.interactiveSpring(
                    response: 0.25,
                    dampingFraction: 0.8,
                    blendDuration: 0.2
                )) {
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
    
    // MARK: - Subviews
    private func posterImage(width: CGFloat) -> some View {
        CachedAsyncImage(url: URL(string: serie.cover ?? "")) { phase in
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
                    placeholderView(width: width)
                @unknown default:
                    EmptyView()
                }
            }
            .transition(.opacity)
            .frame(width: width)
            .clipped()
            .overlay(gradientOverlay)
            .overlay(ratingBadge)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(strokeOverlay)
        .matchedGeometryEffect(id: "\(serie.id)-cover", in: namespace)
    }
    
    private var detailsOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(serie.formattedTitle)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: textGlowRadius, x: 0, y: 2)
                .matchedGeometryEffect(id: "\(serie.id)-title", in: namespace)
            
            HStack {
                yearAndQualityView
                Spacer()
                
                if isDetailsExpanded {
                    detailButton
                } else {
                    enhancedRatingView
                }
            }
            .matchedGeometryEffect(id: "\(serie.id)-details", in: namespace)
            
            if isDetailsExpanded {
                expandedDetails
            }
        }
    }
    
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !serie.genre.isEmpty {
                detailItemWithIcon("film", text: serie.genre)
            }
            
            if !serie.episodeRunTime.isEmpty {
                detailItemWithIcon("clock", text: serie.episodeRunTime)
            }
            
            if !serie.cast.isEmpty {
                detailItemWithIcon("person.2", text: serie.cast)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var detailButton: some View {
        Button(action: {
            onViewDetails()
        }) {
            Text("View Details")
                .font(.system(size: detailsFontSize, weight: .semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.blue.opacity(0.9))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Componentes reutilizables
    private func detailItemWithIcon(_ icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: detailsFontSize))
                .frame(width: 20)
                .foregroundColor(.white.opacity(0.8))
            
            Text(text)
                .font(.system(size: detailsFontSize, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)
        }
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .clear,
                .black.opacity(0.1),
                .black.opacity(0.3),
                .black.opacity(0.6)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .opacity(isDetailsExpanded ? 0 : 0.8)
        .animation(.easeInOut(duration: 0.3), value: isDetailsExpanded)
    }
    
    private var ratingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
                .font(.system(size: smallDetailsFontSize))
            Text(serie.rating)
                .font(.system(size: smallDetailsFontSize))
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
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
    
    private var gradientBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.7),
                        Color.purple.opacity(0.8),
                        Color.pink.opacity(0.7)
                    ]),
                    center: .center,
                    angle: .degrees(animateGradient ? 360 : 0)
                ),
                lineWidth: isTapped ? 1.5 : 0
            )
            .blur(radius: isTapped ? 2 : 0)
            .animation(
                .linear(duration: 2)
                .delay(0.1)
                .repeatForever(autoreverses: false),
                value: animateGradient
            )
    }
    
    // MARK: - Métodos de interacción
    private func handleTap() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isTapped = true
        }
        
        if !animateGradient {
            withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                animateGradient = true
            }
        }
        
        withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.02
        }
        
        resetTap(after: 0.25)
    }
    
    private func resetTap(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isTapped = false
                pulseScale = 1.0
            }
        }
    }
    
    private func placeholderView(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "tv")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width * 0.35)
            
            Text(serie.name)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal)
        }
        .frame(width: width)
        .frame(height: width / posterAspectRatio)
        .background(Color.gray.opacity(0.1))
        .foregroundColor(.secondary)
    }
    
    private var strokeOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                Color.secondary.opacity(isTapped ? 0.2 : 0.1),
                lineWidth: isTapped ? 1.5 : 1
            )
            .animation(.easeInOut(duration: 0.2), value: isTapped)
    }
    
    private var tapEffect: some View {
        Circle()
            .fill(Color.white.opacity(0.3))
            .scaleEffect(isTapped ? 1.5 : 0)
            .opacity(isTapped ? 0 : 0.5)
            .animation(.easeOut(duration: 0.5), value: isTapped)
            .blendMode(.screen)
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
    
    private var yearAndQualityView: some View {
        HStack(spacing: 6) {
            if let year = serie.year {
                Text(year)
                    .font(.system(size: detailsFontSize, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color(.darkGray).opacity(0.5))
                            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                    )
            }
            
            if let quality = serie.quality {
                Text(quality)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(4)
            }
        }
    }
    
    private var enhancedRatingView: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
                .font(.system(size: smallDetailsFontSize))
            Text(serie.rating)
                .font(.system(size: detailsFontSize, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(.background)
        )
    }
    
    // MARK: - Nuevos métodos de gestión
    private func handleDetailsExpansionChange(_ expanded: Bool) {
        #if os(iOS)
        if expanded {
            feedbackGenerator.impactOccurred(intensity: 0.7)
        }
        #endif
        
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
            isTapped = expanded
        }
    }
    
    private func handleTapFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        #endif
    }
}

// MARK: - Transiciones personalizadas (se mantienen)
extension AnyTransition {
    static var customScaleTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: CustomScaleModifier(scale: 0.95, opacity: 0, offset: CGSize(width: 0, height: 20)),
                identity: CustomScaleModifier(scale: 1, opacity: 1, offset: .zero)
            ),
            removal: .modifier(
                active: CustomScaleModifier(scale: 0.9, opacity: 0, offset: CGSize(width: 0, height: -10)),
                identity: CustomScaleModifier(scale: 1, opacity: 1, offset: .zero)
            )
        )
    }
}
// MARK: - Preview

struct SerieCardViewiOS_Previews: PreviewProvider {
    @Namespace static var previewNamespace
    
    static var previews: some View {
        Group {
            SerieCardViewiOS(
                serie: sampleSeries[0],
                namespace: previewNamespace,
                onViewDetails: {
                    print("Ver detalles de Stranger Things")
                }
            )
            .frame(width: 180)
            .previewDisplayName("Normal Size")
            
            SerieCardViewiOS(
                serie: sampleSeries[1],
                namespace: previewNamespace
            )
            .frame(width: 120)
            .previewDisplayName("Compact Size")
            
            gridPreview
        }
        .previewLayout(.sizeThatFits)
        .background(.background)
    }
    
    private static var gridPreview: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)
        ], spacing: 12) {
            ForEach(sampleSeries, id: \.seriesId) { serie in
                SerieCardViewiOS(
                    serie: serie,
                    namespace: previewNamespace,
                    onViewDetails: {
                        print("Ver detalles de \(serie.name)")
                    }
                )
            }
        }
        .padding()
        .frame(maxWidth: 600)
        .previewDisplayName("Grid Preview")
    }
    
    private static let sampleSeries = [
        Serie(
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
        ),
        Serie(
            number: 1,
            name: "Breaking Bad (2008)",
            seriesId: 102,
            cover:"https://m.media-amazon.com/images/M/MV5BMzU5ZGYzNmQtMTdhYy00OGRiLTg0NmQtYjVjNzliZTg1ZGE4XkEyXkFqcGc@._V1_.jpg",
            plot: "A chemistry teacher turned methamphetamine producer.",
            cast: "Bryan Cranston, Aaron Paul",
            director: "Vince Gilligan",
            genre: "Crime, Drama",
            releaseDate: "2008-01-20",
            lastModified: "2024-10-30",
            rating: "9.5",
            rating5Based: 4.75,
            backdropPath: [],
            youtubeTrailer: nil,
            episodeRunTime: "47 min",
            categoryId: "1"
        )
    ]
}
