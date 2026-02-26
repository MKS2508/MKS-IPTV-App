import SwiftUI


struct AnimatedProgressText: View, Animatable {
    var progress: Double
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Text(String(format: "%.2f%%", progress))
            .font(.system(.subheadline, design: .monospaced))
            .foregroundColor(.primary)
            .contentTransition(.numericText(value: progress))
            .animation(.smooth(duration: 0.3, extraBounce: 0), value: progress)
    }
}

struct DownloadRowView: View {
    let item: DownloadItem
    let progress: Double  // Accept progress as a parameter
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var showMetadataPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                statusIcon
            }

            if item.status == .downloading || item.status == .paused {
                VStack(spacing: 8) {
                    // Linear progress with customization
                    ProgressView(value: progress, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: item.status == .paused ? .orange : .accentColor))
                        .frame(height: 10)
                        .background(Color.gray.opacity(0.2))  // Background for unfilled portion
                        .cornerRadius(5)

                    // Animated progress percentage display
                    HStack {
                        AnimatedProgressText(progress: progress)
                            .padding(.trailing, 8)

                        Spacer()
                        if item.totalBytes > 0 {
                            Text(String(format: "%.1f/%.1f MB", Double(item.bytesDownloaded) / 1_048_576, Double(item.totalBytes) / 1_048_576))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else if item.bytesDownloaded > 0 {
                            Text(String(format: "%.1f MB", Double(item.bytesDownloaded) / 1_048_576))
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            Text("Calculating size...")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }

                    if item.status == .downloading {
                        HStack {
                            if item.speed > 0 {
                                Label(String(format: "%.2f MB/s", item.speed), systemImage: "speedometer")
                            } else {
                                Label("Calculating...", systemImage: "speedometer")
                            }
                            Spacer()
                            if item.eta > 0 {
                                Label(formatETA(item.eta), systemImage: "clock")
                            } else {
                                Label("Estimating...", systemImage: "clock")
                            }
                        }
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }

                    // Control buttons
                    HStack {
                        Spacer()

                         if item.status == .paused {
                            Button {
                                downloadManager.resumeDownload(id: item.id)
                            } label: {
                                Label("Resume", systemImage: "play.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }

                        Button {
                            downloadManager.cancelDownload(id: item.id)
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.title3)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(statusText)
                            .font(.subheadline)
                            .foregroundColor(statusColor)

                        Spacer()

                        // Metadata status badge
                        if item.status == .completed {
                            metadataStatusBadge
                        }
                    }

                    // Metadata preview for completed downloads
                    if item.status == .completed, let metadata = item.metadataResult {
                        metadataPreview(metadata: metadata)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.background)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        .contextMenu {
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
            }

            if item.status == .completed {
                Divider()

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
        }
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
    
    // MARK: - Metadata Status Badge

    @ViewBuilder
    private var metadataStatusBadge: some View {
        switch item.metadataStatus {
        case .enriching:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Enriching...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(8)
        case .tagging:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Writing tags...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.15))
            .cornerRadius(8)
        case .completed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text("Tagged")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.15))
            .cornerRadius(8)
        case .failed:
            Button {
                downloadManager.retryMetadata(id: item.id)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Retry")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        case .pending:
            if !item.metadataCandidates.isEmpty {
                Button {
                    showMetadataPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "tag")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                        Text("Choose & Write")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                EmptyView()
            }
        case .skipped:
            EmptyView()
        }
    }

    // MARK: - Metadata Preview

    @ViewBuilder
    private func metadataPreview(metadata: MetadataResult) -> some View {
        HStack(spacing: 8) {
            // Genre tags
            if !metadata.genre.isEmpty {
                Text(metadata.genre.prefix(2).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.7))
                    .cornerRadius(4)
            }

            // Year
            if let year = metadata.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(4)
            }

            // Rating
            if let rating = metadata.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text(String(format: "%.1f", rating))
                        .font(.caption2)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.7))
                .cornerRadius(4)
            }

            // Content advisory rating
            if let advisory = metadata.contentAdvisoryRating, !advisory.isEmpty {
                Text(advisory)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.6))
                    .cornerRadius(4)
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch item.status {
            case .notStarted:
                ProgressView()
                    .scaleEffect(0.8)
            case .downloading:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.accentColor)
            case .paused:
                Image(systemName: "pause.circle.fill")
                    .foregroundColor(.orange)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.title2)
    }
    
    private var statusText: String {
        switch item.status {
        case .notStarted:
            return "Preparing download..."
        case .downloading:
            return "Downloading..."
        case .paused:
            return "Download paused"
        case .completed:
            return "Download completed"
        case .cancelled:
            return "Download cancelled"
        case .failed:
            return "Download failed"
        }
    }
    
    private var statusColor: Color {
        switch item.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        case .paused:
            return .orange
        default:
            return .primary
        }
    }
    
    private func formatETA(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "Calculating..." }
        
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "Unknown"
    }
}


