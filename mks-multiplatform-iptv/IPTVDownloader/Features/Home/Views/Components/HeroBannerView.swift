//
//  HeroBannerView.swift
//  mks-multiplatform-iptv
//
//  Full-width hero banner for the Home screen
//  Shows a random top-rated movie/serie with backdrop, gradient, and action buttons
//  Enriched with TMDB metadata (backdrop HD, plot, genre, runtime) via EnrichedMediaStore
//

import SwiftUI

struct HeroBannerView: View {
    let item: any LibraryItem
    @Binding var selectedView: String?

    @State private var enrichedMetadata: MetadataResult?

    #if os(macOS)
    private let bannerHeight: CGFloat = 400
    #else
    private let bannerHeight: CGFloat = 450
    #endif

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop image — prefer enriched HD backdrop, fallback to coverImage
            backdropImage

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
                Text(item.mediaType == .movie ? "MOVIE" : "SERIES")
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

                // Enriched subtitle: year, genre, runtime
                enrichedSubtitle

                // Rating (glass capsule)
                ratingBadge

                // Plot preview (from enriched metadata)
                if let plot = enrichedMetadata?.plot, !plot.isEmpty {
                    Text(plot)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                        .transition(.opacity)
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
        .task {
            enrichedMetadata = await EnrichedMediaStore.shared
                .getEnrichedMetadata(for: item, tmdbId: item.tmdbIdInt)
        }
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdropImage: some View {
        let backdropURLString = enrichedMetadata?.backdropURL ?? item.coverImage

        if let urlString = backdropURLString, let url = URL(string: urlString) {
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
    }

    // MARK: - Enriched Subtitle

    @ViewBuilder
    private var enrichedSubtitle: some View {
        let parts = subtitleParts
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("\u{2022}")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Text(part)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .adaptiveGlass(in: Capsule())
            .transition(.opacity)
        }
    }

    private var subtitleParts: [String] {
        var parts: [String] = []

        // Year: enriched first, then parsed from title
        if let year = enrichedMetadata?.year {
            parts.append(String(year))
        } else if let year = item.year {
            parts.append(year)
        }

        // Genre: first two from enriched metadata
        if let genres = enrichedMetadata?.genre, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        }

        // Runtime
        if let runtime = enrichedMetadata?.runtimeMinutes, runtime > 0 {
            let hours = runtime / 60
            let mins = runtime % 60
            if hours > 0 {
                parts.append("\(hours)h \(mins)m")
            } else {
                parts.append("\(mins)m")
            }
        }

        return parts
    }

    // MARK: - Rating Badge

    @ViewBuilder
    private var ratingBadge: some View {
        // Prefer enriched TMDB rating (0-10 scale), fallback to IPTV rating (0-5)
        let ratingValue: Double? = {
            if let tmdbRating = enrichedMetadata?.rating, tmdbRating > 0 {
                return tmdbRating
            }
            if item.displayRating5Based > 0 {
                return item.displayRating5Based * 2 // Normalize to 0-10
            }
            return nil
        }()

        if let rating = ratingValue, rating > 0 {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text(String(format: "%.1f", rating))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .adaptiveGlass(in: Capsule())
        }
    }

    // MARK: - Fallback & Navigation

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
        switch item.mediaType {
        case .movie:
            selectedView = NavigationDestination.movies.rawValue
        case .series:
            selectedView = NavigationDestination.series.rawValue
        }
    }
}
