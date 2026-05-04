import SwiftUI
import AVFoundation
import IPTVCore

// MARK: - Player Debug Overlay

/// Toggleable overlay showing live AVPlayer metrics during development.
/// Displays buffer levels, bitrate, stall count, playback state, and glitch detection.
///
/// Toggle via `UserDefaults.showPlayerDebugOverlay` or triple-tap on the player surface.
/// Compiled in all builds but only visible when the setting is enabled.
struct PlayerDebugOverlay: View {
    let player: any VideoPlayerProtocol
    @State private var metrics = PlayerBufferingDetail.idle
    @State private var currentTimeSec: Double = 0
    @State private var glitchSummary: GlitchSessionSummary?
    @State private var recentGlitches: [GlitchEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text("DEBUG")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                if let summary = glitchSummary {
                    glitchBadge(summary)
                }
            }

            Divider()
                .background(.white.opacity(0.2))

            // Metrics section
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

            // Glitch section (if any glitches detected)
            if let summary = glitchSummary, summary.totalEvents > 0 {
                Divider()
                    .background(.white.opacity(0.2))

                Text("GLITCHES")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                // Glitch counts by type
                glitchCounts(summary)

                // Recent glitches
                if !recentGlitches.isEmpty {
                    ForEach(recentGlitches.prefix(3)) { glitch in
                        glitchRow(glitch)
                    }
                }
            }
        }
        .padding(8)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 8))
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            metrics = player.bufferingDetail
            currentTimeSec = player.currentTime
            Task {
                await fetchGlitchData()
            }
        }
    }

    // MARK: - Glitch Views

    @ViewBuilder
    private func glitchBadge(_ summary: GlitchSessionSummary) -> some View {
        let color: Color = if summary.criticalCount > 0 {
            .red
        } else if summary.warningCount > 0 {
            .orange
        } else {
            .green
        }

        HStack(spacing: 2) {
            if summary.criticalCount > 0 {
                Text("ERR:\(summary.criticalCount)")
                    .foregroundStyle(.red)
            }
            if summary.warningCount > 0 {
                Text("WRN:\(summary.warningCount)")
                    .foregroundStyle(.orange)
            }
            if summary.infoCount > 0 {
                Text("INF:\(summary.infoCount)")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 8, weight: .medium, design: .monospaced))
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func glitchCounts(_ summary: GlitchSessionSummary) -> some View {
        let types = summary.countsByType.sorted { $0.key.rawValue < $1.key.rawValue }
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
            ForEach(types.prefix(6), id: \.key) { type, count in
                HStack(spacing: 2) {
                    Circle()
                        .fill(severityColor(type.severity))
                        .frame(width: 6, height: 6)
                    Text("\(type.rawValue):\(count)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func glitchRow(_ glitch: GlitchEvent) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(severityColor(glitch.severity))
                .frame(width: 6, height: 6)
            Text(glitch.type.rawValue)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
            Text("@\(String(format: "%.1f", glitch.currentTime))s")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(glitch.message)
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
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

    private func severityColor(_ severity: GlitchSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .white.opacity(0.6)
        }
    }

    private func fetchGlitchData() async {
        // Access the glitch detector from the player implementation
        if let avImpl = player as? AVPlayerImplementation {
            self.recentGlitches = await avImpl.recentGlitchEvents(limit: 5)
            self.glitchSummary = await avImpl.glitchSessionSummary()
        } else if let ffmpegImpl = player as? FFmpegPlayerImplementation {
            // FFmpegPlayerImplementation delegates to AVPlayerImplementation internally
            // Access its internal avPlayer property
            if let innerAVPlayer = ffmpegImpl.innerAVPlayer {
                self.recentGlitches = await innerAVPlayer.recentGlitchEvents(limit: 5)
                self.glitchSummary = await innerAVPlayer.glitchSessionSummary()
            }
        }
    }
}

// MARK: - FFmpegPlayerImplementation Extension

extension FFmpegPlayerImplementation {
    /// Access the inner AVPlayerImplementation for glitch data.
    var innerAVPlayer: AVPlayerImplementation? {
        // Use Mirror to access the private avPlayer property
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "avPlayer", let avImpl = child.value as? AVPlayerImplementation {
                return avImpl
            }
        }
        return nil
    }
}
