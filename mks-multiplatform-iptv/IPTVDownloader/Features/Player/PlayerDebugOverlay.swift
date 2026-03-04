import SwiftUI
import AVFoundation

// MARK: - Player Debug Overlay

/// Toggleable overlay showing live AVPlayer metrics during development.
/// Displays buffer levels, bitrate, stall count, and playback state.
///
/// Toggle via `UserDefaults.showPlayerDebugOverlay` or triple-tap on the player surface.
/// Compiled in all builds but only visible when the setting is enabled.
struct PlayerDebugOverlay: View {
    let player: any VideoPlayerProtocol
    @State private var metrics = PlayerBufferingDetail.idle
    @State private var currentTimeSec: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DEBUG")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

            Group {
                metricRow("Buffer", "\(formatSeconds(metrics.loadedRangeAhead))s ahead")
                metricRow("Bitrate", formatBitrate(metrics.bitrate))
                metricRow("Stalls", "\(metrics.stallCount)")
                metricRow("Status", metrics.reason ?? (metrics.isBuffering ? "buffering" : "playing"))
                metricRow("Rate", String(format: "%.2f", metrics.playerRate ?? 0))
                metricRow("Time", "\(formatSeconds(currentTimeSec))s")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
        }
        .padding(8)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 8))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            metrics = player.bufferingDetail
            currentTimeSec = player.currentTime
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
        }
    }

    private func formatSeconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f", value)
    }

    private func formatBitrate(_ bps: Double?) -> String {
        guard let bps, bps > 0 else { return "—" }
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.0f kbps", bps / 1_000)
        }
        return String(format: "%.0f bps", bps)
    }
}
