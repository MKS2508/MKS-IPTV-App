//
//  MovieDetailView.swift
//  mks-multiplataforma-tvos-iptv
//
//  tvOS detail: poster izquierda + info derecha, fondo blur del poster.
//  Patrón estándar Apple TV+.
//  IPTV detail cached with SWR. TMDB enrichment cached 7 days.
//

import SwiftUI
import IPTVCore

struct MovieDetailView: View {
    let movie: Movie

    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var detail: MovieDetail?
    @State private var tmdbData: TMDBEnrichment?   // TMDB enrichment (may arrive after IPTV detail)
    @State private var loadError: String?
    @State private var playingItem: PlayableItem?
    @State private var showInfoPanel = false
    @FocusState private var focusedButton: MovieButton?

    enum MovieButton { case play, info, trailer }

    var body: some View {
        ZStack {
            backgroundBlur
            // Poster column: absolute left, fixed width
            HStack {
                posterColumn
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Info column: explicit leading offset so it never depends on HStack space distribution
            HStack {
                Spacer().frame(width: 640)
                infoColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            infoPanelOverlay
        }
        .ignoresSafeArea()
        .task { await loadAll() }
        .onAppear { focusedButton = .play }
        .fullScreenCover(item: $playingItem) { item in
            TVPlayerView(item: item) { playingItem = nil }
        }
    }

    // MARK: - Background

    private var backgroundBlur: some View {
        ZStack {
            // Prefer TMDB backdrop (widescreen, higher quality)
            let backdropURL: URL? = {
                if let u = tmdbData?.backdropURL { return URL(string: u) }
                if let u = movie.streamIcon       { return URL(string: u) }
                return nil
            }()

            if let url = backdropURL {
                CachedHTTPImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Color.black
                    }
                }
            } else {
                Color.black
            }
            Color.black.opacity(0.82)
            Rectangle().fill(.ultraThinMaterial).opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Poster Column

    private var posterColumn: some View {
        VStack {
            Spacer()
            posterImage
                .frame(width: 460, height: 680)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.7), radius: 40, x: 0, y: 20)
            Spacer()
        }
        .padding(.leading, 120)
        .padding(.trailing, 60)
        .frame(width: 640)
    }

