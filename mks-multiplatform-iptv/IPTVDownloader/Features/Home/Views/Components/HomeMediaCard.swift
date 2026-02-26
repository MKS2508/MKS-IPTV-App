//
//  HomeMediaCard.swift
//  mks-multiplatform-iptv
//
//  Portrait card for movies/series in horizontal carousels
//  Shows poster image with Liquid Glass effects, skeleton loader,
//  glass badges, press animation, and haptic feedback
//

import SwiftUI

struct HomeMediaCard: View {
    let item: any LibraryItem
    @Binding var selectedView: String?

    @State private var isPressed = false

    private let cardWidth: CGFloat = 140
    private let cardHeight: CGFloat = 210

    var body: some View {
        Button {
            triggerHaptic()
            navigateToItem()
        } label: {
            ZStack(alignment: .bottom) {
                // Poster image with CachedAsyncImage
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

                // Title + rating overlay
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()

                    Text(item.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if item.displayRating5Based > 0 {
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
                        .adaptiveGlass(in: Capsule())
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Type indicator badge (glass circle)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: item.libraryType == .movie ? "film" : "tv")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(5)
                            .adaptiveGlass(in: Circle())
                    }
                    Spacer()
                }
                .padding(6)

                // Subtle stroke for definition
                RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
            .adaptiveGlassInteractive(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
            .fill(AppColors.surface)
            .frame(width: cardWidth, height: cardHeight)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: item.libraryType == .movie ? "film" : "tv")
                        .font(.title3)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(item.name)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
    }

    private func navigateToItem() {
        switch item.libraryType {
        case .movie:
            selectedView = NavigationDestination.movies.rawValue
        case .series:
            selectedView = NavigationDestination.series.rawValue
        }
    }

    private func triggerHaptic() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}
