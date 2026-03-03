import Foundation
import Combine
import TransmuxCore

class DownloadManager: ObservableObject {
    @Published private(set) var downloads: [DownloadItem] = []
    
    private var downloaders: [UUID: VideoDownloader] = [:]
    private var progressSubscriptions: [UUID: AnyCancellable] = [:]
    private let profile: IPTVProfile
    
    init(profile: IPTVProfile) {
        self.profile = profile
    }
    
    func addDownload(_ download: DownloadItem) {
        DispatchQueue.main.async {
            self.downloads.append(download)
        }
    }
    
    func cancelDownload(id: UUID) {
        guard let downloader = downloaders[id] else { return }
        downloader.cancel()
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
        
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .cancelled
        }
        
        // Clean up
        downloaders[id] = nil
    }
    
    func pauseDownload(id: UUID) {
        guard let downloader = downloaders[id] else { return }
        downloader.pause()
        
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .paused
        }
    }
    
    func cancelAllDownloads() {
        for download in downloads where download.status == .downloading || download.status == .paused {
            cancelDownload(id: download.id)
        }
    }
    
    func togglePauseResumeAll() {
        let activeDownloads = downloads.filter { $0.status == .downloading }
        let pausedDownloads = downloads.filter { $0.status == .paused }
        
        if !activeDownloads.isEmpty {
            // Pause all active downloads
            for download in activeDownloads {
                pauseDownload(id: download.id)
            }
        } else if !pausedDownloads.isEmpty {
            // Resume all paused downloads
            for download in pausedDownloads {
                resumeDownload(id: download.id)
            }
        }
    }
    
    func startDownload(
        vodID: String,
        title: String,
        type: MediaType,
        vodExtension: String,
        outputFormat: VideoDownloader.OutputFormat = .mp4,
        playWhileDownloading: Bool = false,
        downloadPathParam: String,
        tmdbId: Int? = nil,
        genre: String? = nil,
        runtimeMinutes: Int? = nil,
        preResolvedMetadata: MetadataResult? = nil,
        metadataCandidates: [ScoredMetadataResult]? = nil
    ) {
        var download = DownloadItem(
            id: UUID(),
            vodID: vodID,
            title: title,
            type: type,
            status: .notStarted
        )
        
        // Set output format and play-while-downloading option
        download.outputFormat = outputFormat
        download.playWhileDownloading = playWhileDownloading

        // Attach pre-resolved metadata if provided
        if let metadata = preResolvedMetadata {
            download.metadataResult = metadata
        }
        if let candidates = metadataCandidates {
            download.metadataCandidates = candidates
        }

        // Capture immutable copy before concurrent use
        let finalDownload = download

        DispatchQueue.main.async {
            self.downloads.append(finalDownload)
        }

        // Create a new downloader for this download
        let downloader = VideoDownloader(profile: profile)
        downloader.outputFormat = outputFormat
        let downloadId = finalDownload.id
        downloaders[downloadId] = downloader

        // Set up a new progress subscription for this download
        let progressSubscription = downloader.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.handleCompletion(for: downloadId, completion: completion)
            }, receiveValue: { [weak self] progress in
                self?.updateProgress(for: downloadId, progress: progress)
            })
        progressSubscriptions[downloadId] = progressSubscription

        Task {
            do {
                var downloadPath = ""
                if (downloadPathParam != "") {
                    downloadPath = downloadPathParam
                } else {
                    downloadPath = UserDefaults.downloadPath
                }

                // Use the output format's extension for the destination file
                let destinationPath = URL(fileURLWithPath: downloadPath)
                    .appendingPathComponent("\(title).\(outputFormat.fileExtension)")
                    .path

                // Use streaming transmux download for all downloads now
                let session = try await downloader.downloadWithTransmux(
                    vodID: vodID,
                    to: destinationPath,
                    vodExtension: vodExtension,
                    format: outputFormat,
                    isMovie: type == .movie
                )
                
                // Wait for transmux completion
                await waitForTransmuxCompletion(session: session, downloader: downloader)

                // Mark as completed
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].status = .completed
                        self.downloads[index].progress = 100.0
                        self.downloads[index].filePath = session.outputPath

                        // Clean up
                        self.downloaders[downloadId] = nil
                        self.progressSubscriptions[downloadId]?.cancel()
                        self.progressSubscriptions[downloadId] = nil
                    }
                }

                // Post-download metadata writing
                let fileURL = URL(fileURLWithPath: session.outputPath)
                if let metadata = preResolvedMetadata {
                    // Pre-resolved metadata: write tags directly
                    Task { [weak self] in
                        guard let self = self else { return }
                        do {
                            try await MetadataEnrichmentService.shared.writeChosenMetadata(
                                to: fileURL,
                                metadata: metadata
                            ) { status in
                                Task { @MainActor in
                                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                                        self.downloads[index].metadataStatus = status
                                    }
                                }
                            }
                        } catch {
                            await MainActor.run {
                                if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                                    self.downloads[index].metadataStatus = .failed(error.localizedDescription)
                                }
                            }
                        }
                    }
                } else {
                    // No pre-resolved metadata: fetch candidates for later selection
                    let metadataQuery = MetadataSearchQuery(
                        title: title,
                        year: StringSimilarity.extractYear(from: title),
                        tmdbId: tmdbId,
                        genre: genre,
                        runtimeMinutes: runtimeMinutes,
                        mediaType: type == .movie ? .movie : .series
                    )
                    Task { [weak self] in
                        guard let self = self else { return }
                        await MainActor.run {
                            if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                                self.downloads[index].metadataStatus = .enriching
                            }
                        }
                        let candidates = await MetadataEnrichmentService.shared.fetchAllCandidates(query: metadataQuery)
                        await MainActor.run {
                            if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                                self.downloads[index].metadataCandidates = candidates
                                if let best = candidates.first {
                                    self.downloads[index].metadataResult = best.result
                                    self.downloads[index].metadataStatus = .pending
                                } else {
                                    self.downloads[index].metadataStatus = .failed("No metadata found")
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(for: downloadId, error: error)
                }
            }
        }
    }
    
    /// Wait for a transmux session to complete
    private func waitForTransmuxCompletion(session: ProgressiveTransmuxSession, downloader: VideoDownloader) async {
        // Listen for the transmux completion notification
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let observer = NotificationCenter.default.addObserver(
                forName: .transmuxDidComplete,
                object: session.sessionID,
                queue: .main
            ) { _ in
                continuation.resume()
            }
            
            // Also poll for completion as a fallback
            Task {
                while true {
                    let bufferedTime = await session.segmenter.latestBufferedSourceTime()
                    if bufferedTime >= session.duration {
                        NotificationCenter.default.removeObserver(observer)
                        continuation.resume()
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }
    
    func resumeDownload(id: UUID) {
        guard let download = downloads.first(where: { $0.id == id }),
              download.status == .paused,
              let downloader = downloaders[id] else {
            return
        }
        
        // Set up new progress subscription for resumed download
        progressSubscriptions[id]?.cancel()
        let progressSubscription = downloader.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.handleCompletion(for: id, completion: completion)
            }, receiveValue: { [weak self] progress in
                self?.updateProgress(for: id, progress: progress)
            })
        progressSubscriptions[id] = progressSubscription
        
        Task {
            do {
                try await downloader.resume()
                
                await MainActor.run {
                    if let index = downloads.firstIndex(where: { $0.id == id }) {
                        downloads[index].status = .downloading
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(for: id, error: error)
                }
            }
        }
    }
    
    /// Write user-chosen metadata to a completed download's file.
    ///
    /// Call this after the user selects a candidate and optionally edits it.
    /// The metadata is written to the file via FFmpeg and the status updates.
    func writeMetadataForDownload(id: UUID, metadata: MetadataResult) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              let filePath = downloads[index].filePath else { return }

        downloads[index].metadataResult = metadata

        let fileURL = URL(fileURLWithPath: filePath)
        Task { [weak self] in
            guard let self = self else { return }
            do {
                try await MetadataEnrichmentService.shared.writeChosenMetadata(
                    to: fileURL,
                    metadata: metadata
                ) { status in
                    Task { @MainActor in
                        if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                            self.downloads[index].metadataStatus = status
                        }
                    }
                }
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                        self.downloads[index].metadataResult = metadata
                    }
                }
            } catch {
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                        self.downloads[index].metadataStatus = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Retry metadata resolution for a download that failed enrichment.
    func retryMetadata(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let item = downloads[index]
        guard item.status == .completed else { return }

        downloads[index].metadataStatus = .enriching

        let query = MetadataSearchQuery(
            title: item.title,
            year: StringSimilarity.extractYear(from: item.title),
            mediaType: item.type == .movie ? .movie : .series
        )

        Task { [weak self] in
            guard let self = self else { return }
            let candidates = await MetadataEnrichmentService.shared.fetchAllCandidates(query: query)
            await MainActor.run {
                if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                    self.downloads[index].metadataCandidates = candidates
                    if let best = candidates.first {
                        self.downloads[index].metadataResult = best.result
                        self.downloads[index].metadataStatus = .pending
                    } else {
                        self.downloads[index].metadataStatus = .failed("No metadata found")
                    }
                }
            }
        }
    }

    private func handleCompletion(for id: UUID, completion: Subscribers.Completion<Never>) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        // Only .finished is possible since Failure is Never
        if downloads[index].status != .paused && downloads[index].status != .cancelled {
            downloads[index].status = .completed
            downloads[index].progress = 100.0
        }
        
        // Clean up
        downloaders[id] = nil
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
    }
    
    private func updateProgress(for id: UUID, progress: VideoDownloader.DownloadProgress) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedDownload = downloads[index]
        if updatedDownload.status != .paused && updatedDownload.status != .cancelled {
            updatedDownload.status = .downloading
        }
        updatedDownload.progress = progress.percentComplete
        updatedDownload.speed = progress.speed
        updatedDownload.eta = progress.eta
        updatedDownload.totalBytes = progress.totalBytes > 0 ? progress.totalBytes : updatedDownload.totalBytes
        updatedDownload.bytesDownloaded = progress.bytesDownloaded
        downloads[index] = updatedDownload
        
        // Check if download is at 100% and update status if needed
        if progress.percentComplete >= 100.0 && updatedDownload.status == .downloading {
            // Manually trigger completion handling
            handleCompletion(for: id, completion: .finished)
        }
    }
    
    private func handleError(for id: UUID, error: Error) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            if let downloadError = error as? VideoDownloader.DownloadError {
                switch downloadError {
                case .downloadPaused:
                    downloads[index].status = .paused
                case .downloadCancelled:
                    downloads[index].status = .cancelled
                default:
                    downloads[index].status = .failed
                    downloads[index].error = error
                }
            } else {
                downloads[index].status = .failed
                downloads[index].error = error
            }
        }
        
        // Clean up
        downloaders[id] = nil
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
    }
}

class PreviewDownloadManager: DownloadManager {
    init() {
        super.init(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
    }
    
    override func cancelDownload(id: UUID) {
        print("Cancelling download with ID: \(id)")
    }
    
    override func pauseDownload(id: UUID) {
        print("Pausing download with ID: \(id)")
    }
    
    override func resumeDownload(id: UUID) {
        print("Resuming download with ID: \(id)")
    }
}