    @ViewBuilder
    private var posterImage: some View {
        // Prefer TMDB poster (high quality), then streamIcon
        let posterURL: URL? = {
            if let u = tmdbData?.posterURL { return URL(string: u) }
            if let u = movie.streamIcon    { return URL(string: u) }
            return nil
        }()

        if let url = posterURL {
            CachedHTTPImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default: posterPlaceholder
                }
            }
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.1, blue: 0.45), Color(red: 0.1, green: 0.2, blue: 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "film.stack")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Info Column

    private var infoColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {

                Text(movie.name)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)

                // Pills: IPTV detail enriched with TMDB
                if let detail {
                    metadataPills(detail)
                } else {
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 80, height: 32)
                        }
                    }
                }

                actionButtons

                // Plot: prefer TMDB (richer), fall back to IPTV
                let plot = (tmdbData?.plot?.isEmpty == false ? tmdbData?.plot : nil)
                         ?? (detail?.plot.isEmpty == false ? detail?.plot : nil)
                if let plot {
                    Divider().overlay(Color.white.opacity(0.15))
                    plotBlock(plot)
                }

                // Cast / director: prefer TMDB, fall back to IPTV
                if let detail {
                    let cast     = tmdbData?.cast.isEmpty == false ? tmdbData!.cast : detail.cast
                    let director = tmdbData?.director ?? (detail.director.isEmpty ? nil : detail.director)
                    if !cast.isEmpty || director != nil {
                        Divider().overlay(Color.white.opacity(0.15))
                        castBlock(cast: cast, director: director)
                    }
                }

                Spacer(minLength: 80)
            }
            .padding(.top, 120)
            .padding(.trailing, 100)
            .padding(.leading, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Metadata Pills

    private func metadataPills(_ d: MovieDetail) -> some View {
        HStack(spacing: 10) {
            // Genre: TMDB first (comma-joined genres), then IPTV
            let genre = tmdbData?.genre.first ?? (d.genre.isEmpty ? nil : d.genre)
            if let genre { GlassPill(text: genre) }

            // Year: TMDB first, then IPTV
            let year = tmdbData?.year.map(String.init)
                    ?? (d.releaseDate.isEmpty ? nil : String(d.releaseDate.prefix(4)))
            if let year { GlassPill(text: year) }

            if !d.duration.isEmpty { GlassPill(text: d.duration) }

            // Rating: TMDB first, then IPTV
            let rating = tmdbData?.rating.map { String(format: "%.1f", $0) } ?? d.rating
            if let r = rating, !r.isEmpty { GlassPill(text: "★ \(r)") }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: playMovie) {
                Label("Play", systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .play)

            Button { showInfoPanel = true } label: {
                Label("Info", systemImage: "info.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .focused($focusedButton, equals: .info)
        }
    }

    // MARK: - Plot / Cast

    private func plotBlock(_ plot: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Storyline")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1)
            Text(plot)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(5)
        }
    }

    private func castBlock(cast: [String], director: String?) -> some View {
        HStack(alignment: .top, spacing: 60) {
            if let director, !director.isEmpty {
                metaBlock(label: "Director", value: director)
            }
            if !cast.isEmpty {
                metaBlock(label: "Cast", value: cast.prefix(4).joined(separator: ", "))
            }
        }
    }

    private func metaBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(2)
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    // MARK: - Info Panel Overlay

    @ViewBuilder
    private var infoPanelOverlay: some View {
        if showInfoPanel, let detail {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showInfoPanel = false }

            DetailInfoPanel(
                title: movie.name,
                metadata: buildMetadata(detail),
                synopsis: tmdbData?.plot ?? detail.plot,
                actions: [
                    PanelAction(label: "Play", icon: "play.fill", action: playMovie),
                    PanelAction(label: "Trailer", icon: "film", action: { MKSLog.app.info("Trailer tapped") })
                ],
                onDismiss: { showInfoPanel = false }
            )
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func buildMetadata(_ d: MovieDetail) -> [MetadataItem] {
        var items: [MetadataItem] = []
        let genre = tmdbData?.genre.first ?? (d.genre.isEmpty ? nil : d.genre)
        if let genre { items.append(MetadataItem(text: genre)) }
        if !d.releaseDate.isEmpty { items.append(MetadataItem(text: d.releaseDate)) }
        if !d.duration.isEmpty    { items.append(MetadataItem(text: d.duration)) }
        let rating = tmdbData?.rating.map { String(format: "%.1f", $0) } ?? d.rating
        if let r = rating, !r.isEmpty { items.append(MetadataItem(text: r, icon: "star.fill")) }
        return items
    }

    // MARK: - Load All (IPTV detail + TMDB in parallel)

    private func loadAll() async {
        guard let profile = profileStore.profile else { return }
        async let iptv: () = loadDetail(profile: profile)
        async let tmdb: () = loadTMDBEnrichment(profile: profile)
        _ = await (iptv, tmdb)
    }

    private func loadDetail(profile: IPTVProfile) async {
        let cache = TVCacheManager.shared

        // SWR: try cache first
        if let cached = await cache.cachedMovieDetail(id: movie.streamId) {
            detail = cached.value
            if cached.isStale {
                // Background refresh
                Task { await fetchAndCacheDetail(profile: profile) }
            }
            return
        }

        // Cache miss: fetch and cache
        await fetchAndCacheDetail(profile: profile)
    }

    private func fetchAndCacheDetail(profile: IPTVProfile) async {
        let service = IPTVService(profile: profile)
        do {
            let d = try await service.fetchMovieDetails(vodId: movie.streamId)
            await TVCacheManager.shared.cacheMovieDetail(d, id: movie.streamId)
            detail = d
        } catch {
            if detail == nil { loadError = "\(error)" }
            MKSLog.app.error("MovieDetail load failed: \(error)")
        }
    }

    private func loadTMDBEnrichment(profile: IPTVProfile) async {
        let cache = TVCacheManager.shared
        let tmdb  = TVTMDBService.shared

        // Build TMDB cache key
        let tmdbIdInt = detail?.tmdbId
                     ?? movie.tmdbId.flatMap { Int($0) }
        let cacheKey  = tmdbIdInt.map { "tmdb_movie_\($0)" }
                     ?? "tmdb_movie_search_\(movie.streamId)"

        // Check cache
        if let cached = await cache.cachedTMDB(key: cacheKey) {
            tmdbData = cached.value
            if !cached.isStale { return }
        }

        // Fetch from TMDB
        do {
            let enrichment: TMDBEnrichment?
            if let tmdbId = tmdbIdInt, tmdbId > 0 {
                enrichment = try await tmdb.fetchMovie(tmdbId: tmdbId)
            } else {
                // Use TitleParseable extension (from IPTVCore) for clean title + year
                let year = movie.year.flatMap { Int($0) }
                enrichment = try await tmdb.searchMovie(title: movie.cleanTitle, year: year)
            }
            if let enrichment {
                await cache.cacheTMDB(enrichment, key: cacheKey)
                tmdbData = enrichment
            }
        } catch {
            MKSLog.app.debug("TMDB enrichment skipped for movie \(movie.streamId): \(error)")
        }
    }

    // MARK: - Playback

    private func playMovie() {
        guard let profile = profileStore.profile,
              let item = PlayableItem.movie(movie, profile: profile) else { return }
        playingItem = item
    }
}
