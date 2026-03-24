//
//  HeroBannerView.swift
//  mks-multiplatform-iptv
//
//  Full-width hero banner for the Home screen - Apple TV style
//  Features:
//  - Dramatic backdrop with cinematic parallax-like depth
//  - Native Liquid Glass for badges and buttons (iOS 26+)
//  - Smooth animations and haptic feedback
//  - Enriched with TMDB metadata
//  - SAFE async metadata loading (prevents mismatch bugs)
//

import SwiftUI

// MARK: - Hero Banner View

/// Apple TV-style hero banner with cinematic presentation.
///
/// **Design Features:**
/// - Full-bleed backdrop with layered gradient
/// - Native Liquid Glass badges and buttons (iOS 26+)
/// - Animated content entrance
/// - Focus-aware scaling for tvOS
/// - Safe async metadata loading to prevent content mismatch
///
struct HeroBannerView: View {
    let item: any LibraryItem
    @Binding var selectedView: String?

    @State private var enrichedMetadata: MetadataResult?
    @State private var isAppearing = false
    @State private var isPressed = false
    @State private var loadedItemStreamId: Int? = nil  // Track which item's metadata was loaded

    // MARK: - Platform-Specific Sizing

    #if os(tvOS)
    private let bannerHeight: CGFloat = 720
    private let titleFont: Font = .largeTitle.weight(.bold)
    private let bodyFont: Font = .body
    #elseif os(macOS)
    private let bannerHeight: CGFloat = 500
    private let titleFont: Font = .title.weight(.bold)
    private let bodyFont: Font = .subheadline
    #else
    private let bannerHeight: CGFloat = 520
    private let titleFont: Font = .title.weight(.bold)
    private let bodyFont: Font = .subheadline
    #endif

    // MARK: - Safe Computed Properties

    /// Unique identifier for the current item (used for safe async loading)
    private var currentItemStreamId: Int {
        item.streamId
    }

    /// Whether the loaded metadata matches the current item
    private var metadataMatchesCurrentItem: Bool {
        loadedItemStreamId == currentItemStreamId
    }

    /// The backdrop URL to use - only use enriched if it matches current item
    private var safeBackdropURL: String? {
        // Priority: enriched metadata (if matched) > item cover image
        if metadataMatchesCurrentItem, let enriched = enrichedMetadata?.backdropURL, !enriched.isEmpty {
            return enriched
        }
        return item.coverImage
    }

    /// The title to display - ALWAYS from the item, never from enriched metadata
    private var safeTitle: String {
        item.cleanTitle
    }

    /// The plot to display - only use enriched if it matches current item
    private var safePlot: String? {
        guard metadataMatchesCurrentItem,
              let plot = enrichedMetadata?.plot,
              !plot.isEmpty else { return nil }
        return plot
    }

    /// The rating to display - only use enriched if it matches current item
    private var safeRating: Double? {
        if metadataMatchesCurrentItem, let tmdbRating = enrichedMetadata?.rating, tmdbRating > 0 {
            return tmdbRating
        }
        if item.displayRating5Based > 0 {
            return item.displayRating5Based * 2
        }
        return nil
    }

    /// Year from enriched or item
    private var safeYear: String? {
        if metadataMatchesCurrentItem, let year = enrichedMetadata?.year {
            return String(year)
        }
        return item.year
    }

    /// Genres from enriched metadata
    private var safeGenres: [String]? {
        guard metadataMatchesCurrentItem,
              let genres = enrichedMetadata?.genre,
              !genres.isEmpty else { return nil }
        return Array(genres.prefix(2))
    }

