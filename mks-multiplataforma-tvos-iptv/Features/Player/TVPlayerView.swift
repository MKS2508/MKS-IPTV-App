//
//  TVPlayerView.swift
//  mks-multiplataforma-tvos-iptv
//
//  AVPlayerViewController-based player for tvOS. Native scrub, info overlay,
//  focus, AirPlay, subtitles all handled by the system.
//
//  Phase 1 (Block 5): direct URL → AVPlayer native. MP4 / HLS / m3u8 work.
//  Phase 2 (Block 6): transmux fallback for MKV/AVI via TransmuxCore.
//

import SwiftUI
import AVKit
import IPTVCore

// MARK: - Public entry

struct TVPlayerView: View {
    let item: PlayableItem
    let onDismiss: () -> Void

    var body: some View {
        TVPlayerControllerHost(item: item, onDismiss: onDismiss)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Playable item

struct PlayableItem: Equatable, Identifiable {
    enum Kind: Equatable {
        case vod          // movies, series episodes
        case live         // live channels (HLS)
    }

    let title: String
    let subtitle: String?
    let url: URL
    let kind: Kind

    var id: String { url.absoluteString }

    static func movie(_ movie: Movie, profile: IPTVProfile) -> PlayableItem? {
        let ext = movie.containerExtension ?? profile.fileExtension
        let urlString = IPTVConfiguration.buildMovieURL(
            profile: profile,
            vodID: String(movie.streamId),
            vodExtension: ext
        )
        guard let url = URL(string: urlString) else { return nil }
        return .init(title: movie.name, subtitle: nil, url: url, kind: .vod)
    }

    static func episode(_ episode: SerieDetail.Episode, serie: Serie, profile: IPTVProfile) -> PlayableItem? {
        let ext = episode.containerExtension.isEmpty ? profile.fileExtension : episode.containerExtension
        let urlString = IPTVConfiguration.buildSeriesURL(
            profile: profile,
            vodID: String(episode.id),
            vodExtension: ext
        )
        guard let url = URL(string: urlString) else { return nil }
        return .init(
            title: episode.title,
            subtitle: "\(serie.name) · S\(episode.season) · E\(episode.episodeNum)",
            url: url,
            kind: .vod
        )
    }

    static func live(_ channel: LiveChannel, profile: IPTVProfile) -> PlayableItem? {
        let urlString = IPTVConfiguration.buildLiveChannelURL(
            profile: profile,
            channelID: channel.streamId
        )
        guard let url = URL(string: urlString) else { return nil }
        return .init(title: channel.name, subtitle: "Live", url: url, kind: .live)
    }
}

// MARK: - UIViewControllerRepresentable

private struct TVPlayerControllerHost: UIViewControllerRepresentable {
    let item: PlayableItem
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: item.url)
        player.preventsDisplaySleepDuringVideoPlayback = true

        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true

        // tvOS-specific: rich info overlay shown when user swipes down during playback.
        let info = AVMutableMetadataItem()
        info.identifier = .commonIdentifierTitle
        info.value = item.title as NSString
        info.locale = Locale.current

        if let subtitle = item.subtitle {
            let sub = AVMutableMetadataItem()
            sub.identifier = .iTunesMetadataTrackSubTitle
            sub.value = subtitle as NSString
            sub.locale = Locale.current
            vc.player?.currentItem?.externalMetadata = [info, sub]
        } else {
            vc.player?.currentItem?.externalMetadata = [info]
        }

        context.coordinator.player = player
        context.coordinator.onDismiss = onDismiss

        MKSLog.player.info("TVPlayer load url=\(item.url) kind=\(String(describing: item.kind))")
        player.play()

        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Item is immutable per cover presentation — no updates needed.
    }

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.player?.pause()
        vc.player = nil
        coordinator.player = nil
        MKSLog.player.info("TVPlayer dismantled")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
        var onDismiss: (() -> Void)?
    }
}
