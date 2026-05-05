//
//  SerieDetailView.swift
//  mks-multiplataforma-tvos-iptv
//
//  tvOS detail: poster izquierda + info + episodios derecha, fondo blur del poster.
//  Patrón estándar Apple TV+.
//  IPTV detail cached with SWR. TMDB enrichment cached 7 days.
//

import SwiftUI
import IPTVCore

struct SerieDetailView: View {
    let serie: Serie

    @EnvironmentObject private var profileStore: ProfileStore

    @State private var detail: SerieDetail?
    @State private var tmdbData: TMDBEnrichment?   // TMDB enrichment (may arrive after IPTV detail)
    @State private var loadError: String?
    @State private var selectedSeasonKey: String?
    @State private var playingItem: PlayableItem?
    @State private var showInfoPanel = false
    @FocusState private var focusedButton: SerieButton?

    enum SerieButton { case play, info }

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
            let backdropURL: URL? = {
                if let u = tmdbData?.backdropURL  { return URL(string: u) }
                if let u = serie.cover            { return URL(string: u) }
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
        let posterURL: URL? = {
            if let u = tmdbData?.posterURL { return URL(string: u) }
            if let u = serie.cover         { return URL(string: u) }
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
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Info Column

    private var infoColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {

                Text(serie.name)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)

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

                // Plot: prefer TMDB
                let plot = (tmdbData?.plot?.isEmpty == false ? tmdbData?.plot : nil)
                         ?? (detail?.info.plot.isEmpty == false ? detail?.info.plot : nil)
                         ?? (serie.plot.isEmpty ? nil : serie.plot)
                if let plot {
                    Divider().overlay(Color.white.opacity(0.15))
                    plotBlock(plot)
                }

                // Cast / director: prefer TMDB
                let castList = tmdbData?.cast.isEmpty == false
                    ? tmdbData!.cast
                    : detail?.info.cast.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
                let director = tmdbData?.director
                    ?? detail?.info.director
                    ?? (serie.director?.isEmpty == false ? serie.director : nil)
                if !castList.isEmpty || director != nil {
                    Divider().overlay(Color.white.opacity(0.15))
                    castBlock(cast: castList, director: director)
                }

                // Episodes
                if let detail, !detail.episodes.isEmpty {
                    Divider().overlay(Color.white.opacity(0.15))
                    episodeBrowserSection(detail)
                } else if detail == nil && loadError == nil {
                    HStack {
                        ProgressView().scaleEffect(1.4)
                        Text("Loading episodes…")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 12)
                } else if let loadError {
                    errorBanner(loadError)
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

    private func metadataPills(_ d: SerieDetail) -> some View {
        HStack(spacing: 10) {
            let genre = tmdbData?.genre.first ?? (serie.genre.isEmpty ? nil : serie.genre)
            if let genre { GlassPill(text: genre) }

            let year = tmdbData?.year.map(String.init)
                    ?? (serie.releaseDate.isEmpty ? nil : String(serie.releaseDate.prefix(4)))
            if let year { GlassPill(text: year) }

            let rating = tmdbData?.rating.map { String(format: "★ %.1f", $0) }
                      ?? (serie.rating5Based > 0 ? String(format: "★ %.1f", serie.rating5Based) : nil)
            if let r = rating { GlassPill(text: r) }

            if !d.seasons.isEmpty {
                GlassPill(text: "\(d.seasons.count) Season\(d.seasons.count == 1 ? "" : "s")")
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button(action: playFirstEpisode) {
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

    // MARK: - Episode Browser

    private func episodeBrowserSection(_ detail: SerieDetail) -> some View {
        EpisodeBrowserView(
            seasons: detail.seasons,
            episodes: detail.episodes,
            selectedSeasonKey: effectiveSeasonKey(detail),
            onSeasonChange: { key in selectedSeasonKey = key },
            onEpisodePlay: { episode in playEpisode(episode) }
        )
        .padding(.top, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Couldn't load episodes")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Info Panel Overlay

    @ViewBuilder
    private var infoPanelOverlay: some View {
        if showInfoPanel, let detail {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showInfoPanel = false }

            DetailInfoPanel(
                title: serie.name,
                metadata: buildMetadata(detail),
                synopsis: tmdbData?.plot ?? detail.info.plot,
                actions: [
                    PanelAction(label: "Play", icon: "play.fill") {
                        if let first = detail.episodes[effectiveSeasonKey(detail)]?.first {
                            playEpisode(first)
                        }
                    }
                ],
                onDismiss: { showInfoPanel = false }
            )
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func buildMetadata(_ detail: SerieDetail) -> [MetadataItem] {
        var items: [MetadataItem] = []
        let genre = tmdbData?.genre.first ?? (serie.genre.isEmpty ? nil : serie.genre)
        if let genre { items.append(MetadataItem(text: genre)) }
        if !serie.releaseDate.isEmpty { items.append(MetadataItem(text: serie.releaseDate)) }
        if !detail.seasons.isEmpty { items.append(MetadataItem(text: "\(detail.seasons.count) Seasons")) }
        let rating = tmdbData?.rating ?? (serie.rating5Based > 0 ? serie.rating5Based : nil)
        if let r = rating { items.append(MetadataItem(text: String(format: "%.1f", r), icon: "star.fill")) }
        return items
    }

    // MARK: - Load All (IPTV detail + TMDB in parallel)

    private func loadAll() async {
        guard let profile = profileStore.profile else { return }
        async let iptv: () = loadDetail(profile: profile)
        async let tmdb: () = loadTMDBEnrichment()
        _ = await (iptv, tmdb)
    }

    private func loadDetail(profile: IPTVProfile) async {
        let cache = TVCacheManager.shared

        if let cached = await cache.cachedSerieDetail(id: serie.seriesId) {
            detail = cached.value
            if cached.isStale {
                Task { await fetchAndCacheDetail(profile: profile) }
            }
            return
        }

        await fetchAndCacheDetail(profile: profile)
    }

    private func fetchAndCacheDetail(profile: IPTVProfile) async {
        let service = IPTVService(profile: profile)
        do {
            var d = try await service.fetchSeriesDetails(seriesId: serie.seriesId)
            d.seriesId = serie.seriesId
            await TVCacheManager.shared.cacheSerieDetail(d, id: serie.seriesId)
            detail = d
        } catch {
            if detail == nil { loadError = "\(error)" }
            MKSLog.app.error("SerieDetail load failed: \(error)")
        }
    }

    private func loadTMDBEnrichment() async {
        let cache = TVCacheManager.shared
        let tmdb  = TVTMDBService.shared
        let cacheKey = "tmdb_serie_\(serie.seriesId)"

        // Check cache
        if let cached = await cache.cachedTMDB(key: cacheKey) {
            tmdbData = cached.value
            if !cached.isStale { return }
        }

        // Search by clean title + year (Serie has no tmdbId)
        do {
            let year = serie.year.flatMap { Int($0) }
                    ?? (serie.releaseDate.isEmpty ? nil : Int(serie.releaseDate.prefix(4)))
            if let enrichment = try await tmdb.searchSerie(title: serie.cleanTitle, year: year) {
                await cache.cacheTMDB(enrichment, key: cacheKey)
                tmdbData = enrichment
            }
        } catch {
            MKSLog.app.debug("TMDB enrichment skipped for serie \(serie.seriesId): \(error)")
        }
    }

    // MARK: - Helpers

    private func playFirstEpisode() {
        guard let detail else { return }
        if let first = detail.episodes[effectiveSeasonKey(detail)]?.first {
            playEpisode(first)
        }
    }

    private func playEpisode(_ episode: SerieDetail.Episode) {
        guard let profile = profileStore.profile,
              let item = PlayableItem.episode(episode, serie: serie, profile: profile) else {
            MKSLog.player.error("Could not build PlayableItem for episode id=\(episode.id)")
            return
        }
        MKSLog.player.info("Episode play id=\(episode.id) S\(episode.season)E\(episode.episodeNum)")
        playingItem = item
    }

    private func orderedSeasonKeys(_ detail: SerieDetail) -> [String] {
        let keys = Set(detail.episodes.keys).union(detail.seasons.map { String($0.id) })
        return keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    private func effectiveSeasonKey(_ detail: SerieDetail) -> String {
        if let selected = selectedSeasonKey { return selected }
        return orderedSeasonKeys(detail).first ?? "1"
    }
}
