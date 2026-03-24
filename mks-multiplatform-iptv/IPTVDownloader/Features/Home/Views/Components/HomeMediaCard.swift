//
//  HomeMediaCard.swift
//  mks-multiplatform-iptv
//
//  Apple TV-style portrait card for movies/series in horizontal carousels.
//  Features:
//  - Native Liquid Glass effects (iOS 26+)
//  - Smooth press animations
//  - Glass badges for metadata
//  - Haptic feedback
//

import SwiftUI

// MARK: - Home Media Card

/// Apple TV-style portrait card with native Liquid Glass styling.
///
/// **Design Features:**
/// - Portrait poster image with smooth loading
/// - Glass badges for year, quality, HDR
/// - Interactive glass effect on tap
/// - Focus scaling for tvOS
///
struct HomeMediaCard: View {
    let item: any LibraryItem
    @Binding var selectedView: String?

    @State private var isPressed = false
    @State private var isFocused = false

    // MARK: - Platform-Specific Sizing

    #if os(tvOS)
    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 270
    #elseif os(macOS)
    private let cardWidth: CGFloat = 150
    private let cardHeight: CGFloat = 225
    #else
    private let cardWidth: CGFloat = 140
    private let cardHeight: CGFloat = 210
    #endif

    // MARK: - Body

    var body: some View {
        Button {
            triggerHaptic()
            navigateToItem()
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .scaleEffect(pressScale)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.cleanTitle)
        .accessibilityHint("Double tap to view details")
    }

    private var pressScale: CGFloat {
        if isPressed {
            return 0.97
        } else if isFocused {
            return 1.03
        }
        return 1.0
    }

    // MARK: - Card Content

    private var cardContent: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 1: Poster image
            posterLayer

            // Layer 2: Gradient overlay for text readability
            gradientOverlay

            // Layer 3: Content overlay
            contentOverlay

            // Layer 4: Type indicator (top-right)
            typeIndicator

            // Layer 5: Subtle border
            borderOverlay
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
        .cardGlassEffect()
    }

    // MARK: - Poster Layer

    @ViewBuilder
    private var posterLayer: some View {
        if let imageURL = item.coverImage, let url = URL(string: imageURL) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .transition(.opacity)
                case .failure:
                    posterPlaceholder
                case .empty:
                    SkeletonLoader()
                        .frame(width: cardWidth, height: cardHeight)
                @unknown default:
                    posterPlaceholder
                }
            }
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
            .fill(Color.white.opacity(0.08))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: item.mediaType == .movie ? "film" : "tv")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.3))
                    Text(item.cleanTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
    }

    // MARK: - Gradient Overlay

    private var gradientOverlay: some View {
        VStack {
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.6), location: 0.5),
                    .init(color: .black.opacity(0.9), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: cardHeight * 0.5)
        }
    }

    // MARK: - Content Overlay

    private var contentOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()

            // Title
            Text(item.cleanTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            // Metadata badges
            HStack(spacing: 4) {
                yearBadge
                qualityBadge
                hdrBadge
            }

            // Rating
            if item.displayRating5Based > 0 {
                ratingBadge
            }
        }
        .padding(10)
    }

    // MARK: - Badges

    @ViewBuilder
    private var yearBadge: some View {
        if let year = item.year {
            Text(year)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .glassBadge()
        }
    }

    @ViewBuilder
    private var qualityBadge: some View {
        if let quality = item.quality {
            Text(quality)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(qualityColor(for: quality))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .glassBadge()
        }
    }

    @ViewBuilder
    private var hdrBadge: some View {
        if item.isHDR {
            Text("HDR")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .glassBadge()
        }
    }

    @ViewBuilder
    private var ratingBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
                .foregroundStyle(.yellow)
            Text(String(format: "%.1f", item.displayRating5Based))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .glassBadge()
    }

    // MARK: - Type Indicator

    private var typeIndicator: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: item.mediaType == .movie ? "film" : "tv")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .glassBadge()
            }
            Spacer()
        }
        .padding(8)
    }

    // MARK: - Border Overlay

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
    }

    // MARK: - Actions

    private func navigateToItem() {
        switch item.mediaType {
        case .movie:
            selectedView = NavigationDestination.movies.rawValue
        case .series:
            selectedView = NavigationDestination.series.rawValue
        }
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func qualityColor(for quality: String) -> Color {
        let q = quality.lowercased()
        if q.contains("4k") || q.contains("2160") { return .purple }
        if q.contains("1080") { return .cyan }
        if q.contains("720") { return .green }
        return .white.opacity(0.8)
    }
}

// MARK: - Glass Badge Extension

private extension View {
    @ViewBuilder
    func glassBadge() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular.tint(.black.opacity(0.2)), in: Capsule())
        } else {
            self.background(.ultraThinMaterial.opacity(0.8), in: Capsule())
        }
    }
}

// MARK: - Card Glass Effect Extension

private extension View {
    @ViewBuilder
    func cardGlassEffect() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular.tint(.black.opacity(0.1)).interactive(), in: .rect(cornerRadius: AppGlass.cornerRadiusSmall))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
        }
    }
}

// MARK: - Previews

#Preview("Media Cards") {
    HStack(spacing: 16) {
        HomeMediaCard(
            item: Movie(
                name: "Dune: Part Two",
                streamType: "movie",
                streamId: 1,
                tmdbId: nil,
                streamIcon: "https://image.tmdb.org/t/p/w500/8b8R8l88Qje9dn9OE8PY05Nxl1X.jpg",
                rating: "8.5",
                rating5Based: 4.25,
                added: nil,
                isAdult: "0",
                categoryId: "1",
                containerExtension: "mp4",
                customSid: nil,
                directSource: nil
            ),
            selectedView: .constant(nil)
        )

        HomeMediaCard(
            item: Movie(
                name: "Oppenheimer",
                streamType: "movie",
                streamId: 2,
                tmdbId: nil,
                streamIcon: nil,
                rating: "9.0",
                rating5Based: 4.5,
                added: nil,
                isAdult: "0",
                categoryId: "1",
                containerExtension: "mp4",
                customSid: nil,
                directSource: nil
            ),
            selectedView: .constant(nil)
        )
    }
    .padding()
    .background(Color.black)
}
