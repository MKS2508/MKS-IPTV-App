//
//  MovieCardViewiOS.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 18/3/25.
//
import SwiftUI

struct MovieCardViewiOS: View {
    let movie: Movie
    @State private var isTapped = false
    @State private var isAppearing = false
    @State private var isDetailsExpanded = false
    @State private var animateGradient = false
    @State private var pulseScale: CGFloat = 1.0
    var namespace: Namespace.ID
    var onViewDetails: () -> Void
    
    init(movie: Movie, namespace: Namespace.ID, onViewDetails: @escaping () -> Void = {}) {
        self.movie = movie
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
                posterImage(width: geometry.size.width)
                    .frame(width: geometry.size.width)
                
                detailsOverlay
                    .padding(detailsPadding)
                    .frame(width: geometry.size.width)
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.4), .black.opacity(0.85)],
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
            .simultaneousGesture(DragGesture().onChanged { _ in })
        }
        .aspectRatio(posterAspectRatio, contentMode: .fit)
        .frame(minWidth: minPosterWidth)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.95)),
            removal: .opacity
        ))
        .onAppear(perform: handleAppear)
        .onChange(of: isDetailsExpanded) { handleDetailsExpansionChange($0) }
    }
    
    // MARK: - Gestures actualizados
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
                withAnimation(.easeInOut(duration: 0.15)) { isTapped = true }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isTapped = false }
            }
    }
    
    // MARK: - Subviews
    private func posterImage(width: CGFloat) -> some View {
        CachedAsyncImage(url: URL(string: movie.streamIcon ?? "")) { phase in
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
        .matchedGeometryEffect(id: "\(movie.id)-cover", in: namespace)
    }
    
    private var detailsOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(movie.formattedTitle)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: textGlowRadius, x: 0, y: 2)
                .matchedGeometryEffect(id: "\(movie.id)-title", in: namespace)
            
            HStack {
                yearAndQualityView
                Spacer()
                
                if isDetailsExpanded {
                    detailButton
                } else {
                    enhancedRatingView
                }
            }
            .matchedGeometryEffect(id: "\(movie.id)-details", in: namespace)
            
            if isDetailsExpanded {
                expandedDetails
            }
        }
    }
    
    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let added = movie.added {
                detailItemWithIcon("calendar", text: "Added: \(added)")
            }
            
            if let runtime = movie.containerExtension {
                detailItemWithIcon("clock", text: "Format: \(runtime.uppercased())")
            }
            
            if let quality = movie.quality {
                detailItemWithIcon("hd", text: "Quality: \(quality)")
            }
            
            if movie.isAdult == "1" {
                detailItemWithIcon("exclamationmark.triangle", text: "Adult Content")
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    // MARK: - Componentes reutilizables
    private var detailButton: some View {
        Button(action: onViewDetails) {
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
            colors: [.clear, .black.opacity(0.1), .black.opacity(0.3), .black.opacity(0.6)],
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
            Text(movieRating)
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
                    colors: [.blue.opacity(0.7), .purple.opacity(0.8), .pink.opacity(0.7)],
                    center: .center,
                    angle: .degrees(animateGradient ? 360 : 0)
                ),
                lineWidth: isTapped ? 1.5 : 0
            )
            .blur(radius: isTapped ? 2 : 0)
            .animation(
                .linear(duration: 2).delay(0.1).repeatForever(autoreverses: false),
                value: animateGradient
            )
    }
    
    // MARK: - Métodos de interacción
    private func handleDetailsExpansionChange(_ expanded: Bool) {
        #if os(iOS)
        if expanded { feedbackGenerator.impactOccurred(intensity: 0.7) }
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
            Image(systemName: "film")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width * 0.35)
            
            Text(movie.name)
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
    
    private var movieRating: String {
        if let rating5Based = movie.rating5Based {
            return String(format: "%.1f", rating5Based)
        }
        return movie.rating ?? "N/A"
    }
    
    private var yearAndQualityView: some View {
        HStack(spacing: 6) {
            if let year = movie.year {
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
            
            if let quality = movie.quality {
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
            Text(movieRating)
                .font(.system(size: detailsFontSize, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(.background))
    }
    
    private func handleAppear() {
        #if os(iOS)
        feedbackGenerator.prepare()
        #endif
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) { isAppearing = true }
        }
    }
}
// MARK: - Preview
struct MovieCardViewiOS_Previews: PreviewProvider {
    @Namespace static var previewNamespace
    
    static var previews: some View {
        Group {
            MovieCardViewiOS(
                movie: sampleMovies[0],
                namespace: previewNamespace
            )
            .frame(width: 180)
            .previewDisplayName("Normal Size")
            
            MovieCardViewiOS(
                movie: sampleMovies[1],
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
            ForEach(sampleMovies, id: \.streamId) { movie in
                MovieCardViewiOS(movie: movie, namespace: previewNamespace)
            }
        }
        .padding()
        .frame(maxWidth: 600)
        .previewDisplayName("Grid Preview")
    }
    
    private static let sampleMovies = [
        Movie(
            name: "The Matrix (1999) 4K",
            streamType: "movie",
            streamId: 101,
            streamIcon: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg",
            rating: "8.7",
            rating5Based: 4.35,
            added: "2024-01-01",
            isAdult: "0",
            categoryId: "1",
            containerExtension: "mp4",
            customSid: nil,
            directSource: nil
        ),
        Movie(
            name: "Interstellar (2014) HD",
            streamType: "movie",
            streamId: 102,
            streamIcon: "https://image.tmdb.org/t/p/w600_and_h900_bestv2/gEU2QniE6E77NI6lCU6MxlNBvIx.jpg",
            rating: "8.6",
            rating5Based: 4.3,
            added: "2024-02-15",
            isAdult: "0",
            categoryId: "1",
            containerExtension: "mp4",
            customSid: nil,
            directSource: nil
        )
    ]
}
