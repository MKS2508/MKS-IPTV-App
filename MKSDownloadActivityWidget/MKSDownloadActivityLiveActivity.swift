#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct MKSDownloadActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // Lock Screen / Notification Banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Expanded

                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: statusIcon(context.state.status))
                        .font(.title2)
                        .foregroundStyle(statusColor(context.state.status))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(String(format: "%.0f%%", context.state.progress))
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(statusColor(context.state.status))
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        capsuleProgressBar(
                            progress: context.state.progress,
                            color: statusColor(context.state.status),
                            height: 4
                        )

                        HStack {
                            if context.state.speed > 0 {
                                Label(
                                    String(format: "%.1f MB/s", context.state.speed),
                                    systemImage: "speedometer"
                                )
                                .font(.caption2.monospacedDigit())
                            }

                            Spacer()

                            if context.state.totalBytes > 0 {
                                Text("\(formatBytes(context.state.bytesDownloaded)) / \(formatBytes(context.state.totalBytes))")
                                    .font(.caption2.monospacedDigit())
                            }

                            Spacer()

                            if context.state.eta > 0 && context.state.eta.isFinite {
                                Label(formatETA(context.state.eta), systemImage: "clock")
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

            } compactLeading: {
                // MARK: Compact Leading
                Image(systemName: statusIcon(context.state.status))
                    .foregroundStyle(statusColor(context.state.status))

            } compactTrailing: {
                // MARK: Compact Trailing
                Text(String(format: "%.0f%%", context.state.progress))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(statusColor(context.state.status))

            } minimal: {
                // MARK: Minimal — circular progress ring
                ZStack {
                    Circle()
                        .stroke(.quaternary, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(context.state.progress / 100.0))
                        .stroke(
                            statusColor(context.state.status),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
                .padding(2)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<DownloadActivityAttributes>) -> some View {
        VStack(spacing: 12) {
            // Title row
            HStack(spacing: 10) {
                Image(systemName: statusIcon(context.state.status))
                    .font(.title2)
                    .foregroundStyle(statusColor(context.state.status))

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text("\(context.attributes.mediaType) \u{2022} \(context.state.status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: "%.0f%%", context.state.progress))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(statusColor(context.state.status))
            }

            // Progress bar
            capsuleProgressBar(
                progress: context.state.progress,
                color: statusColor(context.state.status),
                height: 6
            )

            // Stats row
            HStack {
                if context.state.totalBytes > 0 {
                    Text("\(formatBytes(context.state.bytesDownloaded)) / \(formatBytes(context.state.totalBytes))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if context.state.speed > 0 {
                    Text(String(format: "%.1f MB/s", context.state.speed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if context.state.eta > 0 && context.state.eta.isFinite {
                    Text(formatETA(context.state.eta))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .activityBackgroundTint(.black.opacity(0.7))
        .activitySystemActionForegroundColor(.white)
    }

    // MARK: - Capsule Progress Bar

    @ViewBuilder
    private func capsuleProgressBar(progress: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)

                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * CGFloat(progress / 100.0)))
            }
        }
        .frame(height: height)
    }

    // MARK: - Helpers

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "Downloading": return "arrow.down.circle.fill"
        case "Paused": return "pause.circle.fill"
        case "Converting": return "gearshape.arrow.triangle.2.circlepath"
        case "Completed": return "checkmark.circle.fill"
        case "Failed": return "xmark.circle.fill"
        default: return "arrow.down.circle.fill"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Downloading": return .blue
        case "Paused": return .orange
        case "Converting": return .purple
        case "Completed": return .green
        case "Failed": return .red
        default: return .blue
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }
}
#endif
