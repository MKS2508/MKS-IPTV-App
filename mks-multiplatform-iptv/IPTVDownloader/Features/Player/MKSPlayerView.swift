import SwiftUI
import AVKit
import MediaPlayer
import IPTVCore

// MARK: - Presentation Mode

enum MKSPlayerPresentationMode {
    case inline
    case fullscreen
}

// MARK: - MKSPlayerView

struct MKSPlayerView: View {
    let player: any VideoPlayerProtocol
    var title: String = ""
    var metadata: MetadataResult? = nil
    var onDismiss: (() -> Void)?
    var onRequestFullscreen: (() -> Void)?
    var presentationMode: MKSPlayerPresentationMode = .inline
    var controlsConfiguration: PlayerControlsConfiguration = .glass

    /// Auto-play next episode support — set from PlaybackTracker
    var nextEpisodeInfo: NextEpisodeInfo?
    var onPlayNextEpisode: ((SerieDetail.Episode) -> Void)?
    var onCancelAutoPlay: (() -> Void)?

    @Environment(RemotePlayManager.self) private var remotePlayManager

    var showMetadata: Bool = true
    @State private var showDebugOverlay = UserDefaults.showPlayerDebugOverlay
    @State private var wasPlayingBeforeCast = false
    @State private var didLoadOnCastDevice = false
    @State private var videoGravity: PlayerVideoGravity = .resizeAspect
    @State private var controlsVisible: Bool = true

    // macOS overlay state removed — native overlays use contentOverlayView,
    // glass overlays use PlayerOverlayContainer's own visibility management.

    private var useNativeControls: Bool {
        controlsConfiguration.mode == .native
    }

    /// True when fullscreen on ANY platform — most SwiftUI overlays should not
    /// exist above the native player view. On macOS this avoids the NSViewRepresentable
    /// blocking bug (FB9818366); on iOS/tvOS this lets AVPlayerViewController own
    /// the entire UI with its native controls, PiP, and metadata.
    private var isNativeFullscreen: Bool {
        presentationMode == .fullscreen
    }

