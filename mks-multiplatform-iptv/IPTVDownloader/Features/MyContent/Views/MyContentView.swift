import SwiftUI
import UniformTypeIdentifiers

struct MyContentView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var localFiles: [LocalVideoFile] = []
    @State private var showFileImporter = false
    #if os(macOS)
    @EnvironmentObject private var touchBarManager: TouchBarManager
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        AdaptiveGlassContainer {
            Group {
                if downloadManager.downloads.isEmpty && localFiles.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
        }
        .navigationTitle("My Content")
        .toolbar { toolbarContent }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg, .mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
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

    // MARK: - Content View

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                // MARK: - IPTV Downloads Section
                if !downloadManager.downloads.isEmpty {
                    Section {
                        ForEach(downloadManager.downloads) { download in
                            DownloadRowView(item: download, progress: download.progress)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    downloadSwipeActions(for: download)
                                }
                        }
                    } header: {
                        SectionHeader(
                            title: "IPTV Downloads",
                            icon: "arrow.down.circle",
                            count: downloadManager.downloads.count
                        )
                    }
                }

                // MARK: - Local Files Section
                if !localFiles.isEmpty {
                    Section {
                        ForEach(localFiles) { file in
                            LocalFileRowView(
                                file: file,
                                onPlay: { playLocalFile(file) },
                                onRemove: { removeLocalFile(file) }
                            )
                        }
                    } header: {
                        SectionHeader(
                            title: "Local Files",
                            icon: "doc.video",
                            count: localFiles.count
                        )
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("My Content")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Add video files or download from your IPTV library")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                showFileImporter = true
            } label: {
                Label("Add Files", systemImage: "plus.circle")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                showFileImporter = true
            } label: {
                Label("Add Files", systemImage: "plus")
            }

            if !downloadManager.downloads.isEmpty {
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

                if downloadManager.hasActiveDownloads || downloadManager.hasPausedDownloads {
                    Button(role: .destructive) {
                        downloadManager.cancelAllDownloads()
                    } label: {
                        Label("Cancel All", systemImage: "xmark.circle")
                    }
                }

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

    // MARK: - Download Swipe Actions

    @ViewBuilder
    private func downloadSwipeActions(for download: DownloadItem) -> some View {
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

    // MARK: - File Handling

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let file = LocalVideoFile(url: url)
                if !localFiles.contains(where: { $0.url == url }) {
                    localFiles.append(file)
                    MKSLog.media.info("[MyContent] Added local file: \(file.displayName)")
                }
            }
        case .failure(let error):
            MKSLog.media.error("[MyContent] Import error: \(error)")
        }
    }

    private func playLocalFile(_ file: LocalVideoFile) {
        #if os(macOS)
        let player = PlayerFactory.shared.createPlayer(for: file.url)
        PlayerWindowManager.shared.present(
            player: player,
            title: file.displayName,
            metadata: nil
        )
        openWindow(id: "player")
        player.load(url: file.url)
        player.play()
        #endif
    }

    private func removeLocalFile(_ file: LocalVideoFile) {
        localFiles.removeAll { $0.id == file.id }
        MKSLog.media.info("[MyContent] Removed local file: \(file.displayName)")
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

// MARK: - Preview

#if DEBUG
struct MyContentView_Previews: PreviewProvider {
    static var previews: some View {
        let previewDownloadManager = DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))

        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "1", title: "Downloading", type: .movie, status: .downloading, totalBytes: 100_000_000, bytesDownloaded: 45_000_000, progress: 45, speed: 2.5, eta: 120))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "2", title: "Completed", type: .movie, status: .completed, totalBytes: 100_000_000, bytesDownloaded: 100_000_000, progress: 100))

        return NavigationStack {
            MyContentView()
                .environmentObject(previewDownloadManager)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
