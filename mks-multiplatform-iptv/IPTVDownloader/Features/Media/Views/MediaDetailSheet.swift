//
//  MediaDetailSheet.swift
//  mks-multiplatform-iptv
//
//  Unified detail view for movies and series (Apple TV+/Netflix style).
//  Replaces AddDownloadMediaViewiOS/AddDownloadView with enriched metadata,
//  glass tabs, and download-in-place (detail stays open after download starts).
//

import SwiftUI

struct MediaDetailSheet: View {
    /// Unified detail item — either MovieDetail or SerieDetail,
    /// both conforming to MediaDetailItem (which extends LibraryItem).
    let detail: any MediaDetailItem
    let onDismiss: () -> Void

    @Binding var selectedView: String?

    /// Downcast to SerieDetail for series-specific features (seasons, episodes)
    private var serieDetail: SerieDetail? { detail as? SerieDetail }
    private var movieDetail: MovieDetail? { detail as? MovieDetail }

    @EnvironmentObject private var downloadManager: DownloadManager

    // MARK: - State

    @State private var enrichedMetadata: MetadataResult?
    @State private var metadataCandidates: [ScoredMetadataResult] = []
    @State private var selectedTab: DetailTab = .overview
    @State private var selectedSeason: String = "1"
    @State private var episodeSearchText = ""

    // Download in-place
    @State private var showDownloadOptions = false
    @State private var downloadEpisode: SerieDetail.Episode?
    @State private var downloadStartedBanner = false
    @State private var shouldConvertToMOV = true
    @State private var selectedFolder: URL = FileManager.default.urls(
        for: .downloadsDirectory, in: .userDomainMask
    ).first!

    #if os(macOS)
    private let headerMaxHeight: CGFloat = 350
    #else
    private let headerMaxHeight: CGFloat = 400
    #endif

