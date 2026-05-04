import IPTVCore
import SwiftUI
#if canImport(UIKit)
import UIKit
import IPTVCore
import IPTVCore
#endif

struct SerieCardView: View {
    let serie: Serie
    @State private var isHovered = false
    @State private var isAppearing = false // For initial appearance animation
    @State private var shineOffset: CGFloat = -200 // For shine effect
    @State private var gradientRotation: Double = 0 // For rotating gradient animation
    @State private var pulseScale: CGFloat = 1.0 // For subtle pulsing effect
    var namespace: Namespace.ID
    
    // Constants for adaptive dimensions - matching MovieCardView
    private let posterAspectRatio: CGFloat = 2/3
    private let cornerRadius: CGFloat = 12
    private let minPosterWidth: CGFloat = 120
    
    // Font sizes - matching MovieCardView
    private let titleFontSize: CGFloat = 15
    private let detailsFontSize: CGFloat = 13
    private let smallDetailsFontSize: CGFloat = 11

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Cover image (always visible)
                coverImage(width: geometry.size.width)
                    .frame(width: geometry.size.width)
                
                // Enhanced serie details overlay
                enhancedSerieDetails
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: geometry.size.width)
                    .background(
                        Rectangle()
                            .fill(Color(.darkGray).opacity(0.9))
                            .blur(radius: 0.5)
                    )
                    // Improved animation for details appearance
                    .opacity(isHovered ? 1 : 0)
                    .offset(y: isHovered ? 0 : 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.width / posterAspectRatio)
            .background(.background)
            .cornerRadius(cornerRadius)
            // Animated moving gradient glow effect on hover
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.7),
                                Color.purple.opacity(0.8),
                                Color.pink.opacity(0.7),
                                Color.orange.opacity(0.6),
                                Color.blue.opacity(0.7)
                            ]),
                            center: .center,
                            angle: .degrees(gradientRotation)
                        ),
                        lineWidth: isHovered ? 2.5 : 0
                    )
                    .scaleEffect(pulseScale)
                    .blur(radius: isHovered ? 3 : 0)
            )
            // Improved shadow animation
            .shadow(
                color: .black.opacity(isHovered ? 0.25 : 0.15),
                radius: isHovered ? 12 : 8,
                x: 0,
                y: isHovered ? 6 : 4
            )
            // Improved hover animation with multiple properties
            .scaleEffect(isHovered ? 1.03 : 1)
            .brightness(isHovered ? 0.03 : 0)
            // Staggered animations for different properties
            .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1), value: isHovered)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                
                // Trigger shine effect when hovering starts
                if hovering {
                    // Start the gradient rotation animation
                    withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                        gradientRotation = 360
                    }
                    
                    // Start the pulse animation
                    withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.03
                    }
                    
                    // Shine effect animation
                    withAnimation(Animation.easeInOut(duration: 1.2)) {
                        shineOffset = geometry.size.width + 200
                    }
                } else {
                    // Reset animations when not hovering
                    withAnimation {
                        gradientRotation = 0
                        pulseScale = 1.0
                    }
                    shineOffset = -200
                }
            }
            // Initial appearance animation
            .opacity(isAppearing ? 1 : 0)
            .offset(y: isAppearing ? 0 : 20)
            .scaleEffect(isAppearing ? 1 : 0.97)
        }
        .aspectRatio(posterAspectRatio, contentMode: .fit)
        .frame(minWidth: minPosterWidth)
        // Improved transition with timing curve
        .transition(
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
        )
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
    }

    // Enhanced serie details with improved typography and focus on title and year
    private var enhancedSerieDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Enhanced title with better typography
            Text(serie.formattedTitle)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .foregroundColor(.primary)
                .matchedGeometryEffect(id: "\(serie.id)-title", in: namespace)
            
            // Badges row: year, quality, codec, HDR
            HStack(spacing: 6) {
                // Year badge
                if let year = serie.year {
                    Text(year)
                        .font(.system(size: smallDetailsFontSize, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.darkGray).opacity(0.5))
                                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                        )
                }
                
                // Quality badge
                if let quality = serie.quality {
                    Text(quality)
                        .font(.system(size: smallDetailsFontSize, weight: .medium))
                        .foregroundColor(qualityColor(for: quality))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.darkGray).opacity(0.5))
                        )
                }
                
                // Codec badge
                if let codec = serie.codec {
                    Text(codec)
                        .font(.system(size: smallDetailsFontSize, weight: .medium))
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.darkGray).opacity(0.5))
                        )
                }
                
                // HDR badge
                if serie.isHDR {
                    Text("HDR")
                        .font(.system(size: smallDetailsFontSize, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.darkGray).opacity(0.5))
                        )
                }
                
                Spacer()
                
                // Enhanced rating view
                enhancedRatingView
            }
            .matchedGeometryEffect(id: "\(serie.id)-details", in: namespace)
        }
    }
    
    private func qualityColor(for quality: String) -> Color {
        let q = quality.lowercased()
        if q.contains("4k") || q.contains("2160") { return .purple }
        if q.contains("1080") { return .blue }
        if q.contains("720") { return .green }
        return .gray
    }
    
    private func coverImage(width: CGFloat) -> some View {
        CachedAsyncImage(url: URL(string: serie.cover ?? "")) { phase in
            switch phase {
            case .empty:
                SkeletonLoader()
                    .aspectRatio(posterAspectRatio, contentMode: .fill)
            case .success(let image):
                ZStack {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width)
                        .clipped()
                        .overlay(
                            // Improved gradient on poster (visible when not hovered)
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
                            // Smoother fade animation for gradient
                                .opacity(isHovered ? 0 : 0.8)
                                .animation(.easeInOut(duration: 0.3), value: isHovered)
                                .overlay(
                                    // Rating badge with animated entrance
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
                                    // Animated badge with scale and opacity
                                        .opacity(isHovered ? 0 : 1)
                                        .scaleEffect(isHovered ? 0.9 : 1)
                                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                )
                        )
                    
                    // Enhanced shine effect overlay with better animation
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .white.opacity(0.1),
                                    .white.opacity(0.3),
                                    .white.opacity(0.1),
                                    .clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(35))
                        .offset(x: shineOffset)
                        .frame(width: 60)
                        .blendMode(.screen)
                        .opacity(isHovered ? 1 : 0)
                }
            case .failure:
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
            @unknown default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    Color.secondary.opacity(isHovered ? 0.2 : 0.1),
                    lineWidth: isHovered ? 1.5 : 1
                )
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        )
        .matchedGeometryEffect(id: "\(serie.id)-poster", in: namespace)
    }

    // Enhanced rating view with improved visual design - matching MovieCardView
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
}


struct SerieCardView_Previews: PreviewProvider {
    @Namespace static var previewNamespace

    static var previews: some View {
        Group {
            SerieCardView(serie: Serie(
                number: 1,
                name: "Stranger Things (2016)",
                seriesId: 101,
                cover: "https://image.tmdb.org//t//p//w600_and_h900_bestv2//x48pAd8p6vU6UVDYLhhfHiKjRUY.jpg",
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
            ), namespace: previewNamespace)
            .frame(width: 300, height: 400)
            .padding()

            SerieCardView(serie: Serie(
                number: 1,
                name: "Breaking Bad (2008)",
                seriesId: 102,
                cover: nil,
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
            ), namespace: previewNamespace)
            .frame(width: 250)
            .padding()
        }
        .previewLayout(.sizeThatFits)
        .background(.background)
    }
}