#if DEBUG
struct DownloadRowView_Previews: PreviewProvider {
    static var previews: some View {
        let previewDownloadManager = PreviewDownloadManager()
        
        return Group {
            DownloadRowView(item: DownloadItem(id: UUID(), vodID: "1", title: "Not Started Download", type: .movie, status: .notStarted, totalBytes: 100_000_000, bytesDownloaded: 0, progress: 0, speed: 0, eta: 0), progress: 0)
                .previewDisplayName("Not Started")
            
            // Wrap the "Downloading" item in SimulatedProgressView for animated progress
            SimulatedProgressView(item: DownloadItem(id: UUID(), vodID: "2", title: "Downloading File", type: .movie, status: .downloading, totalBytes: 100_000_000, bytesDownloaded: 45_000_000, progress: 45, speed: 2.5, eta: 120))
                .previewDisplayName("Downloading (Simulated Progress)")
            
            DownloadRowView(item: DownloadItem(id: UUID(), vodID: "3", title: "Paused Download", type: .movie, status: .paused, totalBytes: 100_000_000, bytesDownloaded: 60_000_000, progress: 60, speed: 0, eta: 0), progress: 60)
                .previewDisplayName("Paused")
            
            DownloadRowView(item: DownloadItem(id: UUID(), vodID: "4", title: "Completed Download", type: .movie, status: .completed, totalBytes: 100_000_000, bytesDownloaded: 100_000_000, progress: 100, speed: 0, eta: 0), progress: 100)
                .previewDisplayName("Completed")
            
            DownloadRowView(item: DownloadItem(id: UUID(), vodID: "5", title: "Cancelled Download", type: .movie, status: .cancelled, totalBytes: 100_000_000, bytesDownloaded: 30_000_000, progress: 30, speed: 0, eta: 0), progress: 30)
                .previewDisplayName("Cancelled")
            
            DownloadRowView(item: DownloadItem(id: UUID(), vodID: "6", title: "Failed Download", type: .movie, status: .failed, totalBytes: 100_000_000, bytesDownloaded: 80_000_000, progress: 80, speed: 0, eta: 0, error: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection error"]) as Error), progress: 80)
                .previewDisplayName("Failed")
        }
        .environmentObject(previewDownloadManager)
        .previewLayout(.sizeThatFits)
        .padding()
    }
}


// Wrapper view to simulate animated progress for preview purposes
struct SimulatedProgressView: View {
    let item: DownloadItem
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        DownloadRowView(item: item, progress: animatedProgress)  // Pass animatedProgress
            .onAppear {
                startSimulatedProgress()
            }
    }
    
    private func startSimulatedProgress() {
        animatedProgress = item.progress
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if animatedProgress >= 100 {
                timer.invalidate()  // Stop the timer once progress reaches 100%
            } else {
                animatedProgress += 1  // Increment progress
            }
        }
    }
}

#endif