    // MARK: - Tabs

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case episodes = "Episodes"
    }

    private var visibleTabs: [DetailTab] {
        if serieDetail != nil {
            return DetailTab.allCases
        }
        return [.overview]
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    headerSection
                    tabBarSection
                    tabContent
                    Spacer(minLength: 60)
                }
            }

            // Floating close button
            closeButton

            // Download started banner
            if downloadStartedBanner {
                downloadBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await loadEnrichedMetadata()
            if let serie = serieDetail {
                selectedSeason = serie.seasons.first?.id ?? "1"
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            backdropView
                .frame(height: headerMaxHeight)
                .clipped()

            // Gradient
            LinearGradient(
                colors: [
                    .clear,
                    AppColors.background.opacity(0.6),
                    AppColors.background
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            // Content overlay
            HStack(alignment: .bottom, spacing: 16) {
                posterView
                titleBlock
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(height: headerMaxHeight)
    }

    @ViewBuilder
    private var backdropView: some View {
        let url = bestBackdropURL

        if let url {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                case .failure:
                    fallbackBackdrop
                case .empty:
                    SkeletonLoader()
                        .frame(maxWidth: .infinity)
                @unknown default:
                    fallbackBackdrop
                }
            }
        } else {
            fallbackBackdrop
        }
    }

    private var bestBackdropURL: URL? {
        let candidates: [String?] = [
            enrichedMetadata?.backdropURL,
            detail.detailBackdropPaths.first,
            detail.coverImage
        ]
        return candidates.compactMap { $0 }.compactMap { URL(string: $0) }.first
    }

    private var fallbackBackdrop: some View {
        LinearGradient(
            colors: [AppColors.accentDark, AppColors.background],
            startPoint: .topTrailing,
            endPoint: .bottomLeading
        )
    }

    @ViewBuilder
    private var posterView: some View {
        let posterStr = enrichedMetadata?.posterURL
            ?? detail.detailPosterURL
            ?? detail.coverImage

        if let str = posterStr, let url = URL(string: str) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                default:
                    posterPlaceholder
                }
            }
            .frame(width: 110, height: 165)
            .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
            .fill(AppColors.surface)
            .frame(width: 110, height: 165)
            .overlay {
                Image(systemName: detail.mediaType == .movie ? "film" : "tv")
                    .font(.largeTitle)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }

    @ViewBuilder
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type badge
            Text(detail.mediaType == .movie ? "MOVIE" : "SERIES")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(AppColors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .adaptiveGlass(in: Capsule())

            // Title
            Text(detail.cleanTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            // Metadata pills
            metadataPills

            // Rating
            ratingBadge

            // Action buttons
            actionButtons
        }
    }

    // MARK: - Metadata Pills

    @ViewBuilder
    private var metadataPills: some View {
        let parts = buildMetadataParts()
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 {
                        Text("\u{2022}")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text(part)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func buildMetadataParts() -> [String] {
        var parts: [String] = []

        if let year = enrichedMetadata?.year {
            parts.append(String(year))
        } else if let year = detail.year {
            parts.append(year)
        }

        if let genres = enrichedMetadata?.genre, !genres.isEmpty {
            parts.append(genres.prefix(2).joined(separator: ", "))
        } else if !detail.detailGenre.isEmpty {
            parts.append(detail.detailGenre)
        }

        if let runtime = enrichedMetadata?.runtimeMinutes, runtime > 0 {
            let h = runtime / 60
            let m = runtime % 60
            parts.append(h > 0 ? "\(h)h \(m)m" : "\(m)m")
        } else if detail.detailDurationSeconds > 0 {
            let h = detail.detailDurationSeconds / 3600
            let m = (detail.detailDurationSeconds % 3600) / 60
            parts.append(h > 0 ? "\(h)h \(m)m" : "\(m)m")
        }

        if let quality = detail.quality {
            parts.append(quality)
        }
        if detail.isHDR { parts.append("HDR") }

        return parts
    }

    // MARK: - Rating Badge

    @ViewBuilder
    private var ratingBadge: some View {
        let rating: Double? = {
            if let r = enrichedMetadata?.rating, r > 0 { return r }
            if detail.displayRating5Based > 0 { return detail.displayRating5Based * 2 }
            return nil
        }()

        if let rating, rating > 0 {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption2)
                Text(String(format: "%.1f", rating))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .adaptiveGlass(in: Capsule())
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                // Play — reuse existing navigation
                navigateToItem()
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.appGlassProminent)

            Button {
                downloadEpisode = nil
                showDownloadOptions = true
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.appGlass)
        }
        .sheet(isPresented: $showDownloadOptions) {
            downloadSheet
                .presentationDetents([.medium])
        }
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBarSection: some View {
        if visibleTabs.count > 1 {
            GlassSegmentedControl(
                options: visibleTabs,
                selectedOption: $selectedTab,
                titleKeyPath: \.rawValue,
                imageKeyPath: nil
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewContent
        case .episodes:
            episodesContent
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Plot
            let plot = enrichedMetadata?.plot ?? detail.detailPlot
            if !plot.isEmpty {
                Text(plot)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineSpacing(4)
            }

            // Director
            let director = enrichedMetadata?.director ?? detail.detailDirector
            if let director, !director.isEmpty {
                infoRow("Director", value: director)
            }

            // Cast
            let cast: String = {
                if let c = enrichedMetadata?.cast, !c.isEmpty {
                    return c.prefix(6).joined(separator: ", ")
                }
                let detailCast = detail.detailCast.filter { !$0.isEmpty }
                if !detailCast.isEmpty {
                    return detailCast.prefix(6).joined(separator: ", ")
                }
                return ""
            }()
            if !cast.isEmpty {
                infoRow("Cast", value: cast)
            }

            // Trailer link
            let trailer = detail.detailYoutubeTrailer
            if let trailer, !trailer.isEmpty {
                Link(destination: URL(string: "https://www.youtube.com/watch?v=\(trailer)")!) {
                    Label("Watch Trailer", systemImage: "play.rectangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.accent)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.textTertiary)
                .tracking(0.8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Episodes Tab

    @ViewBuilder
    private var episodesContent: some View {
        if let serieDetail {
            VStack(alignment: .leading, spacing: 12) {
                // Season picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(serieDetail.seasons, id: \.id) { season in
                            Button(season.name) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedSeason = season.id
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                selectedSeason == season.id
                                    ? .white : AppColors.textSecondary
                            )
                            .adaptiveGlass(in: Capsule())
                            .overlay {
                                if selectedSeason == season.id {
                                    Capsule()
                                        .stroke(AppColors.accent, lineWidth: 1.5)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Episode list
                let episodes = filteredEpisodes(serieDetail: serieDetail)

                if episodes.isEmpty {
                    ContentUnavailableView(
                        "No Episodes",
                        systemImage: "tv.slash",
                        description: Text("No episodes found for this season.")
                    )
                    .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(episodes, id: \.id) { episode in
                            EpisodeRowView(
                                episode: episode,
                                serieName: detail.cleanTitle,
                                onPlay: {
                                    // Play episode
                                },
                                onDownload: {
                                    downloadEpisode = episode
                                    showDownloadOptions = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 12)
        }
    }

    private func filteredEpisodes(serieDetail: SerieDetail) -> [SerieDetail.Episode] {
        let all = serieDetail.episodes[selectedSeason] ?? []
        if episodeSearchText.isEmpty { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(episodeSearchText)
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Download Sheet (in-place, does NOT dismiss detail)

    @ViewBuilder
    private var downloadSheet: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Download Options")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showDownloadOptions = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // MOV conversion toggle
            Toggle(isOn: $shouldConvertToMOV) {
                Label("Convert to MOV", systemImage: "film")
                    .font(.subheadline)
            }
            .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))

            Spacer()

            // Download button
            Button {
                startDownload()
            } label: {
                Label(
                    downloadEpisode != nil ? "Download Episode" : "Download Movie",
                    systemImage: "arrow.down.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .padding(24)
    }

    // MARK: - Download Action (stays in detail)

    private func startDownload() {
        if let episode = downloadEpisode, serieDetail != nil {
            downloadManager.startDownload(
                vodID: episode.id,
                title: episode.title,
                type: .series,
                vodExtension: episode.containerExtension,
                shouldConvertToMOV: shouldConvertToMOV,
                downloadPathParam: selectedFolder.path,
                genre: detail.detailGenre,
                runtimeMinutes: nil,
                preResolvedMetadata: enrichedMetadata,
                metadataCandidates: metadataCandidates
            )
        } else if let movie = movieDetail {
            downloadManager.startDownload(
                vodID: String(movie.tmdbId),
                title: detail.cleanTitle,
                type: .movie,
                vodExtension: movie.movieData.containerExtension ?? "mkv",
                shouldConvertToMOV: shouldConvertToMOV,
                downloadPathParam: selectedFolder.path,
                tmdbId: movie.tmdbId,
                genre: detail.detailGenre,
                runtimeMinutes: detail.detailDurationSeconds / 60,
                preResolvedMetadata: enrichedMetadata,
                metadataCandidates: metadataCandidates
            )
        }

        showDownloadOptions = false

        // Show confirmation banner (detail stays open)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            downloadStartedBanner = true
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            await MainActor.run {
                withAnimation { downloadStartedBanner = false }
            }
        }
    }

    // MARK: - Download Banner

    private var downloadBanner: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                Text("Download started")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
            .padding(.horizontal, 20)
            .padding(.top, 60)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func navigateToItem() {
        switch detail.mediaType {
        case .movie:
            selectedView = NavigationDestination.movies.rawValue
        case .series:
            selectedView = NavigationDestination.series.rawValue
        }
    }

    private func loadEnrichedMetadata() async {
        let result = await EnrichedMediaStore.shared
            .getEnrichedMetadata(for: detail, tmdbId: detail.tmdbIdInt)
        enrichedMetadata = result
    }
}

// MARK: - Episode Row

struct EpisodeRowView: View {
    let episode: SerieDetail.Episode
    let serieName: String
    let onPlay: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Episode thumbnail
            if let imageURL = URL(string: episode.info.movieImage) {
                CachedAsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        AppColors.surface
                    }
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColors.surface)
                    .frame(width: 120, height: 68)
                    .overlay {
                        Image(systemName: "play.rectangle")
                            .foregroundStyle(AppColors.textTertiary)
                    }
            }

            // Episode info
            VStack(alignment: .leading, spacing: 4) {
                Text("E\(episode.episodeNum)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColors.accent)
                Text(episode.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !episode.info.duration.isEmpty {
                    Text(episode.info.duration)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}
