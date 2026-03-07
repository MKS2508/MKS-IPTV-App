import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    #if os(macOS)
    @EnvironmentObject private var touchBarManager: TouchBarManager
    #endif

    var body: some View {
        AdaptiveGlassContainer {
            Group {
                if downloadManager.downloads.isEmpty {
                    emptyStateView
                } else {
                    downloadsList
                }
            }
        }
        .navigationTitle("Downloads")
        .toolbar { toolbarContent }
        #if os(macOS)
        .onAppear {
            updateTouchBarProgress()
        }
        .onReceive(downloadManager.$downloads) { _ in
            updateTouchBarProgress()
        }
        .onReceive(downloadManager.objectWillChange) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateTouchBarProgress()
            }
        }
        #endif
    }

    // MARK: - Downloads List

    private var downloadsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(downloadManager.downloads) { download in
                    DownloadRowView(item: download, progress: download.progress)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if download.status == .downloading {
                                Button {
                                    downloadManager.pauseDownload(id: download.id)
                                } label: {
                                    Label("Pause", systemImage: "pause.circle")
                                }
                                .tint(.yellow)

                                Button(role: .destructive) {
                                    downloadManager.cancelDownload(id: download.id)
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            } else if download.status == .paused {
                                Button {
                                    downloadManager.resumeDownload(id: download.id)
                                } label: {
                                    Label("Resume", systemImage: "play.circle")
                                }
                                .tint(.green)

                                Button(role: .destructive) {
                                    downloadManager.cancelDownload(id: download.id)
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                }
                            } else if download.status == .failed {
                                Button {
                                    downloadManager.retryDownload(id: download.id)
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                                .tint(.accentColor)

                                Button(role: .destructive) {
                                    downloadManager.removeDownload(id: download.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            } else if download.status == .completed || download.status == .cancelled {
                                Button(role: .destructive) {
                                    downloadManager.removeDownload(id: download.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Downloads")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Your downloads will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            if !downloadManager.downloads.isEmpty {
                // Pause All / Resume All toggle
                if downloadManager.hasActiveDownloads {
                    Button {
                        downloadManager.togglePauseResumeAll()
                    } label: {
                        Label("Pause All", systemImage: "pause.circle")
                    }
                } else if downloadManager.hasPausedDownloads {
                    Button {
                        downloadManager.togglePauseResumeAll()
                    } label: {
                        Label("Resume All", systemImage: "play.circle")
                    }
                }

                // Cancel All (only when there are active/paused downloads)
                if downloadManager.hasActiveDownloads || downloadManager.hasPausedDownloads {
                    Button(role: .destructive) {
                        downloadManager.cancelAllDownloads()
                    } label: {
                        Label("Cancel All", systemImage: "xmark.circle")
                    }
                }

                // Clear Finished
                if downloadManager.downloads.contains(where: { $0.status == .completed || $0.status == .cancelled || $0.status == .failed }) {
                    Button {
                        downloadManager.clearFinished()
                    } label: {
                        Label("Clear Finished", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - TouchBar (macOS)

    #if os(macOS)
    private func updateTouchBarProgress() {
        let activeDownloads = downloadManager.downloads.filter { $0.status == .downloading }
        let totalProgress = activeDownloads.isEmpty ? 0.0 :
            activeDownloads.map { $0.progress / 100.0 }.reduce(0, +) / Double(activeDownloads.count)

        let totalSpeed = activeDownloads.map { $0.speed }.reduce(0, +)

        let averageETA = activeDownloads.isEmpty ? 0.0 :
            activeDownloads.map { $0.eta }.reduce(0, +) / Double(activeDownloads.count)

        touchBarManager.updateDownloadProgress(
            active: activeDownloads.count,
            progress: totalProgress,
            speed: totalSpeed,
            eta: averageETA
        )

        touchBarManager.isPaused = downloadManager.downloads.contains { $0.status == .paused }
    }
    #endif
}


#if DEBUG
struct DownloadsView_Previews: PreviewProvider {
    static var previews: some View {
        let previewDownloadManager = DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))

        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "1", title: "Not Started", type: .movie, status: .notStarted))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "2", title: "Downloading", type: .movie, status: .downloading, totalBytes: 100_000_000, bytesDownloaded: 45_000_000, progress: 45, speed: 2.5, eta: 120))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "3", title: "Paused", type: .movie, status: .paused, totalBytes: 100_000_000, bytesDownloaded: 60_000_000, progress: 60))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "4", title: "Completed", type: .movie, status: .completed, totalBytes: 100_000_000, bytesDownloaded: 100_000_000, progress: 100))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "5", title: "Cancelled", type: .movie, status: .cancelled))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "6", title: "Failed", type: .movie, status: .failed, errorMessage: "Connection error"))

        return Group {
            NavigationStack {
                DownloadsView()
                    .environmentObject(previewDownloadManager)
            }
            .previewDisplayName("With Downloads")

            NavigationStack {
                DownloadsView()
                    .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
            }
            .previewDisplayName("Empty State")
        }
        .preferredColorScheme(.dark)
    }
}
#endif