    /// True when fullscreen Cast/DLNA is handled inside the native player view.
    /// macOS: actionPopUpButtonMenu gear icon.
    /// tvOS: transportBarCustomMenuItems.
    /// iOS: RemotePlayButton embedded in AVPlayerViewController.contentOverlayView.
    /// In all cases the SwiftUI floating RemotePlayButton overlay is unnecessary.
    private var platformHandlesCastNatively: Bool {
        presentationMode == .fullscreen
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // MARK: - Layer 0: Player surface (video layer)
            playerSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            // MARK: - Layer 1: Debug overlay (top-left, non-blocking)
            // Hidden in native fullscreen — let the system player own the UI.
            if showDebugOverlay, !isNativeFullscreen {
                VStack {
                    HStack {
                        PlayerDebugOverlay(player: player)
                        Spacer()
                    }
                }
                .padding(8)
                .allowsHitTesting(false)
            }

            // MARK: - Layer 2: Controls/conditional overlays
            if useNativeControls {
                nativeControlsOverlays
            } else {
                glassControlsOverlay
            }

            // MARK: - Layer 3: Top trailing buttons (individual, no full-screen wrapper)
            // Hidden only when the platform handles Cast natively (macOS gear menu, tvOS transport bar).
            // iOS has no native AVPlayerViewController Cast API, so the floating button stays visible.
            if showRemotePlayButton, !platformHandlesCastNatively {
                RemotePlayButton()
                    .buttonStyle(.plain)
                    .adaptiveGlass(in: Capsule())
                    .opacity(useNativeControls ? 1 : (controlsVisible ? 1 : 0))
                    .allowsHitTesting(useNativeControls || controlsVisible)
            }

            // MARK: - Layer 4: Casting overlay (replaces player surface when active)
            if remotePlayManager.connectedDevice != nil {
                castingOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // MARK: - Layer 5: Auto-play next episode overlay (bottom-right)
            if let nextInfo = nextEpisodeInfo, !isNativeFullscreen {
                AutoPlayNextOverlay(
                    info: nextInfo,
                    onPlayNow: { onPlayNextEpisode?(nextInfo.episode) },
                    onCancel: { onCancelAutoPlay?() }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: nextEpisodeInfo?.episode.id)
            }
        }
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                // Only manage controlsVisible for inline glass controls.
                // Fullscreen uses native controls exclusively.
                if !isNativeFullscreen, !useNativeControls {
                    controlsVisible = true
                }
            case .ended:
                break
            }
        }
        #endif
        .onChange(of: remotePlayManager.connectedDevice?.id) { oldId, newId in
            if newId != nil, oldId == nil {
                handleCastConnected()
            } else if newId == nil, oldId != nil {
                handleCastDisconnected()
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .onAppear {
            remotePlayManager.ensureDiscoveryActive()
        }
        .onDisappear {
            // Stop RemotePlay when player view is dismissed to prevent
            // leaked polling tasks, transmux monitors, and SOAP calls.
            if didLoadOnCastDevice || remotePlayManager.connectedDevice != nil {
                Task {
                    await remotePlayManager.disconnect()
                }
            }
        }
    }

    // MARK: - Player Surface

    @ViewBuilder
    private var playerSurface: some View {
        switch presentationMode {
        case .fullscreen:
            ReactiveFullscreenSurface(
                player: player,
                title: title,
                metadata: metadata,
                onDismiss: onDismiss,
                videoGravity: videoGravity.avGravity,
                remoteDevices: remotePlayManager.discoveredDevices,
                connectedDevice: remotePlayManager.connectedDevice,
                onDeviceSelected: { device in
                    Task {
                        try? await remotePlayManager.connect(to: device)
                    }
                },
                onDisconnect: {
                    Task {
                        await remotePlayManager.disconnect()
                    }
                },
                onCopyStreamURL: {
                    #if os(macOS)
                    if let url = player.sourceURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    #endif
                },
                onRefreshDevices: {
                    remotePlayManager.refreshDiscovery()
                }
            )

        case .inline:
            player.playerView()
        }
    }

    // MARK: - Native Controls Overlays

    @ViewBuilder
    private var nativeControlsOverlays: some View {
        // Native mode: inline overlays only.
        // Fullscreen: native player owns UI on all platforms.
        if presentationMode == .inline {
            if let metadata, showMetadata {
                GlassMetadataOverlay(metadata: metadata)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if metadata == nil, !title.isEmpty {
                titleBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
            }

            if onRequestFullscreen != nil {
                fullscreenButton
            }
        }
    }

    // MARK: - Glass Controls Overlay

    @ViewBuilder
    private var glassControlsOverlay: some View {
        // Glass controls only for inline mode.
        // Fullscreen uses native player controls on all platforms.
        let showGlassControls = presentationMode == .inline

        if showGlassControls {
            if let metadata, showMetadata {
                GlassMetadataOverlay(metadata: metadata)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.25), value: controlsVisible)
            }

            PlayerOverlayContainer(
                player: player,
                configuration: controlsConfiguration,
                isVisible: $controlsVisible,
                metadata: showMetadata ? metadata : nil,
                onFullscreenRequest: onRequestFullscreen,
                onDismiss: onDismiss,
                onGravityChange: { newGravity in
                    videoGravity = newGravity
                }
            )
        }
    }

    // MARK: - Show Remote Play Button

    private var showRemotePlayButton: Bool {
        true
    }

    // MARK: - Title Bar

    @ViewBuilder
    private var titleBar: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let onDismiss {
                Button("Close", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Dismiss Button

    @ViewBuilder
    private func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Fullscreen Button

    @ViewBuilder
    private var fullscreenButton: some View {
        Button(action: { onRequestFullscreen?() }) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
        }
        .adaptiveGlass(in: Circle())
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    // MARK: - Casting Overlay

    private var castingOverlay: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "tv.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                if let deviceName = remotePlayManager.connectedDevice?.name {
                    Text("Casting to \(deviceName)")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.white)
                }

                if !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                GlassRemotePlayOverlay()

                Spacer()
            }
        }
    }

    // MARK: - Event Handlers

    private func handleCastConnected() {
        guard let sourceURL = player.sourceURL else {
            MKSLog.dlna.warning("No sourceURL on player — cannot auto-load on Cast device")
            return
        }

        MKSLog.dlna.info("handleCastConnected — sourceURL=\(sourceURL.absoluteString)")
        MKSLog.dlna.debug("handleCastConnected — player.isPlaying=\(player.isPlaying), player.currentTime=\(player.currentTime)")
        MKSLog.dlna.debug("handleCastConnected — device transport=\(remotePlayManager.connectedDevice?.effectiveTransport.rawValue ?? "nil")")

        wasPlayingBeforeCast = player.isPlaying
        didLoadOnCastDevice = true

        let startPosition = player.currentTime

        // Pause local playback — audio should come from the TV, not the Mac
        if player.isPlaying {
            player.pause()
            MKSLog.dlna.info("Local player paused before cast handoff")
        }

        Task {
            do {
                // Use transmux pipeline: FFmpeg remuxes the source to MPEG-TS/HLS,
                // TransmuxServer serves it over HTTP, TV gets a LAN URL with
                // compatible content instead of raw MKV from the IPTV server.
                MKSLog.dlna.info("Starting loadWithTransmux...")
                try await remotePlayManager.loadWithTransmux(
                    url: sourceURL,
                    metadata: metadata,
                    startPosition: startPosition
                )
                MKSLog.dlna.info("Content transmuxed and loaded on device at position \(String(format: "%.1f", startPosition))s")
            } catch {
                MKSLog.dlna.error("Failed to load on device: \(error)")
                didLoadOnCastDevice = false
                // Resume local playback on failure
                if wasPlayingBeforeCast {
                    player.play()
                    MKSLog.dlna.info("Resumed local playback after cast failure")
                }
            }
        }
    }

    private func handleCastDisconnected() {
        guard didLoadOnCastDevice else { return }
        didLoadOnCastDevice = false

        let castPosition = remotePlayManager.deviceState?.currentTime ?? player.currentTime

        if castPosition > 0 {
            player.seek(to: castPosition)
        }

        if wasPlayingBeforeCast {
            player.play()
        }
    }

}

