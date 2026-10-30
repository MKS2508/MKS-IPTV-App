import SwiftUI
import UniformTypeIdentifiers
import IPTVCore

struct MyContentView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var localFiles: [LocalVideoFile] = []
    @State private var localFileMetadata: [UUID: LocalFileMetadata] = [:]
    @State private var showFileImporter = false

    // Sheet state
    @State private var selectedLocalFile: LocalVideoFile?
    @State private var showActionSheet = false
    @State private var showMetadataPicker = false
    @State private var metadataCandidates: [ScoredMetadataResult] = []
    @State private var showConvertSheet = false

    #if os(macOS)
    @EnvironmentObject private var touchBarManager: TouchBarManager
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        content
            .navigationTitle("My Content")
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg, .mpeg4Movie],
                allowsMultipleSelection: true
            ) { handleFileImport($0) }
            .onAppear { loadLocalFiles() }
            .sheet(isPresented: $showMetadataPicker) { metadataPickerSheet }
            .sheet(isPresented: $showConvertSheet) { convertSheet }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if localFiles.isEmpty && downloadManager.downloads.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 24) {
                    if !downloadManager.downloads.isEmpty {
                        downloadsSection
                    }
                    if !localFiles.isEmpty {
                        localFilesSection
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Downloads Section

    private var downloadsSection: some View {
        Section {
            ForEach(downloadManager.downloads) { download in
                DownloadRowView(item: download, progress: download.progress)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        downloadSwipeActions(for: download)
                    }
            }
        } header: {
            SectionHeader(title: "IPTV Downloads", icon: "arrow.down.circle", count: downloadManager.downloads.count)
        }
    }

    // MARK: - Local Files Section

    private var localFilesSection: some View {
        Section {
            ForEach(localFiles) { file in
                LocalFileRowView(
                    file: file,
                    effectiveDisplayName: effectiveDisplayName(for: file),
                    onPlay: { playLocalFile(file) },
                    onShowActions: { _ in showActionSheet(for: file) }
                )
            }
        } header: {
            SectionHeader(title: "Local Files", icon: "doc.video", count: localFiles.count)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("My Content")
                .font(.title2.weight(.semibold))
            Text("Add video files or download from your IPTV library")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Add Files") { showFileImporter = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem { Button("Add Files") { showFileImporter = true } }
        if !downloadManager.downloads.isEmpty {
            ToolbarItem {
                Menu {
                    if downloadManager.hasActiveDownloads {
                        Button("Pause All") { downloadManager.togglePauseResumeAll() }
                    } else if downloadManager.hasPausedDownloads {
                        Button("Resume All") { downloadManager.togglePauseResumeAll() }
                    }
                    if downloadManager.hasActiveDownloads || downloadManager.hasPausedDownloads {
                        Divider()
                        Button("Cancel All", role: .destructive) { downloadManager.cancelAllDownloads() }
                    }
                    if downloadManager.downloads.contains(where: { $0.status == .completed || $0.status == .failed }) {
                        Button("Clear Finished") { downloadManager.clearFinished() }
                    }
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func downloadSwipeActions(for download: DownloadItem) -> some View {
        switch download.status {
        case .downloading:
            Button("Pause") { downloadManager.pauseDownload(id: download.id) }
                .tint(.yellow)
            Button("Cancel", role: .destructive) { downloadManager.cancelDownload(id: download.id) }
        case .paused:
            Button("Resume") { downloadManager.resumeDownload(id: download.id) }
                .tint(.green)
            Button("Cancel", role: .destructive) { downloadManager.cancelDownload(id: download.id) }
        case .failed:
            Button("Retry") { downloadManager.retryDownload(id: download.id) }
            Button("Remove", role: .destructive) { downloadManager.removeDownload(id: download.id) }
        case .completed, .cancelled:
            Button("Remove", role: .destructive) { downloadManager.removeDownload(id: download.id) }
        default:
            EmptyView()
        }
    }

    // MARK: - Local File Helpers

    private func effectiveDisplayName(for file: LocalVideoFile) -> String {
        localFileMetadata[file.id]?.displayName ?? file.displayName
    }

    private func loadLocalFiles() {
        let (files, metadata) = LocalFileManager.shared.load()
        localFiles = files
        localFileMetadata = metadata
    }

    private func showActionSheet(for file: LocalVideoFile) {
        selectedLocalFile = file
        showActionSheet = true
    }

    private func playLocalFile(_ file: LocalVideoFile) {
        #if os(macOS)
        let player = PlayerFactory.shared.createPlayer(for: file.url)
        PlayerWindowManager.shared.present(player: player, title: effectiveDisplayName(for: file), metadata: nil)
        openWindow(id: "player")
        player.load(url: file.url)
        player.play()
        #endif
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            let file = LocalVideoFile(url: url)
            localFiles = LocalFileManager.shared.add(file, to: localFiles, metadata: localFileMetadata)
        }
    }

    // MARK: - Action Sheet

    @ViewBuilder
    private var actionSheet: some View {
        if let file = selectedLocalFile {
            LocalFileActionSheet(
                file: file,
                metadata: localFileMetadata[file.id] ?? LocalFileMetadata(displayName: file.displayName),
                onDismiss: { showActionSheet = false },
                onEditMetadata: {
                    showActionSheet = false
                    startEditMetadata(for: file)
                },
                onConvert: {
                    showActionSheet = false
                    showConvertSheet = true
                },
                onDelete: {
                    showActionSheet = false
                    deleteLocalFile(file)
                }
            )
        }
    }

    // MARK: - Metadata

    private func startEditMetadata(for file: LocalVideoFile) {
        selectedLocalFile = file
        Task {
            let query = MetadataSearchQuery(
                title: file.displayName, year: nil, tmdbId: nil, genre: nil,
                runtimeMinutes: nil, mediaType: .movie, seasonNumber: nil, episodeNumber: nil, showTitle: nil
            )
            let candidates = await MetadataEnrichmentService.shared.fetchAllCandidates(query: query)
            metadataCandidates = candidates
            showMetadataPicker = true
        }
    }

    @ViewBuilder
    private var metadataPickerSheet: some View {
        if let file = selectedLocalFile {
            MetadataPickerView(
                fileTitle: effectiveDisplayName(for: file),
                candidates: metadataCandidates,
                onConfirm: { result in
                    showMetadataPicker = false
                    applyMetadata(result, to: file)
                },
                onDismiss: { showMetadataPicker = false }
            )
        }
    }

    private func applyMetadata(_ result: MetadataResult, to file: LocalVideoFile) {
        Task {
            do {
                try await MetadataEnrichmentService.shared.writeChosenMetadata(to: file.url, metadata: result)
                if result.title != file.displayName {
                    localFileMetadata = LocalFileManager.shared.updateDisplayName(
                        id: file.id, displayName: result.title,
                        files: localFiles, metadata: localFileMetadata
                    )
                }
            } catch {
                MKSLog.media.error("[MyContent] Metadata write failed: \(error)")
            }
        }
    }

    // MARK: - Convert

    @ViewBuilder
    private var convertSheet: some View {
        if let file = selectedLocalFile {
            ConvertFileSheet(
                file: file,
                onDismiss: { showConvertSheet = false },
                onComplete: { newURL in
                    showConvertSheet = false
                    replaceLocalFile(original: file, with: newURL)
                }
            )
        }
    }

    private func replaceLocalFile(original: LocalVideoFile, with newURL: URL) {
        let newFile = LocalVideoFile(url: newURL)
        localFiles = LocalFileManager.shared.remove(id: original.id, from: localFiles, metadata: localFileMetadata)
        localFiles = LocalFileManager.shared.add(newFile, to: localFiles, metadata: localFileMetadata)
        selectedLocalFile = newFile
    }

    private func deleteLocalFile(_ file: LocalVideoFile) {
        localFiles = LocalFileManager.shared.remove(id: file.id, from: localFiles, metadata: localFileMetadata)
    }
}

// MARK: - Preview

#if DEBUG
struct MyContentView_Previews: PreviewProvider {
    static var previews: some View {
        let mgr = DownloadManager(profile: IPTVProfile(name: "Test", baseURL: "http://x.com", username: "u", password: "p"))
        NavigationStack {
            MyContentView()
                .environmentObject(mgr)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
