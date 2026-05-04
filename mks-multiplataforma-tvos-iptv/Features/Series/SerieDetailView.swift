//
//  SerieDetailView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Hero + plot + season picker + episodes list.
//

import SwiftUI
import IPTVCore

struct SerieDetailView: View {
    let serie: Serie

    @EnvironmentObject private var profileStore: ProfileStore

    @State private var detail: SerieDetail?
    @State private var loadError: String?
    @State private var selectedSeasonKey: String?
    @State private var playingItem: PlayableItem?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero

                if let detail {
                    if !detail.info.plot.isEmpty {
                        plotSection(detail.info.plot)
                    }

                    seasonsSection(detail)
                    episodesSection(detail)
                } else if loadError != nil {
                    errorBanner
                } else {
                    ProgressView()
                        .scaleEffect(1.6)
                        .frame(maxWidth: .infinity, minHeight: 200)
                }

                Spacer(minLength: 80)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .task { await loadDetail() }
        .fullScreenCover(item: $playingItem) { item in
            TVPlayerView(item: item) { playingItem = nil }
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

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            backdropImage
                .frame(height: 720)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 720)

            VStack(alignment: .leading, spacing: 18) {
                Text(serie.name)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 1200, alignment: .leading)

                HStack(spacing: 16) {
                    if !serie.genre.isEmpty {
                        Text(serie.genre)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    if !serie.releaseDate.isEmpty {
                        metaPill(serie.releaseDate)
                    }
                    if serie.rating5Based > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(String(format: "%.1f", serie.rating5Based))
                        }
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                    if let detail {
                        metaPill("\(detail.seasons.count) seasons")
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
        .frame(height: 720)
    }

    @ViewBuilder
    private var backdropImage: some View {
        let urlString = detail?.info.backdropPath.first ?? serie.cover ?? ""
        if let url = URL(string: urlString) {
            CachedHTTPImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    backdropPlaceholder
                @unknown default:
                    backdropPlaceholder
                }
            }
        } else {
            backdropPlaceholder
        }
    }

    private var backdropPlaceholder: some View {
        LinearGradient(
            colors: [.indigo.opacity(0.7), .pink.opacity(0.4), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func plotSection(_ plot: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storyline")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(plot)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(6)
                .frame(maxWidth: 1400, alignment: .leading)
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
    }

    private func seasonsSection(_ detail: SerieDetail) -> some View {
        let availableKeys = orderedSeasonKeys(detail)
        return VStack(alignment: .leading, spacing: 16) {
            Text("Seasons")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(availableKeys, id: \.self) { key in
                        seasonChip(key: key, isSelected: key == effectiveSeasonKey(detail))
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
        }
        .padding(.top, 40)
    }

    private func seasonChip(key: String, isSelected: Bool) -> some View {
        Button {
            selectedSeasonKey = key
        } label: {
            Text("Season \(key)")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .white : .white.opacity(0.5))
        .foregroundStyle(isSelected ? .black : .white)
    }

    private func episodesSection(_ detail: SerieDetail) -> some View {
        let key = effectiveSeasonKey(detail)
        let episodes = detail.episodes[key] ?? []

        return VStack(alignment: .leading, spacing: 16) {
            Text("Episodes")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            if episodes.isEmpty {
                Text("No episodes available")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 80)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(episodes.sorted(by: { $0.episodeNum < $1.episodeNum })) { episode in
                        EpisodeRow(episode: episode) { playEpisode(episode) }
                            .padding(.horizontal, 80)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .padding(.top, 40)
    }

    private var errorBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Couldn't load episodes")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            if let loadError {
                Text(loadError)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.white.opacity(0.12), in: Capsule())
    }

    private func orderedSeasonKeys(_ detail: SerieDetail) -> [String] {
        let keys = Set(detail.episodes.keys).union(detail.seasons.map { String($0.id) })
        return keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    private func effectiveSeasonKey(_ detail: SerieDetail) -> String {
        if let selected = selectedSeasonKey { return selected }
        return orderedSeasonKeys(detail).first ?? "1"
    }

    private func loadDetail() async {
        guard detail == nil, let profile = profileStore.profile else { return }
        let service = IPTVService(profile: profile)
        do {
            var d = try await service.fetchSeriesDetails(seriesId: serie.seriesId)
            d.seriesId = serie.seriesId
            detail = d
        } catch {
            loadError = "\(error)"
            MKSLog.app.error("SerieDetail load failed: \(error)")
        }
    }
}

// MARK: - EpisodeRow

private struct EpisodeRow: View {
    let episode: SerieDetail.Episode
    let onPlay: () -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 24) {
                Text(String(format: "%02d", episode.episodeNum))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.6))
                    .frame(width: 100, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Season \(episode.season) · Episode \(episode.episodeNum)")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 0)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.5))
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isFocused ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}
