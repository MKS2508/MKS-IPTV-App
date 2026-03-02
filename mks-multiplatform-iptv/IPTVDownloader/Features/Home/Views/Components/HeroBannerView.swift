//
//  HeroBannerView.swift
//  mks-multiplatform-iptv
//
//  Full-width hero banner for the Home screen
//  Shows a random top-rated movie/serie with backdrop, gradient, and action buttons
//

import SwiftUI

struct HeroBannerView: View {
    let item: any LibraryItem
    @Binding var selectedView: String?

    #if os(macOS)
    private let bannerHeight: CGFloat = 400
    #else
    private let bannerHeight: CGFloat = 450
    #endif

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image with CachedAsyncImage
            if let imageURL = item.coverImage, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: bannerHeight)
                            .clipped()
                            .transition(.opacity)
                    case .failure:
                        fallbackBanner
                    case .empty:
                        SkeletonLoader()
                            .frame(maxWidth: .infinity)
                            .frame(height: bannerHeight)
                    @unknown default:
                        fallbackBanner
                    }
                }
            } else {
                fallbackBanner
            }

            // Gradient overlay
            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.3),
                    Color.black.opacity(0.7),
                    Color.black.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay
            VStack(alignment: .leading, spacing: 12) {
                // Type badge (glass capsule)
                Text(item.libraryType == .movie ? "MOVIE" : "SERIES")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .adaptiveGlass(in: Capsule())

                // Title
                Text(item.cleanTitle)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                // Rating (glass capsule)
                if item.displayRating5Based > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(format: "%.1f", item.displayRating5Based))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .adaptiveGlass(in: Capsule())
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        navigateToItem()
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.appGlassProminent)

                    Button {
                        navigateToItem()
                    } label: {
                        Label("More Info", systemImage: "info.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.appGlass)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(height: bannerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    private var fallbackBanner: some View {
        LinearGradient(
            colors: [
                AppColors.accentDark,
                AppColors.background
            ],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
        .frame(height: bannerHeight)
    }

    private func navigateToItem() {
        switch item.libraryType {
        case .movie:
            selectedView = NavigationDestination.movies.rawValue
        case .series:
            selectedView = NavigationDestination.series.rawValue
        }
    }
}
