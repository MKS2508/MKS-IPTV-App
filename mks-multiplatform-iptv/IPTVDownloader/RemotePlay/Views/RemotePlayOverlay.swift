import SwiftUI
import IPTVCore

struct RemotePlayOverlay: View {
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

    private var canSeek: Bool {
        remotePlayManager.connectedDevice?.capabilities.contains(.seeking) ?? false
    }

    private var canPause: Bool {
        remotePlayManager.connectedDevice?.capabilities.contains(.pause) ?? false
    }
    
    var body: some View {
        if isConnected {
            VStack(spacing: 0) {
                dragHandle
                deviceHeader
                divider
                playbackControls
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
    
    @ViewBuilder
    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }
    
    @ViewBuilder
    private var deviceHeader: some View {
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
    }
    
    @ViewBuilder
    private var divider: some View {
        Divider()
            .background(.white.opacity(0.2))
    }
    
    @ViewBuilder
    private var playbackControls: some View {
        VStack(spacing: 16) {
            if canSeek {
                seekBar
            } else {
                timeLabels
                    .padding(.horizontal)
            }
            mainControls
            volumeControl
        }
        .padding(.vertical, 16)
        .animation(.easeInOut(duration: 0.3), value: canSeek)
    }
    
    @ViewBuilder
    private var seekBar: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    trackView(width: geometry.size.width)
                    progressView(width: geometry.size.width)
                    thumbView(width: geometry.size.width)
                }
                .frame(height: 4)
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
            
            timeLabels
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private func trackView(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(width: width, height: 4)
    }
    
    @ViewBuilder
    private func progressView(width: CGFloat) -> some View {
        Capsule()
            .fill(AppColors.accent)
            .frame(width: width * progress, height: 4)
    }
    
    @ViewBuilder
    private func thumbView(width: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 8, height: 8)
            )
            .offset(x: width * progress - 6)
            .scaleEffect(isDragging ? 1.3 : 1.0)
            .animation(.spring(response: 0.15), value: isDragging)
    }
    
    @ViewBuilder
    private var timeLabels: some View {
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
    
    @ViewBuilder
    private var mainControls: some View {
        HStack(spacing: 40) {
            if canSeek {
                skipButton(direction: .backward)
            }
            playPauseButton
            if canSeek {
                skipButton(direction: .forward)
            }
        }
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.3), value: canSeek)
    }
    
    @ViewBuilder
    private func skipButton(direction: SkipDirection) -> some View {
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
    
    @ViewBuilder
    private var playPauseButton: some View {
        Button {
            Task {
                if isPlaying {
                    guard canPause else { return }
                    try? await remotePlayManager.pause()
                } else {
                    try? await remotePlayManager.play()
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPlaying && !canPause ? AppColors.accent.opacity(0.4) : AppColors.accent)
                    .frame(width: 64, height: 64)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .offset(x: isPlaying ? 0 : 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isPlaying && !canPause)
        .scaleEffect(isPlaying ? 1.0 : 1.05)
        .animation(.spring(response: 0.25), value: isPlaying)
    }
    
    @ViewBuilder
    private var volumeControl: some View {
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

#Preview {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()
        
        RemotePlayOverlay()
    }
    .environment(RemotePlayManager.shared)
}
