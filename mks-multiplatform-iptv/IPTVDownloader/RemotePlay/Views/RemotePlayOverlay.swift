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
    @State private var dragOffset: CGFloat = 0

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
        return currentTime / duration
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
                    Image(systemName: "tv.fill")
                        .foregroundStyle(.green)
                    Text("Casting to \(deviceName ?? "Device")")
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
                    // Progress bar
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
                            }
                        }
                        .frame(height: 4)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    isDragging = true
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )

                        // Time labels
                        HStack {
                            Text(formatTime(currentTime))
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

                    // Volume control
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
                                Task {
                                    try? await remotePlayManager.setVolume(newVolume)
                                }
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
