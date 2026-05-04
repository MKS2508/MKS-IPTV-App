import SwiftUI
import IPTVCore

struct SeriesEpisodePickerView: View {
    let serie: DebugStreamItem
    let onEpisodeSelected: (SerieDetail.Episode) -> Void
    let onDismiss: () -> Void
    
    @EnvironmentObject var profile: IPTVProfile
    @State private var selectedSeason: String = ""
    @State private var episodes: [SerieDetail.Episode] = []
    @State private var isLoading = true
    @State private var serieDetail: SerieDetail?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Episode - \(serie.title)")
                    .font(.headline)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            
            Divider()
            
            if isLoading {
                ProgressView("Loading episodes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = serieDetail {
                VStack {
                    // Season picker
                    Picker("Season", selection: $selectedSeason) {
                        ForEach(detail.seasons, id: \.id) { season in
                            Text("Season \(season.seasonNumber)")
                                .tag(season.id)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    
                    // Episodes list
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(episodes, id: \.id) { episode in
                                DebugEpisodeRow(episode: episode) {
                                    onEpisodeSelected(episode)
                                    onDismiss()
                                }
                            }
                        }
                        .padding()
                    }
                }
            } else {
                Text("Failed to load episodes")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 600, height: 500)
        .background(.ultraThinMaterial)
        .task {
            await loadSeriesDetails()
        }
        .onChange(of: selectedSeason) {
            updateEpisodes()
        }
    }
    
    private func loadSeriesDetails() async {
        isLoading = true
        do {
            let movieService = MovieService(profile: profile)
            let detail = try await movieService.fetchSeriesDetails(seriesId: serie.id)
            serieDetail = detail
            if let firstSeason = detail.seasons.first {
                selectedSeason = firstSeason.id
                // API returns episodes keyed by season number (e.g. "1"), not by season ID.
                // Try season.id first, fall back to String(season.seasonNumber).
                let key = episodesKey(for: firstSeason, in: detail)
                episodes = detail.episodes[key] ?? []
            }
        } catch {
            MKSLog.debug.error("Failed to load series details: \(error)")
        }
        isLoading = false
    }
    
    private func updateEpisodes() {
        guard let detail = serieDetail,
              let season = detail.seasons.first(where: { $0.id == selectedSeason }) else {
            episodes = []
            return
        }
        let key = episodesKey(for: season, in: detail)
        episodes = detail.episodes[key] ?? []
    }

    /// Resolves the correct dictionary key for a season's episodes.
    /// Xtream IPTV panels use the season number as key ("1", "2"…) rather than
    /// the season's internal ID. We probe both and return whichever exists.
    private func episodesKey(for season: SerieDetail.Season, in detail: SerieDetail) -> String {
        if detail.episodes[season.id] != nil {
            return season.id
        }
        let numberKey = String(season.seasonNumber)
        if detail.episodes[numberKey] != nil {
            return numberKey
        }
        // Last resort: return season.id and let the caller handle empty result
        return season.id
    }
}

struct DebugEpisodeRow: View {
    let episode: SerieDetail.Episode
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Episode \(episode.episodeNum): \(episode.title)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        Label("\(episode.info.duration)", systemImage: "clock")
                        Label("Ext: \(episode.containerExtension)", systemImage: "doc")
                        if episode.info.rating5Based > 0 {
                            Label(String(format: "%.1f", episode.info.rating5Based), systemImage: "star.fill")
                                .foregroundColor(.yellow)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    if !episode.info.plot.isEmpty {
                        Text(episode.info.plot)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                
                Spacer()
                
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