    /// Runtime from enriched metadata
    private var safeRuntime: String? {
        guard metadataMatchesCurrentItem,
              let runtime = enrichedMetadata?.runtimeMinutes,
              runtime > 0 else { return nil }
        let hours = runtime / 60
        let mins = runtime % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Layer 1: Backdrop image
            backdropLayer

            // Layer 2: Cinematic gradient overlay
            gradientOverlay

            // Layer 3: Vignette effect
            vignetteOverlay

            // Layer 4: Content
            contentLayer
                .padding(24)
        }
        .frame(height: bannerHeight)
        .clipShape(RoundedRectangle(cornerRadius: bannerCornerRadius))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .scaleEffect(isPressed ? 0.995 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                isAppearing = true
            }
        }
        // SAFE: Use task with id to track which item we're loading for
        .task(id: currentItemStreamId) {
            let streamId = currentItemStreamId

            // Small delay to prevent rapid-fire loading if items change quickly
            try? await Task.sleep(for: .milliseconds(50))

            // Load metadata
            let metadata = await EnrichedMediaStore.shared
                .getEnrichedMetadata(for: item, tmdbId: item.tmdbIdInt)

            // CRITICAL: Only update if this is still the same item
            // This prevents the bug where backdrop/title don't match
            if streamId == currentItemStreamId {
                withAnimation(.easeInOut(duration: 0.3)) {
                    enrichedMetadata = metadata
                    loadedItemStreamId = streamId
                }
            }
        }
        // Reset when item changes
        .onChange(of: currentItemStreamId) { oldId, newId in
            if oldId != newId {
                // Clear stale metadata immediately to prevent flash
                enrichedMetadata = nil
                loadedItemStreamId = nil
            }
        }
    }

    private var bannerCornerRadius: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 0
        #endif
    }

    // MARK: - Backdrop Layer

    @ViewBuilder
    private var backdropLayer: some View {
        if let urlString = safeBackdropURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: bannerHeight)
                        .clipped()
                        .opacity(isAppearing ? 1 : 0.8)
                        .animation(.easeInOut(duration: 0.3), value: isAppearing)
                case .failure, .empty:
                    fallbackBackdrop
                @unknown default:
                    fallbackBackdrop
                }
            }
        } else {
            fallbackBackdrop
        }
    }

    private var fallbackBackdrop: some View {
        LinearGradient(
            colors: [
                AppColors.accent.opacity(0.6),
                AppColors.accentDark,
                AppColors.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: bannerHeight)
    }

    // MARK: - Gradient Overlay

    private var gradientOverlay: some View {
        VStack {
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.2), location: 0.3),
                    .init(color: .black.opacity(0.5), location: 0.6),
                    .init(color: .black.opacity(0.85), location: 0.85),
                    .init(color: .black.opacity(0.98), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: bannerHeight * 0.7)
        }
    }

    // MARK: - Vignette Overlay

    private var vignetteOverlay: some View {
        LinearGradient(
            colors: [
                .black.opacity(0.3),
                .clear,
                .clear,
                .black.opacity(0.2)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Content Layer

    private var contentLayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Type badge
            typeBadge
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 10)

            // Title (ALWAYS from item, never from enriched)
            Text(safeTitle)
                .font(titleFont)
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 15)

            // Metadata row
            metadataRow
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 20)

            // Plot preview (only if we have matching enriched data)
            if let plot = safePlot {
                Text(plot)
                    .font(bodyFont)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                    .frame(maxWidth: 600, alignment: .leading)
                    .opacity(isAppearing ? 1 : 0)
                    .offset(y: isAppearing ? 0 : 25)
            }

            // Action buttons
            actionButtons
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 30)
        }
        .animation(.easeOut(duration: 0.5).delay(0.2), value: isAppearing)
    }

    // MARK: - Type Badge

    private var typeBadge: some View {
        Text(item.mediaType == .movie ? "MOVIE" : "SERIES")
            .font(.caption.weight(.bold))
            .tracking(2)
            .foregroundStyle(AppColors.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .heroGlassBadge()
    }

    // MARK: - Metadata Row

    private var metadataRow: some View {
        HStack(spacing: 12) {
            // Year, genre, runtime capsule
            let parts = buildMetadataParts()
            if !parts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        if index > 0 {
                            Text("•")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Text(part)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .heroGlassBadge()
            }

            // Rating badge
            if let rating = safeRating, rating > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .heroGlassBadge()
            }
        }
    }

    private func buildMetadataParts() -> [String] {
        var parts: [String] = []

        if let year = safeYear {
            parts.append(year)
        }

        if let genres = safeGenres {
            parts.append(genres.joined(separator: ", "))
        }

        if let runtime = safeRuntime {
            parts.append(runtime)
        }

        return parts
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            // Primary: Play button
            Button {
                triggerHaptic()
                navigateToItem()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .heroPrimaryButton()

            // Secondary: More Info button
            Button {
                triggerHaptic()
                navigateToItem()
            } label: {
                Label("More Info", systemImage: "info.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .heroSecondaryButton()
        }
    }

    // MARK: - Navigation & Haptics

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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

// MARK: - Hero Glass Badge Extension

private extension View {
    /// Applies glass badge style for hero elements with fallback
    @ViewBuilder
    func heroGlassBadge() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular.tint(.black.opacity(0.1)), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Hero Button Styles

private extension Button {
    /// Primary hero button with prominent glass styling
    @ViewBuilder
    func heroPrimaryButton() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
                .tint(AppColors.accent)
        }
    }

    /// Secondary hero button with subtle glass styling
    @ViewBuilder
    func heroSecondaryButton() -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
                .tint(.white.opacity(0.2))
        }
    }
}

// MARK: - Previews

#Preview("Hero Banner") {
    GeometryReader { geo in
        ScrollView {
            VStack {
                HeroBannerView(
                    item: Movie(
                        name: "Dune: Part Two",
                        streamType: "movie",
                        streamId: 1,
                        tmdbId: nil,
                        streamIcon: "https://image.tmdb.org/t/p/w1280/xOMo8BRK7PfcJv9JCnx7s5hj0PX.jpg",
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

                Spacer()
            }
        }
    }
    .background(Color.black)
}
