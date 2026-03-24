import Foundation
import Combine
import os
import TransmuxCore
#if os(iOS)
import Photos
#endif

class DownloadManager: ObservableObject {
    @Published private(set) var downloads: [DownloadItem] = []

    private var downloaders: [UUID: VideoDownloader] = [:]
    private var progressSubscriptions: [UUID: AnyCancellable] = [:]
    private let profile: IPTVProfile
    private let logger = Logger(subsystem: "com.mks.iptv.DownloadManager", category: "Downloads")
    private let notificationService = DownloadNotificationService.shared
    #if os(iOS)
    private let liveActivityManager = DownloadLiveActivityManager.shared
    #endif
    private var lastNotificationUpdate: [UUID: Date] = [:]
    private let notificationThrottle: TimeInterval = 2.0

    // MARK: - Persistence

    private static var persistenceURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("mks-iptv-downloads.json")
    }

    // MARK: - Computed Properties

    var hasActiveDownloads: Bool {
        downloads.contains { $0.status == .downloading || $0.status == .converting }
    }

    var hasPausedDownloads: Bool {
        downloads.contains { $0.status == .paused }
    }

    // MARK: - Init

    init(profile: IPTVProfile) {
        self.profile = profile
        loadPersistedDownloads()
    }

    // MARK: - Public API

    func addDownload(_ download: DownloadItem) {
        DispatchQueue.main.async {
            self.downloads.append(download)
            self.persistDownloads()
        }
    }

    func cancelDownload(id: UUID) {
        if let downloader = downloaders[id] {
            downloader.cancel()
        }
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil

        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .cancelled

            // Delete the partial file
            if let filePath = downloads[index].filePath ?? downloads[index].downloadPath {
                try? FileManager.default.removeItem(atPath: filePath)
            }
        }

        #if os(iOS)
        liveActivityManager.endActivity(for: id.uuidString, status: "Cancelled")
        #endif
        downloaders[id] = nil
        persistDownloads()
    }

    func pauseDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .downloading else { return }

        if let downloader = downloaders[id] {
            downloader.pause()

            // Save byte offset for resume
            downloads[index].bytesDownloaded = downloader.downloadedBytes
        }

        downloads[index].status = .paused
        downloads[index].speed = 0
        downloads[index].eta = 0
        #if os(iOS)
        liveActivityManager.updateActivity(
            for: id.uuidString, progress: downloads[index].progress,
            speed: 0, eta: 0,
            bytesDownloaded: downloads[index].bytesDownloaded,
            totalBytes: downloads[index].totalBytes,
            status: "Paused"
        )
        #endif
        persistDownloads()
    }

    func resumeDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .paused else { return }

        let item = downloads[index]

        // For transmux downloads, we need to restart (can't resume transmux mid-stream)
        if item.transmuxSessionID != nil {
            // Restart the transmux from scratch
            logger.info("Resuming transmux download — restarting transmux session for \(item.title)")
            restartDownload(id: id)
            return
        }

        // For HTTP downloads: resume from byte offset
        if let downloader = downloaders[id] {
            // Resubscribe to progress
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
                        if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                            self.downloads[index].status = .downloading
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.handleError(for: id, error: error)
                    }
                }
            }
        } else {
            // Downloader was released (e.g., app restart) — restart from byte offset
            restartDownload(id: id)
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
            for download in activeDownloads {
                pauseDownload(id: download.id)
            }
        } else if !pausedDownloads.isEmpty {
            for download in pausedDownloads {
                resumeDownload(id: download.id)
            }
        }
    }

    func clearFinished() {
        downloads.removeAll { $0.status == .completed || $0.status == .cancelled || $0.status == .failed }
        persistDownloads()
    }

    func removeDownload(id: UUID) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let item = downloads[index]
            // Cancel if active
            if item.status == .downloading || item.status == .converting {
                cancelDownload(id: id)
            }
            downloads.remove(at: index)
            persistDownloads()
        }
    }

    // MARK: - Start Download (Two-Phase: Download → Convert)

    func startDownload(
        vodID: String,
        title: String,
        type: MediaType,
        vodExtension: String,
        outputFormat: VideoDownloader.OutputFormat = .mp4,
        playWhileDownloading: Bool = false,
        saveToPhotos: Bool = false,
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

        download.outputFormat = outputFormat
        download.playWhileDownloading = playWhileDownloading
        download.saveToPhotos = saveToPhotos
        download.sourceExtension = vodExtension

        if let metadata = preResolvedMetadata {
            download.metadataResult = metadata
        }
        if let candidates = metadataCandidates {
            download.metadataCandidates = candidates
        }

        let downloadPath = downloadPathParam.isEmpty ? UserDefaults.downloadPath : downloadPathParam
        download.downloadPath = downloadPath

        // Build source URL string for persistence (resume after app restart)
        let urlString = type == .movie
            ? IPTVConfiguration.buildMovieURL(profile: profile, vodID: vodID, vodExtension: vodExtension)
            : IPTVConfiguration.buildSeriesURL(profile: profile, vodID: vodID, vodExtension: vodExtension)
        download.sourceURLString = urlString

        let finalDownload = download
        let downloadId = finalDownload.id

        DispatchQueue.main.async {
            self.downloads.append(finalDownload)
            self.persistDownloads()
        }

        // Decide download strategy:
        // - If playWhileDownloading: use transmux (stream + play simultaneously)
        // - Otherwise: direct HTTP download (wire speed) → optional post-download convert
        if playWhileDownloading {
            startTransmuxDownload(
                downloadId: downloadId,
                vodID: vodID,
                title: title,
                type: type,
                vodExtension: vodExtension,
                outputFormat: outputFormat,
                downloadPath: downloadPath,
                saveToPhotos: saveToPhotos,
                tmdbId: tmdbId,
                genre: genre,
                runtimeMinutes: runtimeMinutes,
                preResolvedMetadata: preResolvedMetadata,
                metadataCandidates: metadataCandidates
            )
        } else {
            startDirectDownload(
                downloadId: downloadId,
                vodID: vodID,
                title: title,
                type: type,
                vodExtension: vodExtension,
                outputFormat: outputFormat,
                downloadPath: downloadPath,
                saveToPhotos: saveToPhotos,
                tmdbId: tmdbId,
                genre: genre,
                runtimeMinutes: runtimeMinutes,
                preResolvedMetadata: preResolvedMetadata,
                metadataCandidates: metadataCandidates
            )
        }
    }

    // MARK: - Direct HTTP Download (Wire Speed)

    private func startDirectDownload(
        downloadId: UUID,
        vodID: String,
        title: String,
        type: MediaType,
        vodExtension: String,
        outputFormat: VideoDownloader.OutputFormat,
        downloadPath: String,
        saveToPhotos: Bool,
        tmdbId: Int?,
        genre: String?,
        runtimeMinutes: Int?,
        preResolvedMetadata: MetadataResult?,
        metadataCandidates: [ScoredMetadataResult]?
    ) {
        let downloader = VideoDownloader(profile: profile)
        downloader.outputFormat = outputFormat
        downloaders[downloadId] = downloader

        // Subscribe to progress
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
                // Use source extension for the raw download file
                let rawFilePath = URL(fileURLWithPath: downloadPath)
                    .appendingPathComponent("\(title).\(vodExtension)")
                    .path

                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].status = .downloading
                        self.downloads[index].downloadPath = rawFilePath
                    }
                    #if os(iOS)
                    self.liveActivityManager.startActivity(
                        downloadId: downloadId.uuidString,
                        title: title,
                        mediaType: type == .movie ? "Movie" : "Series"
                    )
                    #endif
                }

                // Phase A: Download raw file at wire speed
                try await downloader.downloadForSave(
                    vodID: vodID,
                    to: rawFilePath,
                    vodExtension: vodExtension,
                    isMovie: type == .movie
                )

                // Phase A complete — mark as downloaded
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].status = .downloaded
                        self.downloads[index].progress = 100.0
                        self.downloads[index].filePath = rawFilePath
                    }
                    self.persistDownloads()
                }

                // Phase B: Convert if needed (source ext differs from target format)
                let needsConversion = vodExtension.lowercased() != outputFormat.fileExtension.lowercased()

                if needsConversion {
                    await self.performPostDownloadConversion(
                        downloadId: downloadId,
                        rawFilePath: rawFilePath,
                        title: title,
                        outputFormat: outputFormat,
                        downloadPath: downloadPath
                    )
                } else {
                    // No conversion needed — rename to target format if needed and mark completed
                    let finalPath = URL(fileURLWithPath: downloadPath)
                        .appendingPathComponent("\(title).\(outputFormat.fileExtension)")
                        .path

                    if rawFilePath != finalPath {
                        try? FileManager.default.moveItem(atPath: rawFilePath, toPath: finalPath)
                    }

                    await MainActor.run {
                        if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                            self.downloads[index].status = .completed
                            self.downloads[index].filePath = finalPath
                        }
                        self.downloaders[downloadId] = nil
                        self.progressSubscriptions[downloadId]?.cancel()
                        self.progressSubscriptions[downloadId] = nil
                        self.sendCompletionNotification(for: downloadId)
                        self.persistDownloads()
                    }
                }

                // Save to Photos if requested (iOS)
                #if os(iOS)
                if saveToPhotos {
                    let finalFilePath: String = await MainActor.run {
                        self.downloads.first(where: { $0.id == downloadId })?.filePath ?? rawFilePath
                    }
                    await Self.saveVideoToPhotos(
                        fileURL: URL(fileURLWithPath: finalFilePath),
                        downloadId: downloadId
                    )
                }
                #endif

                // Post-download metadata
                await self.handlePostDownloadMetadata(
                    downloadId: downloadId,
                    title: title,
                    type: type,
                    tmdbId: tmdbId,
                    genre: genre,
                    runtimeMinutes: runtimeMinutes,
                    preResolvedMetadata: preResolvedMetadata,
                    metadataCandidates: metadataCandidates
                )

            } catch {
                logger.error("[DownloadManager] Direct download failed for \(vodID) (\(title)): \(error)")
                await MainActor.run {
                    self.handleError(for: downloadId, error: error)
                }
            }
        }
    }

    // MARK: - Transmux Download (Play-While-Downloading)

    private func startTransmuxDownload(
        downloadId: UUID,
        vodID: String,
        title: String,
        type: MediaType,
        vodExtension: String,
        outputFormat: VideoDownloader.OutputFormat,
        downloadPath: String,
        saveToPhotos: Bool,
        tmdbId: Int?,
        genre: String?,
        runtimeMinutes: Int?,
        preResolvedMetadata: MetadataResult?,
        metadataCandidates: [ScoredMetadataResult]?
    ) {
        let downloader = VideoDownloader(profile: profile)
        downloader.outputFormat = outputFormat
        downloaders[downloadId] = downloader

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
                let destinationPath = URL(fileURLWithPath: downloadPath)
                    .appendingPathComponent("\(title).\(outputFormat.fileExtension)")
                    .path

                let session = try await downloader.downloadWithTransmux(
                    vodID: vodID,
                    to: destinationPath,
                    vodExtension: vodExtension,
                    format: outputFormat,
                    isMovie: type == .movie
                )

                // Store transmux session ID on the download item
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].status = .downloading
                        self.downloads[index].transmuxSessionID = session.sessionID
                    }
                    #if os(iOS)
                    self.liveActivityManager.startActivity(
                        downloadId: downloadId.uuidString,
                        title: title,
                        mediaType: type == .movie ? "Movie" : "Series"
                    )
                    #endif
                    self.persistDownloads()
                }

                // Wait for transmux completion (with safe single-resume)
                await self.waitForTransmuxCompletion(session: session)

                // Mark as completed
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].status = .completed
                        self.downloads[index].progress = 100.0
                        self.downloads[index].filePath = session.outputPath
                        self.downloads[index].transmuxSessionID = nil
                    }
                    self.downloaders[downloadId] = nil
                    self.progressSubscriptions[downloadId]?.cancel()
                    self.progressSubscriptions[downloadId] = nil
                    self.sendCompletionNotification(for: downloadId)
                    self.persistDownloads()
                }

                // Save to Photos if requested (iOS)
                #if os(iOS)
                if saveToPhotos {
                    await Self.saveVideoToPhotos(
                        fileURL: URL(fileURLWithPath: session.outputPath),
                        downloadId: downloadId
                    )
                }
                #endif

                // Post-download metadata
                await self.handlePostDownloadMetadata(
                    downloadId: downloadId,
                    title: title,
                    type: type,
                    tmdbId: tmdbId,
                    genre: genre,
                    runtimeMinutes: runtimeMinutes,
                    preResolvedMetadata: preResolvedMetadata,
                    metadataCandidates: metadataCandidates
                )

            } catch {
                logger.error("[DownloadManager] Transmux download failed for \(vodID) (\(title)): \(error)")
                await MainActor.run {
                    self.handleError(for: downloadId, error: error)
                }
            }
        }
    }

    // MARK: - Post-Download Conversion

    private func performPostDownloadConversion(
        downloadId: UUID,
        rawFilePath: String,
        title: String,
        outputFormat: VideoDownloader.OutputFormat,
        downloadPath: String
    ) async {
        await MainActor.run {
            if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                self.downloads[index].status = .converting
                #if os(iOS)
                self.liveActivityManager.updateActivity(
                    for: downloadId.uuidString,
                    progress: self.downloads[index].progress,
                    speed: 0, eta: 0,
                    bytesDownloaded: self.downloads[index].bytesDownloaded,
                    totalBytes: self.downloads[index].totalBytes,
                    status: "Converting"
                )
                #endif
            }
            self.persistDownloads()
        }

        do {
            let rawFileURL = URL(fileURLWithPath: rawFilePath)
            let tmxSession = try await TransmuxingService.shared.startTransmux(from: rawFileURL)

            logger.info("[DownloadManager] Post-download conversion started, session: \(tmxSession.sessionID)")

            // Wait for transmux to complete using notification + polling (same as streaming transmux)
            await waitForTransmuxCompletion(session: tmxSession)

            logger.info("[DownloadManager] Post-download conversion completed for \(title)")

            let convertedPath = tmxSession.outputPath

            // Clean up raw file
            try? FileManager.default.removeItem(atPath: rawFilePath)

            // Move converted file to final destination
            let finalPath = URL(fileURLWithPath: downloadPath)
                .appendingPathComponent("\(title).\(outputFormat.fileExtension)")
                .path

            if convertedPath != finalPath {
                try? FileManager.default.moveItem(atPath: convertedPath, toPath: finalPath)
            }

            await MainActor.run {
                if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                    self.downloads[index].status = .completed
                    self.downloads[index].filePath = finalPath
                }
                self.downloaders[downloadId] = nil
                self.progressSubscriptions[downloadId]?.cancel()
                self.progressSubscriptions[downloadId] = nil
                self.sendCompletionNotification(for: downloadId)
                self.persistDownloads()
            }

            // Clean up transmux session
            await TransmuxingService.shared.cleanup(sessionID: tmxSession.sessionID)

        } catch {
            logger.error("[DownloadManager] Post-download conversion failed: \(error)")
            await MainActor.run {
                // Conversion failed but raw file exists — mark as completed with raw file
                if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                    self.downloads[index].status = .completed
                    self.downloads[index].filePath = rawFilePath
                    self.downloads[index].errorMessage = "Conversion failed: \(error.localizedDescription). Raw file saved."
                }
                self.downloaders[downloadId] = nil
                self.sendCompletionNotification(for: downloadId)
                self.persistDownloads()
            }
        }
    }

    // MARK: - Wait for Transmux (Safe Single-Resume)

    private func waitForTransmuxCompletion(session: ProgressiveTransmuxSession) async {
        // Use a flag to ensure continuation is resumed exactly once
        let resumed = OSAllocatedUnfairLock(initialState: false)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let observer = NotificationCenter.default.addObserver(
                forName: .transmuxDidComplete,
                object: session.sessionID,
                queue: .main
            ) { _ in
                let shouldResume = resumed.withLock { wasResumed -> Bool in
                    if wasResumed { return false }
                    wasResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume()
                }
            }

            // Also poll for completion as a fallback
            Task {
                while true {
                    let bufferedTime = await session.segmenter.latestBufferedSourceTime()
                    if bufferedTime >= session.duration {
                        NotificationCenter.default.removeObserver(observer)
                        let shouldResume = resumed.withLock { wasResumed -> Bool in
                            if wasResumed { return false }
                            wasResumed = true
                            return true
                        }
                        if shouldResume {
                            continuation.resume()
                        }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    // MARK: - Restart Download (for resume after app restart or transmux pause)

    private func restartDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        let item = downloads[index]

        guard item.status == .paused || item.status == .failed else { return }

        // Clean up old downloader
        downloaders[id]?.cancel()
        downloaders[id] = nil
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil

        // Restart with same parameters
        downloads[index].status = .notStarted
        downloads[index].speed = 0
        downloads[index].eta = 0

        if item.playWhileDownloading {
            startTransmuxDownload(
                downloadId: id,
                vodID: item.vodID,
                title: item.title,
                type: item.type,
                vodExtension: item.sourceExtension ?? "mkv",
                outputFormat: item.outputFormat,
                downloadPath: item.downloadPath ?? UserDefaults.downloadPath,
                saveToPhotos: item.saveToPhotos,
                tmdbId: nil,
                genre: nil,
                runtimeMinutes: nil,
                preResolvedMetadata: item.metadataResult,
                metadataCandidates: item.metadataCandidates.isEmpty ? nil : item.metadataCandidates
            )
        } else {
            startDirectDownload(
                downloadId: id,
                vodID: item.vodID,
                title: item.title,
                type: item.type,
                vodExtension: item.sourceExtension ?? "mkv",
                outputFormat: item.outputFormat,
                downloadPath: item.downloadPath ?? UserDefaults.downloadPath,
                saveToPhotos: item.saveToPhotos,
                tmdbId: nil,
                genre: nil,
                runtimeMinutes: nil,
                preResolvedMetadata: item.metadataResult,
                metadataCandidates: item.metadataCandidates.isEmpty ? nil : item.metadataCandidates
            )
        }
    }

    /// Retry a failed download
    func retryDownload(id: UUID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }),
              downloads[index].status == .failed else { return }

        downloads[index].errorMessage = nil
        restartDownload(id: id)
    }

    // MARK: - Post-Download Metadata

    private func handlePostDownloadMetadata(
        downloadId: UUID,
        title: String,
        type: MediaType,
        tmdbId: Int?,
        genre: String?,
        runtimeMinutes: Int?,
        preResolvedMetadata: MetadataResult?,
        metadataCandidates: [ScoredMetadataResult]?
    ) async {
        let filePath: String? = await MainActor.run {
            self.downloads.first(where: { $0.id == downloadId })?.filePath
        }
        guard let filePath = filePath else { return }
        let fileURL = URL(fileURLWithPath: filePath)

        if let metadata = preResolvedMetadata {
            // Pre-resolved metadata: write tags directly
            do {
                try await MetadataEnrichmentService.shared.writeChosenMetadata(
                    to: fileURL,
                    metadata: metadata
                ) { status in
                    Task { @MainActor in
                        if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                            self.downloads[index].metadataStatus = status
                        }
                        self.persistDownloads()
                    }
                }
            } catch {
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == downloadId }) {
                        self.downloads[index].metadataStatus = .failed(error.localizedDescription)
                    }
                    self.persistDownloads()
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
                self.persistDownloads()
            }
        }
    }

    // MARK: - Metadata Operations

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
                    self.persistDownloads()
                }
            } catch {
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == id }) {
                        self.downloads[index].metadataStatus = .failed(error.localizedDescription)
                    }
                    self.persistDownloads()
                }
            }
        }
    }

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
                self.persistDownloads()
            }
        }
    }

    // MARK: - Progress Handling

    private func handleCompletion(for id: UUID, completion: Subscribers.Completion<Never>) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }

        if downloads[index].status != .paused && downloads[index].status != .cancelled {
            // Don't auto-complete here for direct downloads — the Task handles it
            // Only for transmux downloads that signal completion via progressSubject
            if downloads[index].transmuxSessionID != nil {
                downloads[index].status = .completed
                downloads[index].progress = 100.0
            }
        }
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

        // Throttled Live Activity / notification update (every 2 seconds)
        let now = Date()
        if let lastUpdate = lastNotificationUpdate[id], now.timeIntervalSince(lastUpdate) < notificationThrottle {
            return
        }
        lastNotificationUpdate[id] = now
        #if os(iOS)
        liveActivityManager.updateActivity(
            for: id.uuidString,
            progress: progress.percentComplete,
            speed: progress.speed,
            eta: progress.eta,
            bytesDownloaded: progress.bytesDownloaded,
            totalBytes: progress.totalBytes,
            status: "Downloading"
        )
        #elseif os(macOS)
        notificationService.updateProgress(
            downloadId: id,
            title: updatedDownload.title,
            progress: progress.percentComplete,
            speed: progress.speed,
            eta: progress.eta,
            bytesDownloaded: progress.bytesDownloaded,
            totalBytes: progress.totalBytes
        )
        #endif
    }

    // MARK: - Save to Photos (iOS)

    #if os(iOS)
    private static func saveVideoToPhotos(fileURL: URL, downloadId: UUID) async {
        do {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                print("[DownloadManager] Photos authorization denied: \(status)")
                return
            }

            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
            print("[DownloadManager] Video saved to Photos: \(fileURL.lastPathComponent)")
        } catch {
            print("[DownloadManager] Failed to save to Photos: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Completion Notification Helper

    /// Call after setting .completed on a download item to end Live Activity (iOS) or send notification (macOS).
    private func sendCompletionNotification(for id: UUID) {
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        #if os(iOS)
        liveActivityManager.endActivity(for: id.uuidString, status: "Completed")
        #elseif os(macOS)
        notificationService.notifyDownloadComplete(
            downloadId: id,
            title: item.title,
            fileSize: item.totalBytes
        )
        #endif
        lastNotificationUpdate[id] = nil
    }

    // MARK: - Error Handling

    private func handleError(for id: UUID, error: Error) {
        logger.error("[DownloadManager] handleError: \(error)")
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let title = downloads[index].title
            if let downloadError = error as? VideoDownloader.DownloadError {
                switch downloadError {
                case .downloadPaused:
                    downloads[index].status = .paused
                    #if os(iOS)
                    liveActivityManager.updateActivity(
                        for: id.uuidString, progress: downloads[index].progress,
                        speed: 0, eta: 0,
                        bytesDownloaded: downloads[index].bytesDownloaded,
                        totalBytes: downloads[index].totalBytes,
                        status: "Paused"
                    )
                    #elseif os(macOS)
                    notificationService.removeNotification(downloadId: id)
                    #endif
                case .downloadCancelled:
                    downloads[index].status = .cancelled
                    #if os(iOS)
                    liveActivityManager.endActivity(for: id.uuidString, status: "Cancelled")
                    #elseif os(macOS)
                    notificationService.removeNotification(downloadId: id)
                    #endif
                default:
                    downloads[index].status = .failed
                    downloads[index].errorMessage = error.localizedDescription
                    #if os(iOS)
                    liveActivityManager.endActivity(for: id.uuidString, status: "Failed")
                    #elseif os(macOS)
                    notificationService.notifyDownloadFailed(
                        downloadId: id,
                        title: title,
                        errorMessage: error.localizedDescription
                    )
                    #endif
                }
            } else {
                downloads[index].status = .failed
                downloads[index].errorMessage = error.localizedDescription
                #if os(iOS)
                liveActivityManager.endActivity(for: id.uuidString, status: "Failed")
                #else
                notificationService.notifyDownloadFailed(
                    downloadId: id,
                    title: title,
                    errorMessage: error.localizedDescription
                )
                #endif
            }
        }

        downloaders[id] = nil
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
        lastNotificationUpdate[id] = nil
        persistDownloads()
    }

    // MARK: - Persistence

    private func persistDownloads() {
        var itemsToPersist = downloads

        // Normalize transient states for persistence
        for i in itemsToPersist.indices {
            switch itemsToPersist[i].status {
            case .downloading:
                // Active downloads become paused on persist (will resume on next launch)
                itemsToPersist[i].status = .paused
                itemsToPersist[i].speed = 0
                itemsToPersist[i].eta = 0
            case .converting:
                // Converting downloads become failed on persist (can't resume conversion)
                itemsToPersist[i].status = .failed
                itemsToPersist[i].errorMessage = "Conversion interrupted"
            default:
                break
            }
        }

        do {
            let data = try JSONEncoder().encode(itemsToPersist)
            try data.write(to: Self.persistenceURL, options: .atomic)
        } catch {
            logger.error("[DownloadManager] Failed to persist downloads: \(error)")
        }
    }

    private func loadPersistedDownloads() {
        guard FileManager.default.fileExists(atPath: Self.persistenceURL.path) else { return }

        do {
            let data = try Data(contentsOf: Self.persistenceURL)
            var loaded = try JSONDecoder().decode([DownloadItem].self, from: data)

            // Mark any downloads that were .downloading as .failed (interrupted)
            for i in loaded.indices {
                if loaded[i].status == .downloading {
                    loaded[i].status = .failed
                    loaded[i].errorMessage = "Download interrupted — tap to retry"
                }
            }

            downloads = loaded
            logger.info("[DownloadManager] Loaded \(loaded.count) persisted downloads")
        } catch {
            logger.error("[DownloadManager] Failed to load persisted downloads: \(error)")
        }
    }
}

// MARK: - Preview

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
