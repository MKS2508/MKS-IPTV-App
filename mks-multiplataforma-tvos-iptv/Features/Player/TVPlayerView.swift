//
//  TVPlayerView.swift
//  mks-multiplataforma-tvos-iptv
//
//  AVPlayerViewController-based player for tvOS with the full TransmuxCore
//  pipeline for VOD. Native scrub, info overlay, focus, AirPlay, PiP.
//
//  - VOD (movies, episodes): source URL → TransmuxingService → fMP4 + HLS
//    playlist served by TransmuxServer → AVPlayer plays the local HLS URL.
//    Required because the IPTV catalog is MKV/AVI, which AVPlayer can't
//    consume natively.
//  - LIVE: m3u8 URL piped directly to AVPlayer (HLS is native).
//

import SwiftUI
import AVKit
import IPTVCore
import TransmuxCore

// MARK: - PlayableItem

struct PlayableItem: Equatable, Identifiable {
    enum Kind: Equatable {
        case vod          // movies, series episodes (transmuxed)
        case live         // live channels (HLS, no transmux)
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

// MARK: - TVPlayerView

struct TVPlayerView: View {
    let item: PlayableItem
    let onDismiss: () -> Void

    @StateObject private var pipeline = PlaybackPipeline()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch pipeline.state {
            case .idle, .preparing(_):
                preparing
            case .ready(let url):
                TVPlayerControllerHost(item: item, playbackURL: url, onExit: onDismiss)
                    .ignoresSafeArea()
            case .failed(let message):
                failed(message)
            }
        }
        .task {
            await pipeline.prepare(for: item)
        }
        .onDisappear {
            Task { await pipeline.tearDown() }
        }
    }

    private var preparing: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2.0)
            Text(pipeline.statusMessage)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
            Text(item.title)
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 200)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 96))
                .foregroundStyle(.orange)
            Text("Couldn't start playback")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 200)
            Button("Close") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PlaybackPipeline

@MainActor
final class PlaybackPipeline: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing(String)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var transmuxSessionID: String?

    var statusMessage: String {
        if case .preparing(let message) = state { return message }
        return "Preparing…"
    }

    func prepare(for item: PlayableItem) async {
        guard case .idle = state else { return }

        switch item.kind {
        case .live:
            await prepareLive(item)
        case .vod:
            await prepareVOD(item)
        }
    }

    func tearDown() async {
        if let sessionID = transmuxSessionID {
            MKSLog.player.info("Player teardown — cancelling transmux session \(sessionID)")
            await TransmuxingService.shared.cancelTransmux(sessionID: sessionID)
            await TransmuxServer.shared.stop()
            await TransmuxingService.shared.cleanup(sessionID: sessionID)
            transmuxSessionID = nil
        }
        state = .idle
    }

    // MARK: - Live (no transmux)

    private func prepareLive(_ item: PlayableItem) async {
        MKSLog.player.info("Live prepare url=\(item.url)")
        state = .preparing("Connecting…")
        state = .ready(item.url)
    }

    // MARK: - VOD (transmux pipeline)

    private func prepareVOD(_ item: PlayableItem) async {
        let sourceURL = item.url
        MKSLog.player.info("VOD prepare url=\(sourceURL)")

        state = .preparing("Checking stream…")
        let preflight = await StreamPreflight.check(url: sourceURL)
        guard preflight.isReachable else {
            let msg = "Stream unreachable (HTTP \(preflight.httpStatus ?? -1)) — \(preflight.error ?? "unknown")"
            MKSLog.player.error("VOD preflight failed: \(msg)")
            state = .failed(msg)
            return
        }

        state = .preparing("Starting transmux…")
        do {
            let session = try await TransmuxingService.shared.startTransmux(from: sourceURL)
            transmuxSessionID = session.sessionID
            MKSLog.player.info("Transmux started session=\(session.sessionID) expectedSize=\(session.expectedSize)")

            var effectiveSize = session.expectedSize
            if effectiveSize <= 0, let preflightSize = preflight.contentLength, preflightSize > 0 {
                effectiveSize = preflightSize
            }

            state = .preparing("Starting HTTP server…")
            let serverSession = try await TransmuxServer.shared.start(
                filePath: session.outputPath,
                playlistPath: session.playlistPath,
                mediaPlaylistPath: session.mediaPlaylistPath,
                expectedSize: effectiveSize,
                segmenter: session.segmenter,
                initSegmentSize: session.initSegmentSize,
                seekHandle: session.seekHandle
            )

            MKSLog.player.info("Server ready local=\(serverSession.localURL)")
            state = .ready(serverSession.localURL)
        } catch {
            MKSLog.player.error("VOD transmux failed: \(error)")
            state = .failed("\(error.localizedDescription)")
        }
    }
}

// MARK: - UIViewControllerRepresentable

private struct TVPlayerControllerHost: UIViewControllerRepresentable {
    let item: PlayableItem
    let playbackURL: URL
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let player = AVPlayer(url: playbackURL)
        player.preventsDisplaySleepDuringVideoPlayback = true
        if item.kind == .live {
            player.automaticallyWaitsToMinimizeStalling = false
        }

        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true

        var metadata: [AVMetadataItem] = []
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = item.title as NSString
        titleItem.locale = Locale.current
        metadata.append(titleItem)

        if let subtitle = item.subtitle {
            let sub = AVMutableMetadataItem()
            sub.identifier = .iTunesMetadataTrackSubTitle
            sub.value = subtitle as NSString
            sub.locale = Locale.current
            metadata.append(sub)
        }
        vc.player?.currentItem?.externalMetadata = metadata

        context.coordinator.player = player
        MKSLog.player.info("TVPlayer load url=\(playbackURL) kind=\(String(describing: item.kind))")
        player.play()

        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.player?.pause()
        vc.player = nil
        coordinator.player = nil
        MKSLog.player.info("TVPlayer dismantled")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var player: AVPlayer?
    }
}
