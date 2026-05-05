//
//  EpisodeBrowserView.swift
//  mks-multiplataforma-tvos-iptv
//
//  tvOS episode browser: season picker chips + horizontal episode cards.
//  Uses .buttonStyle(.card) for native tvOS focus + selection behaviour.
//  @FocusState tracks focused episode to drive the preview strip below.
//

import SwiftUI
import IPTVCore

struct EpisodeBrowserView: View {
    let seasons: [SerieDetail.Season]
    let episodes: [String: [SerieDetail.Episode]]
    let selectedSeasonKey: String
    let onSeasonChange: (String) -> Void
    let onEpisodePlay: (SerieDetail.Episode) -> Void

    @FocusState private var focusedEpisodeId: String?
    @Namespace private var episodeNS

    private let cardWidth: CGFloat  = 420
    private let cardHeight: CGFloat = 236   // 16:9

    // Derive the currently focused episode for the preview strip
    private var focusedEpisode: SerieDetail.Episode? {
        guard let id = focusedEpisodeId else { return nil }
        return currentEpisodes.first { $0.id == id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            seasonPickerRow
                .padding(.bottom, 20)
            episodeScrollRow
            if focusedEpisode != nil {
                previewStrip
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: focusedEpisodeId)
    }

    // MARK: - Season Picker

    private var seasonPickerRow: some View {
        // Wrap in a focusSection so the tvOS engine can enter this row
        // independently from the episode cards below.
        HStack(spacing: 12) {
            ForEach(orderedSeasonKeys, id: \.self) { key in
                seasonChip(key: key)
            }
        }
        .focusSection()
    }

    private func seasonChip(key: String) -> some View {
        Button {
            onSeasonChange(key)
        } label: {
            Text(seasonLabel(for: key))
                .font(.body.weight(.semibold))
                .foregroundStyle(key == selectedSeasonKey ? Color.black : Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
        }
        .buttonStyle(SeasonChipButtonStyle(isSelected: key == selectedSeasonKey))
    }

    // MARK: - Episode Scroll

    private var episodeScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 20) {
                ForEach(currentEpisodes) { episode in
                    episodeCard(episode)
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 28)
            .scrollTargetLayout()
        }
        .scrollClipDisabled()
        .focusSection()
    }

    @ViewBuilder
    private func episodeCard(_ episode: SerieDetail.Episode) -> some View {
        Button {
            onEpisodePlay(episode)
        } label: {
            episodeCardLabel(episode)
        }
        // .card gives native tvOS parallax + highlight + selection
        .buttonStyle(.card)
        .frame(width: cardWidth, height: cardHeight + 68)
        .focused($focusedEpisodeId, equals: episode.id as String)
    }

    private func episodeCardLabel(_ episode: SerieDetail.Episode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                episodeThumbnailImage(episode)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                GlassBadge(text: String(format: "E%02d", episode.episodeNum))
                    .padding(10)
            }
            // Info strip
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: cardWidth - 20, alignment: .leading)
                if !episode.info.duration.isEmpty {
                    Text(episode.info.duration)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(width: cardWidth, alignment: .leading)
            .background(Color(white: 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func episodeThumbnailImage(_ episode: SerieDetail.Episode) -> some View {
        if let thumb = episode.info.movieImage.nilIfEmpty, let url = URL(string: thumb) {
            CachedHTTPImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    thumbnailPlaceholder
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.1, blue: 0.35),
                    Color(red: 0.08, green: 0.05, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "play.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Preview Strip (shown when an episode is focused)

    private var previewStrip: some View {
        Group {
            if let episode = focusedEpisode {
                HStack(alignment: .top, spacing: 24) {
                    // Mini thumbnail
                    ZStack {
                        episodeThumbnailImage(episode)
                    }
                    .frame(width: 200, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Episode meta
                    VStack(alignment: .leading, spacing: 6) {
                        Text("S\(episode.season)  E\(episode.episodeNum)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white.opacity(0.55))
                            .tracking(1)
                        Text(episode.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if !episode.info.duration.isEmpty {
                            Text(episode.info.duration)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        if !episode.info.plot.isEmpty {
                            Text(episode.info.plot)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(3)
                        }
                    }

                    Spacer()

                    // Play button in preview strip — NOT in the focus path (decorative)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 20)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }

    // MARK: - Helpers

    private var orderedSeasonKeys: [String] {
        let keys = Set(episodes.keys).union(seasons.map { String($0.id) })
        return keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
    }

    private var currentEpisodes: [SerieDetail.Episode] {
        (episodes[selectedSeasonKey] ?? []).sorted { $0.episodeNum < $1.episodeNum }
    }

    private func seasonLabel(for key: String) -> String {
        if let num = Int(key) { return "Season \(num)" }
        return key
    }
}

// MARK: - Season Chip Button Style

struct SeasonChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .background(chipBackground(configuration: configuration))
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func chipBackground(configuration: Configuration) -> some View {
        if #available(tvOS 26, *) {
            Capsule()
                .glassEffect(
                    isSelected
                        ? .regular.tint(.white.opacity(0.85))
                        : .regular.interactive(),
                    in: .capsule
                )
        } else {
            if isSelected {
                Capsule().fill(Color.white)
            } else {
                Capsule().fill(Color.white.opacity(0.18))
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
        }
    }
}

extension ButtonStyle where Self == SeasonChipButtonStyle {
    static func seasonChipStyle(isSelected: Bool) -> SeasonChipButtonStyle {
        SeasonChipButtonStyle(isSelected: isSelected)
    }
}

// MARK: - String nil-if-empty helper

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
