//
//  RemotePlayOverlay.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Overlay view for casting playback state
//

import SwiftUI

/// Minimal overlay that appears during casting to show device name,
/// playback controls (play/pause/seek, volume), current position/progress.
struct RemotePlayOverlay: View {

    // MARK: - Environment

    @Environment(RemotePlayManager.self) private var remotePlayManager

    // MARK: - State

    @State private var isDragging = false
    @State private var dragProgress: Double = 0

    /// Pending volume value for debounced sending.
    @State private var pendingVolume: Float?
    @State private var volumeDebounceTask: Task<Void, Never>?

    // MARK: - Computed Properties

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

    private var displayTime: Double {
        isDragging ? dragProgress * duration : currentTime
    }

    private var volume: Float {
        remotePlayManager.deviceState?.volume ?? 1.0
    }

    private var isMuted: Bool {
        remotePlayManager.deviceState?.isMuted ?? false
    }

    // MARK: - Body

    var body: some View {
        if isConnected {
            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Device info header
                HStack {
                    Image(systemName: remotePlayManager.connectedDevice?.type.icon ?? "tv.fill")
                        .foregroundStyle(remotePlayManager.connectedDevice?.type.accentColor ?? .green)
                    Text("Playing on \(deviceName ?? "Device")")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task {
                            await remotePlayManager.disconnect()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)

                Divider()

                // Playback controls
                VStack(spacing: 16) {
                    // Progress bar with seek gesture
                    VStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 4)

                                // Progress
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(width: geometry.size.width * progress, height: 4)

                                // Seek thumb (visible during drag)
                                if isDragging {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 12, height: 12)
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

                        // Time labels
                        HStack {
                            Text(formatTime(displayTime))
                                .font(.caption)
                                .monospacedDigit()
                            Spacer()
                            Text(formatTime(duration))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Play/Pause controls
                    HStack(spacing: 40) {
                        // Rewind 15s
                        Button {
                            Task {
                                let newTime = max(0, currentTime - 15)
                                try? await remotePlayManager.seek(to: newTime)
                            }
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)

                        // Play/Pause
                        Button {
                            Task {
                                if isPlaying {
                                    try? await remotePlayManager.pause()
                                } else {
                                    try? await remotePlayManager.play()
                                }
                            }
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.largeTitle)
                                .frame(width: 64, height: 64)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        // Forward 15s
                        Button {
                            Task {
                                let newTime = min(duration, currentTime + 15)
                                try? await remotePlayManager.seek(to: newTime)
                            }
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)

                    // Volume control with debounce
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                try? await remotePlayManager.setMuted(!isMuted)
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.body)
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { volume },
                            set: { newVolume in
                                debouncedSetVolume(newVolume)
                            }
                        ))
                        .frame(maxWidth: 150)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            }
            #if os(iOS)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .shadow(radius: 10)
            .padding()
            #else
            .frame(width: 320)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .shadow(radius: 8)
            #endif
        }
    }

    // MARK: - Helpers

    /// Debounce volume changes — only sends SOAP request after 250ms of no changes.
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

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.5)
            .ignoresSafeArea()

        RemotePlayOverlay()
    }
    .environment(RemotePlayManager.shared)
}
