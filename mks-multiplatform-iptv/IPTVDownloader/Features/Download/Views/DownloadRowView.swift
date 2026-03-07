import SwiftUI

struct AnimatedProgressText: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(String(format: "%.1f%%", progress))
            .font(.system(.subheadline, design: .monospaced))
            .foregroundColor(.primary)
            .contentTransition(.numericText(value: progress))
            .animation(.smooth(duration: 0.3, extraBounce: 0), value: progress)
    }
}

struct DownloadRowView: View {
    let item: DownloadItem
    let progress: Double
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var showMetadataPicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Circular progress indicator
            circularProgress
                .frame(width: 40, height: 40)

            // Content
            VStack(alignment: .leading, spacing: 5) {
                // Title row with action buttons
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    actionButtons
                }

                // Progress bar (for active states)
                if showsProgressBar {
                    capsuleProgressBar
                }

                // Stats row
                statsRow
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius))
        .contextMenu { contextMenuItems }
        .sheet(isPresented: $showMetadataPicker) {
            MetadataPickerView(
                downloadItem: item,
                onConfirm: { chosenMetadata in
                    downloadManager.writeMetadataForDownload(id: item.id, metadata: chosenMetadata)
                    showMetadataPicker = false
                },
                onDismiss: {
                    showMetadataPicker = false
                }
            )
        }
    }

    // MARK: - Circular Progress

    private var circularProgress: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 3)

            // Progress ring
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(statusAccentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.3), value: progressFraction)

            // Center icon
            statusCenterIcon
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(statusAccentColor)
        }
    }

    private var progressFraction: Double {
        switch item.status {
        case .completed, .downloaded:
            return 1.0
        case .converting:
            return 0.0 // Indeterminate — handled by animation
        case .notStarted:
            return 0.0
        default:
            return min(progress / 100.0, 1.0)
        }
    }

    @ViewBuilder
    private var statusCenterIcon: some View {
        switch item.status {
        case .notStarted:
            ProgressView()
                .scaleEffect(0.6)
        case .downloading:
            Image(systemName: "arrow.down")
        case .paused:
            Image(systemName: "pause.fill")
        case .downloaded:
            Image(systemName: "checkmark")
        case .converting:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark")
        case .cancelled:
            Image(systemName: "xmark")
        case .failed:
            Image(systemName: "exclamationmark")
        }
    }

    // MARK: - Capsule Progress Bar

    private var showsProgressBar: Bool {
        item.status == .downloading || item.status == .paused || item.status == .converting
    }

    private var capsuleProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                if item.status == .converting {
                    // Indeterminate shimmer
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [statusAccentColor.opacity(0.3), statusAccentColor, statusAccentColor.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * 0.3)
                } else {
                    Capsule()
                        .fill(statusAccentColor)
                        .frame(width: max(geo.size.width * CGFloat(progress / 100.0), 0))
                        .animation(.smooth(duration: 0.3), value: progress)
                }
            }
        }
        .frame(height: 4)
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        switch item.status {
        case .downloading:
            VStack(alignment: .leading, spacing: 3) {
                // Line 1: progress percentage + size
                HStack(spacing: 6) {
                    AnimatedProgressText(progress: progress)

                    if item.totalBytes > 0 {
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(formatBytes(item.bytesDownloaded) + " / " + formatBytes(item.totalBytes))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else if item.bytesDownloaded > 0 {
                        Text("\u{00B7}")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(formatBytes(item.bytesDownloaded))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                // Line 2: speed + ETA
                if item.speed > 0 || item.eta > 0 {
                    HStack(spacing: 6) {
                        if item.speed > 0 {
                            Text(String(format: "%.1f MB/s", item.speed))
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }

                        if item.speed > 0 && item.eta > 0 {
                            Text("\u{00B7}")
                                .foregroundStyle(.tertiary)
                                .font(.caption2)
                        }

                        if item.eta > 0 {
                            Text(formatETA(item.eta) + " left")
                                .foregroundStyle(.tertiary)
                                .font(.caption2)
                        }
                    }
                }
            }

        case .paused:
            HStack(spacing: 6) {
                Text("Paused")
                    .foregroundStyle(.orange)
                    .font(.caption.weight(.medium))

                if item.totalBytes > 0 {
                    Text("\u{00B7}")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    Text(formatBytes(item.bytesDownloaded) + " / " + formatBytes(item.totalBytes))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Spacer()
            }

        case .converting:
            HStack(spacing: 8) {
                Text("Converting...")
                    .foregroundStyle(.purple)
                    .font(.caption.weight(.medium))
                Spacer()
            }

        case .downloaded:
            HStack(spacing: 8) {
                Text("Downloaded — preparing conversion")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
            }

        case .completed:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Format badge
                    Text(item.outputFormat.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.accent.opacity(0.8), in: Capsule())

                    if item.totalBytes > 0 {
                        Text(formatBytes(item.totalBytes))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Spacer(minLength: 0)
                }

                metadataStatusBadge
            }

        case .failed:
            HStack(spacing: 6) {
                Text(item.errorMessage ?? "Download failed")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
            }

        case .cancelled:
            HStack {
                Text("Cancelled")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Spacer()
            }

        case .notStarted:
            HStack {
                Text("Preparing...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Spacer()
            }
        }

        // Metadata preview for completed downloads
        if item.status == .completed, let metadata = item.metadataResult {
            metadataPreview(metadata: metadata)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch item.status {
            case .downloading:
                Button { downloadManager.pauseDownload(id: item.id) } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)

                Button { downloadManager.cancelDownload(id: item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            case .paused:
                Button { downloadManager.resumeDownload(id: item.id) } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button { downloadManager.cancelDownload(id: item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            case .failed:
                Button { downloadManager.retryDownload(id: item.id) } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Button { downloadManager.removeDownload(id: item.id) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

            case .completed:
                #if os(macOS)
                if let filePath = item.filePath {
                    Button {
                        NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                #endif

            case .converting:
                // No actions during conversion
                EmptyView()

            default:
                EmptyView()
            }
        }
    }

    // MARK: - Status Color

    private var statusAccentColor: Color {
        switch item.status {
        case .downloading: return .accentColor
        case .paused: return .orange
        case .downloaded: return .green
        case .converting: return .purple
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .notStarted: return .secondary
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if item.status == .downloading {
            Button {
                downloadManager.pauseDownload(id: item.id)
            } label: {
                Label("Pause", systemImage: "pause.circle")
            }

            Button(role: .destructive) {
                downloadManager.cancelDownload(id: item.id)
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
        } else if item.status == .paused {
            Button {
                downloadManager.resumeDownload(id: item.id)
            } label: {
                Label("Resume", systemImage: "play.circle")
            }

            Button(role: .destructive) {
                downloadManager.cancelDownload(id: item.id)
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
        } else if item.status == .failed {
            Button {
                downloadManager.retryDownload(id: item.id)
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }

        if item.status == .completed {
            Divider()

            #if os(macOS)
            if let filePath = item.filePath {
                Button {
                    NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            #endif

            if !item.metadataCandidates.isEmpty {
                Button {
                    showMetadataPicker = true
                } label: {
                    Label("Choose & Edit Metadata", systemImage: "tag")
                }
            }

            if case .failed = item.metadataStatus {
                Button {
                    downloadManager.retryMetadata(id: item.id)
                } label: {
                    Label("Retry Metadata", systemImage: "arrow.clockwise")
                }
            }

            if let metadata = item.metadataResult, item.metadataStatus == .pending {
                Button {
                    downloadManager.writeMetadataForDownload(id: item.id, metadata: metadata)
                } label: {
                    Label("Write Tags Now", systemImage: "square.and.pencil")
                }
            }
        }

        if item.status == .completed || item.status == .cancelled || item.status == .failed {
            Divider()
            Button(role: .destructive) {
                downloadManager.removeDownload(id: item.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Metadata Status Badge

    @ViewBuilder
    private var metadataStatusBadge: some View {
        switch item.metadataStatus {
        case .enriching:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Enriching")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.15), in: Capsule())

        case .tagging:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Tagging")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.15), in: Capsule())

        case .completed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text("Tagged")
                    .font(.caption2)
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.15), in: Capsule())

        case .failed:
            Button { downloadManager.retryMetadata(id: item.id) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text("Retry")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)

        case .pending:
            if !item.metadataCandidates.isEmpty {
                Button { showMetadataPicker = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "tag")
                            .font(.caption2)
                        Text("Write")
                            .font(.caption2)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }

        case .skipped:
            EmptyView()
        }
    }

    // MARK: - Metadata Preview

    @ViewBuilder
    private func metadataPreview(metadata: MetadataResult) -> some View {
        HStack(spacing: 6) {
            if !metadata.genre.isEmpty {
                Text(metadata.genre.prefix(2).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.7), in: Capsule())
            }

            if let year = metadata.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.6), in: Capsule())
            }

            if let rating = metadata.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text(String(format: "%.1f", rating))
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.7), in: Capsule())
            }

            if let advisory = metadata.contentAdvisoryRating, !advisory.isEmpty {
                Text(advisory)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.6), in: Capsule())
            }
        }
    }

    // MARK: - Formatters

    private func formatETA(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}


#if DEBUG
struct DownloadRowView_Previews: PreviewProvider {
    static var previews: some View {
        let previewDownloadManager = PreviewDownloadManager()

        return ScrollView {
            VStack(spacing: 12) {
                DownloadRowView(
                    item: DownloadItem(id: UUID(), vodID: "1", title: "Not Started Download", type: .movie, status: .notStarted),
                    progress: 0
                )

                DownloadRowView(
                    item: DownloadItem(
                        id: UUID(), vodID: "2", title: "Downloading File",
                        type: .movie, status: .downloading,
                        totalBytes: 100_000_000, bytesDownloaded: 45_000_000,
                        progress: 45, speed: 2.5, eta: 120
                    ),
                    progress: 45
                )

                DownloadRowView(
                    item: DownloadItem(
                        id: UUID(), vodID: "3", title: "Paused Download",
                        type: .movie, status: .paused,
                        totalBytes: 100_000_000, bytesDownloaded: 60_000_000,
                        progress: 60
                    ),
                    progress: 60
                )

                DownloadRowView(
                    item: DownloadItem(
                        id: UUID(), vodID: "3b", title: "Converting MKV to MP4",
                        type: .movie, status: .converting
                    ),
                    progress: 0
                )

                DownloadRowView(
                    item: DownloadItem(
                        id: UUID(), vodID: "4", title: "Completed Download",
                        type: .movie, status: .completed,
                        totalBytes: 100_000_000, bytesDownloaded: 100_000_000,
                        progress: 100
                    ),
                    progress: 100
                )

                DownloadRowView(
                    item: DownloadItem(
                        id: UUID(), vodID: "6", title: "Failed Download",
                        type: .movie, status: .failed,
                        errorMessage: "Connection error"
                    ),
                    progress: 80
                )
            }
            .padding()
        }
        .environmentObject(previewDownloadManager as DownloadManager)
        .preferredColorScheme(.dark)
    }
}
#endif
