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
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
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
        }
    }
    
    // The rest of the code for statusIcon, statusText, statusColor, and formatETA remain the same.



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