// MARK: - GlassMetadataOverlay

struct GlassMetadataOverlay: View {
    let metadata: MetadataResult

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let year = metadata.year {
                        Text(String(year))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()

                if let rating = metadata.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .adaptiveGlass(in: Capsule(), fallbackOpacity: 0.5)
                }
            }

            HStack(spacing: 12) {
                if let director = metadata.director, !director.isEmpty {
                    Label(director, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }

                if !metadata.genre.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(metadata.genre.prefix(3), id: \.self) { genre in
                            Text(genre)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .adaptiveGlass(in: Capsule(), fallbackOpacity: 0.3)
                        }
                    }
                }
            }

            if let plot = metadata.plot, !plot.isEmpty {
                Text(plot)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius), fallbackOpacity: 0.75)
    }
}

// MARK: - GlassRemotePlayOverlay

struct GlassRemotePlayOverlay: View {
    @Environment(RemotePlayManager.self) private var remotePlayManager

    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var pendingVolume: Float?
    @State private var volumeDebounceTask: Task<Void, Never>?

    private var isConnected: Bool {
        remotePlayManager.connectedDevice != nil
    }

    private var deviceName: String? {
        remotePlayManager.connectedDevice?.name
    }

    private var isPlaying: Bool {
        remotePlayManager.deviceState?.isPlaying ?? false
    }

    private var currentTime: Double {
        remotePlayManager.deviceState?.currentTime ?? 0
    }

    private var duration: Double {
        remotePlayManager.deviceState?.duration ?? 0
    }

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return isDragging ? dragProgress : (currentTime / duration)
    }

    private var volume: Float {
        remotePlayManager.deviceState?.volume ?? 1.0
    }

    private var isMuted: Bool {
        remotePlayManager.deviceState?.isMuted ?? false
    }

    var body: some View {
        if isConnected {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                HStack {
                    Image(systemName: remotePlayManager.connectedDevice?.type.icon ?? "tv.fill")
                        .foregroundStyle(remotePlayManager.connectedDevice?.type.accentColor ?? .green)
                    Text("Playing on \(deviceName ?? "Device")")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        Task {
                            await remotePlayManager.disconnect()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 14)

                Divider()
                    .background(.white.opacity(0.2))

                VStack(spacing: 16) {
                    castSeekBar

                    HStack(spacing: 40) {
                        castSkipButton(direction: .backward)
                        castPlayPauseButton
                        castSkipButton(direction: .forward)
                    }
                    .padding(.vertical, 8)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                try? await remotePlayManager.setMuted(!isMuted)
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { volume },
                            set: { newVolume in
                                debouncedSetVolume(newVolume)
                            }
                        ))
                        .frame(maxWidth: 150)
                        .tint(AppColors.accent)
                    }
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            }
            #if os(iOS)
            .frame(maxWidth: .infinity)
            #else
            .frame(width: 340)
            #endif
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 16), fallbackOpacity: 0.85)
            .shadow(color: .black.opacity(0.3), radius: 20)
            .padding()
        }
    }

    // MARK: - Cast Seek Bar

    @ViewBuilder
    private var castSeekBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.accent)
                        .frame(width: geometry.size.width * progress, height: 4)

                    if isDragging {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().fill(AppColors.accent).frame(width: 8, height: 8))
                            .offset(x: geometry.size.width * progress - 6)
                    }
                }
                .contentShape(Rectangle().size(width: geometry.size.width, height: 24))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = max(0, min(1, value.location.x / geometry.size.width))
                            dragProgress = fraction
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / geometry.size.width))
                            let seekTime = fraction * duration
                            isDragging = false
                            Task {
                                try? await remotePlayManager.seek(to: seekTime)
                            }
                        }
                )
            }
            .frame(height: 12)

            HStack {
                Text(PlayerTimeInfo.formatTime(currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(PlayerTimeInfo.formatTime(duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Cast Skip Buttons

    @ViewBuilder
    private func castSkipButton(direction: SkipDirection) -> some View {
        Button {
            Task {
                let interval: Double = 15
                let newTime = direction == .forward
                    ? min(duration, currentTime + interval)
                    : max(0, currentTime - interval)
                try? await remotePlayManager.seek(to: newTime)
            }
        } label: {
            Image(systemName: direction == .forward ? "goforward.15" : "gobackward.15")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cast Play/Pause Button

    @ViewBuilder
    private var castPlayPauseButton: some View {
        Button {
            Task {
                if isPlaying {
                    try? await remotePlayManager.pause()
                } else {
                    try? await remotePlayManager.play()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 64, height: 64)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func debouncedSetVolume(_ newVolume: Float) {
        pendingVolume = newVolume
        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let volume = pendingVolume else { return }
            try? await remotePlayManager.setVolume(volume)
            pendingVolume = nil
        }
    }

    private enum SkipDirection {
        case forward, backward
    }
}

// MARK: - ReactiveFullscreenSurface

private struct ReactiveFullscreenSurface: View {
    let player: any VideoPlayerProtocol
    var title: String = ""
    var metadata: MetadataResult? = nil
    var onDismiss: (() -> Void)?
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    // MARK: - Remote Play (native transport bar integration)
    // macOS: actionPopUpButtonMenu gear icon
    // iOS: transportBarCustomMenuItems in AVPlayerViewController

    var remoteDevices: [RemoteDevice] = []
    var connectedDevice: RemoteDevice? = nil
    var onDeviceSelected: ((RemoteDevice) -> Void)? = nil
    var onDisconnect: (() -> Void)? = nil
    var onCopyStreamURL: (() -> Void)? = nil
    var onRefreshDevices: (() -> Void)? = nil

    @State private var avPlayer: AVPlayer?
    @State private var didSetupMetadata = false
    @State private var didSetDuration = false

    var body: some View {
        Group {
            if let avPlayer {
                #if os(iOS) || os(tvOS)
                NativeAVPlayerViewController(
                    player: avPlayer,
                    onDismiss: onDismiss,
                    videoGravity: videoGravity,
                    remoteDevices: remoteDevices,
                    connectedDevice: connectedDevice,
                    onDeviceSelected: onDeviceSelected,
                    onDisconnect: onDisconnect,
                    onRefreshDevices: onRefreshDevices
                )
                #elseif os(macOS)
                NativeAVPlayerView(
                    player: avPlayer,
                    videoGravity: videoGravity,
                    controlsStyle: .floating,
                    remoteDevices: remoteDevices,
                    connectedDevice: connectedDevice,
                    onDeviceSelected: onDeviceSelected,
                    onDisconnect: onDisconnect,
                    onCopyStreamURL: onCopyStreamURL,
                    onRefreshDevices: onRefreshDevices
                )
                #endif
            } else {
                player.playerView()
            }
        }
        .onAppear {
            avPlayer = player.underlyingAVPlayer
            applyMetadataIfNeeded()
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if avPlayer == nil {
                avPlayer = player.underlyingAVPlayer
            }
            applyMetadataIfNeeded()
            updateDurationIfNeeded()
        }
        .onDisappear {
            PlayerMetadataHelper.teardownRemoteTransportControls()
            PlayerMetadataHelper.clearNowPlayingInfo()
        }
    }

    private func applyMetadataIfNeeded() {
        guard !didSetupMetadata, let avPlayer else { return }
        didSetupMetadata = true

        let playerRef = player
        let displayTitle = metadata?.title ?? title

        PlayerMetadataHelper.setupRemoteTransportControls(
            onPlay: { playerRef.play() },
            onPause: { playerRef.pause() },
            onToggle: {
                if playerRef.isPlaying { playerRef.pause() } else { playerRef.play() }
            },
            onSeek: { position in playerRef.seek(to: position) }
        )

        if let metadata {
            let dur = avPlayer.currentItem?.duration.seconds ?? 0
            PlayerMetadataHelper.setNowPlayingInfo(
                from: metadata,
                duration: dur.isFinite ? dur : 0,
                currentTime: avPlayer.currentTime().seconds
            )
            PlayerMetadataHelper.loadArtwork(from: metadata)

            #if os(iOS) || os(tvOS) || os(visionOS)
            if let item = avPlayer.currentItem {
                item.externalMetadata = PlayerMetadataHelper.buildExternalMetadata(from: metadata)
                PlayerMetadataHelper.loadExternalArtwork(for: item, from: metadata)
            }
            #endif
        } else if !displayTitle.isEmpty {
            var info: [String: Any] = [
                MPMediaItemPropertyTitle: displayTitle,
                MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
                MPNowPlayingInfoPropertyPlaybackRate: 1.0
            ]
            let dur = avPlayer.currentItem?.duration.seconds ?? 0
            if dur.isFinite && dur > 0 {
                info[MPMediaItemPropertyPlaybackDuration] = dur
                didSetDuration = true
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            MPNowPlayingInfoCenter.default().playbackState = .playing

            #if os(iOS) || os(tvOS) || os(visionOS)
            if let item = avPlayer.currentItem {
                item.externalMetadata = PlayerMetadataHelper.buildTitleOnlyMetadata(title: displayTitle)
            }
            #endif
        }
    }

    private func updateDurationIfNeeded() {
        guard !didSetDuration, let avPlayer else { return }
        let dur = avPlayer.currentItem?.duration.seconds ?? 0
        guard dur.isFinite && dur > 0 else { return }
        didSetDuration = true

        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPMediaItemPropertyPlaybackDuration] = dur
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = avPlayer.currentTime().seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - Extensions

extension MKSPlayerView {
    func controlsMode(_ mode: PlayerControlsMode) -> Self {
        var copy = self
        copy.controlsConfiguration = PlayerControlsConfiguration(mode: mode)
        return copy
    }

    func controlsConfiguration(_ config: PlayerControlsConfiguration) -> Self {
        var copy = self
        copy.controlsConfiguration = config
        return copy
    }
}

// MARK: - Previews

#Preview("Native Controls") {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("Native Controls Preview")
            .foregroundStyle(.white)
    }
}

#Preview("Glass Controls") {
    ZStack {
        Color.black.ignoresSafeArea()
        Text("Glass Controls Preview")
            .foregroundStyle(.white)
    }
}
