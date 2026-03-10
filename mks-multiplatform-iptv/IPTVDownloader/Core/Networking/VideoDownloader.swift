import Foundation
import Combine
import os
import TransmuxCore

class VideoDownloader: NSObject, URLSessionDataDelegate {
    private enum Constants {
        static let bufferSize: Int = 2 * 1024 * 1024
        static let maxRetries = 3
        static let retryDelay: TimeInterval = 1.0
        static let speedSampleCount = 10
        static let playbackBufferThreshold: Double = 0.10 // 10% buffer for play-while-downloading
    }

    private let profile: IPTVProfile

    /// Output container format for downloaded content
    enum OutputFormat: String, CaseIterable, Codable {
        case mp4 = "MP4"
        case mkv = "MKV"
        case mov = "MOV"

        var fileExtension: String {
            switch self {
            case .mp4: return "mp4"
            case .mkv: return "mkv"
            case .mov: return "mov"
            }
        }

        var ffmpegFormat: String {
            switch self {
            case .mp4: return "mp4"
            case .mkv: return "matroska"
            case .mov: return "mov"
            }
        }
    }

    enum DownloadError: Error {
        case invalidURL
        case invalidResponse
        case downloadFailed(String)
        case fileError(String)
        case downloadCancelled
        case downloadPaused
    }

    var outputFormat: OutputFormat = .mp4

    enum DownloadState: Equatable {
        case notStarted
        case downloading
        case paused
        case completed
        case cancelled
        case converting
        case error(Error)

        static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted),
                 (.downloading, .downloading),
                 (.paused, .paused),
                 (.completed, .completed),
                 (.cancelled, .cancelled),
                 (.converting, .converting):
                return true
            case (.error(let lhsError), .error(let rhsError)):
                return lhsError.localizedDescription == rhsError.localizedDescription
            default:
                return false
            }
        }
    }

    struct DownloadProgress {
        let bytesDownloaded: Int64
        let totalBytes: Int64
        let speed: Double
        let eta: TimeInterval

        var percentComplete: Double {
            guard totalBytes > 0 else { return 0 }
            return min((Double(bytesDownloaded) / Double(totalBytes)) * 100, 100)
        }
    }

    private var session: URLSession!
    private var dataTask: URLSessionDataTask?
    private var outputFileHandle: FileHandle?
    private var downloadContinuation: CheckedContinuation<Void, Error>?

    private(set) var downloadedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private var startTime: Date?
    private var speedSamples: [Double] = []
    private var buffer = Data(capacity: Constants.bufferSize)
    private(set) var currentState: DownloadState = .notStarted
    private var currentVodId: String?
    private var currentDestinationPath: String?

    /// Active transmux session ID — set during downloadWithTransmux, used by cancel/pause
    var transmuxSessionID: String?

    /// Whether this downloader is running a transmux-based download
    var isTransmuxDownload: Bool { transmuxSessionID != nil }

    private let progressSubject = PassthroughSubject<DownloadProgress, Never>()
    var progressPublisher: AnyPublisher<DownloadProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    private let logger = Logger(subsystem: "com.mks.iptv.VideoDownloader", category: "Download")
    private let downloadStateKey = "com.mks.iptv.VideoDownloader.downloadState"

    init(profile: IPTVProfile) {
        self.profile = profile
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 3600
        configuration.httpShouldUsePipelining = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil

        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        logger.info("VideoDownloader initialized")
    }

    // MARK: - Control

    func cancel() {
        logger.info("Cancelling download for vodID: \(self.currentVodId ?? "unknown")")

        // Cancel HTTP download task
        dataTask?.cancel()

        // Cancel transmux session if active
        if let sessionID = transmuxSessionID {
            logger.info("Cancelling transmux session: \(sessionID)")
            Task {
                await TransmuxingService.shared.cancelTransmux(sessionID: sessionID)
                await TransmuxingService.shared.cleanup(sessionID: sessionID)
            }
            transmuxSessionID = nil
        }

        currentState = .cancelled
        clearDownloadState()
        downloadContinuation?.resume(throwing: DownloadError.downloadCancelled)
        downloadContinuation = nil
        closeFileHandle()
    }

    func pause() {
        guard case .downloading = currentState else { return }
        logger.info("Pausing download for vodID: \(self.currentVodId ?? "unknown")")

        if isTransmuxDownload {
            // For transmux downloads: cancel the transmux session but keep output file
            if let sessionID = transmuxSessionID {
                logger.info("Pausing transmux session (cancel but keep file): \(sessionID)")
                Task {
                    await TransmuxingService.shared.cancelTransmux(sessionID: sessionID)
                }
            }
        } else {
            // For HTTP downloads: cancel the data task (we'll resume with Range header)
            dataTask?.cancel()
        }

        // Flush any buffered data before pausing
        flushBuffer()

        currentState = .paused
        saveDownloadState()
        downloadContinuation?.resume()
        downloadContinuation = nil
        closeFileHandle()
    }

    func resume() async throws {
        guard case .paused = currentState else { return }
        logger.info("Resuming download for vodID: \(self.currentVodId ?? "unknown")")

        guard let vodId = currentVodId,
              let destinationPath = currentDestinationPath else {
            throw DownloadError.downloadFailed("Missing download information")
        }

        // Ensure file exists and is writable
        let fileURL = URL(fileURLWithPath: destinationPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DownloadError.fileError("Download file not found")
        }

        do {
            outputFileHandle = try FileHandle(forWritingTo: fileURL)
            try outputFileHandle?.seekToEnd()
        } catch {
            logger.error("Failed to open file for resuming: \(error.localizedDescription)")
            throw DownloadError.fileError("Cannot open file for resuming: \(error.localizedDescription)")
        }

        let urlString = IPTVConfiguration.buildMovieURL(profile: profile, vodID: vodId, vodExtension: "mp4")
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("bytes=\(downloadedBytes)-", forHTTPHeaderField: "Range")
        IPTVConfiguration.defaultRequestHeaders().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        dataTask = session.dataTask(with: request)
        currentState = .downloading
        startTime = Date()

        try await streamData()
    }

    // MARK: - Download Methods

    /// Download a movie via direct HTTP (no transmux). Full pause/resume via Range headers.
    func downloadMovie(vodID: String, to destinationPath: String, vodExtension: String) async throws {
        currentVodId = vodID
        currentDestinationPath = destinationPath
        currentState = .downloading
        downloadedBytes = 0
        totalBytes = 0

        if let (savedBytes, _) = loadDownloadState(forVodId: vodID) {
            downloadedBytes = savedBytes
        }

        logger.info("Starting movie download: vodID=\(vodID)")
        let urlString = IPTVConfiguration.buildMovieURL(profile: profile, vodID: vodID, vodExtension: vodExtension)
        try await download(from: urlString, to: destinationPath)
    }

    /// Download a series episode via direct HTTP (no transmux). Full pause/resume via Range headers.
    func downloadSerie(vodID: String, to destinationPath: String, vodExtension: String) async throws {
        currentVodId = vodID
        currentDestinationPath = destinationPath
        currentState = .downloading
        downloadedBytes = 0
        totalBytes = 0

        if let (savedBytes, _) = loadDownloadState(forVodId: vodID) {
            downloadedBytes = savedBytes
        }

        logger.info("Starting series download: vodID=\(vodID)")
        let urlString = IPTVConfiguration.buildSeriesURL(profile: profile, vodID: vodID, vodExtension: vodExtension)
        try await download(from: urlString, to: destinationPath)
    }

    /// Download for saving — thin wrapper that routes to downloadMovie or downloadSerie based on media type.
    /// Uses direct HTTP download (wire speed), no transmux involved.
    func downloadForSave(
        vodID: String,
        to destinationPath: String,
        vodExtension: String,
        isMovie: Bool
    ) async throws {
        if isMovie {
            try await downloadMovie(vodID: vodID, to: destinationPath, vodExtension: vodExtension)
        } else {
            try await downloadSerie(vodID: vodID, to: destinationPath, vodExtension: vodExtension)
        }
    }

    // MARK: - TransmuxCore Streaming Download (Stream-Download + Transmux Fusion)

    /// Streaming download using TransmuxCore's FFmpeg I/O layer.
    /// Simultaneously downloads and transmuxes to the target container format in a single pass.
    /// Returns a ProgressiveTransmuxSession once the fMP4 header is written, enabling play-while-downloading.
    func downloadWithTransmux(
        vodID: String,
        to destinationPath: String,
        vodExtension: String,
        format: OutputFormat,
        isMovie: Bool
    ) async throws -> ProgressiveTransmuxSession {
        currentVodId = vodID
        currentDestinationPath = destinationPath
        currentState = .downloading
        downloadedBytes = 0
        totalBytes = 0

        logger.info("Starting streaming transmux download: vodID=\(vodID), format=\(format.rawValue)")

        // Build source URL from IPTV configuration
        let urlString = isMovie
            ? IPTVConfiguration.buildMovieURL(profile: profile, vodID: vodID, vodExtension: vodExtension)
            : IPTVConfiguration.buildSeriesURL(profile: profile, vodID: vodID, vodExtension: vodExtension)

        guard let sourceURL = URL(string: urlString) else {
            logger.error("Invalid URL: \(urlString)")
            throw DownloadError.invalidURL
        }

        logger.info("Source URL: \(sourceURL.absoluteString.prefix(80))...")

        // Ensure destination directory exists
        let fileURL = URL(fileURLWithPath: destinationPath)
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            logger.info("Created directory at path: \(directoryURL.path)")
        }
        logger.info("Destination: \(destinationPath)")

        // Start transmux session - this returns once fMP4 header is written
        startTime = Date()
        logger.info("Calling TransmuxingService.startTransmux...")

        let tmxSession: ProgressiveTransmuxSession
        do {
            tmxSession = try await TransmuxingService.shared.startTransmux(from: sourceURL)
        } catch {
            logger.error("TransmuxingService.startTransmux FAILED: \(error)")
            logger.error("Error type: \(type(of: error)), description: \(error.localizedDescription)")
            throw error
        }

        // Store session ID for cancel/pause support
        transmuxSessionID = tmxSession.sessionID

        logger.info("Transmux session started: \(tmxSession.sessionID)")
        logger.info("Output: \(tmxSession.outputPath)")
        logger.info("Duration: \(tmxSession.duration)s, Expected size: \(tmxSession.expectedSize) bytes")

        // Update total bytes for progress tracking
        totalBytes = tmxSession.expectedSize

        // Set up progress monitoring from the session's segmenter
        Task { [weak self] in
            await self?.monitorTransmuxProgress(session: tmxSession)
        }

        return tmxSession
    }

    /// Monitor transmux progress and emit progress updates
    private func monitorTransmuxProgress(session: ProgressiveTransmuxSession) async {
        let segmenter = session.segmenter

        // Poll for progress updates while transmux is active
        while currentState == .downloading {
            let bufferedTime = await segmenter.latestBufferedSourceTime()
            let duration = session.duration

            if duration > 0 {
                let progress = bufferedTime / duration
                let bytesProcessed = Int64(Double(session.expectedSize) * progress)

                // FIX: Update downloadedBytes so calculateSpeed() and calculateETA() work
                downloadedBytes = bytesProcessed
                totalBytes = session.expectedSize

                let elapsed = Date().timeIntervalSince(startTime ?? Date())

                let downloadProgress = DownloadProgress(
                    bytesDownloaded: bytesProcessed,
                    totalBytes: session.expectedSize,
                    speed: calculateSpeed(elapsed: elapsed),
                    eta: calculateETA()
                )
                progressSubject.send(downloadProgress)
            }

            // Check if transmux is complete
            if bufferedTime >= duration {
                currentState = .completed
                progressSubject.send(completion: .finished)
                break
            }

            // Poll interval
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Check if enough content is buffered for play-while-downloading (10% threshold)
    func isReadyForPlayback(session: ProgressiveTransmuxSession) async -> Bool {
        let bufferedTime = await session.segmenter.latestBufferedSourceTime()
        let duration = session.duration
        guard duration > 0 else { return false }

        let bufferPercentage = bufferedTime / duration
        return bufferPercentage >= Constants.playbackBufferThreshold
    }

    /// Get the current buffer percentage for play-while-downloading
    func bufferPercentage(session: ProgressiveTransmuxSession) async -> Double {
        let bufferedTime = await session.segmenter.latestBufferedSourceTime()
        let duration = session.duration
        guard duration > 0 else { return 0 }
        return (bufferedTime / duration) * 100
    }

    // MARK: - Internal HTTP Download

    private func download(from urlString: String, to destinationPath: String) async throws {
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }

        let fileURL = URL(fileURLWithPath: destinationPath)

        do {
            // Ensure the containing directory exists
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                logger.info("Created directory at path: \(directoryURL.path)")
            }

            if FileManager.default.fileExists(atPath: fileURL.path) {
                if downloadedBytes > 0 {
                    // Resuming: open existing file and seek to end
                    outputFileHandle = try FileHandle(forWritingTo: fileURL)
                    try outputFileHandle?.seekToEnd()
                    logger.info("Resuming download to existing file at: \(fileURL.path)")
                } else {
                    try FileManager.default.removeItem(at: fileURL)
                    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) {
                        throw DownloadError.fileError("Failed to create file at path: \(fileURL.path)")
                    }
                    outputFileHandle = try FileHandle(forWritingTo: fileURL)
                    logger.info("Created new file at: \(fileURL.path)")
                }
            } else {
                if !FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) {
                    throw DownloadError.fileError("Failed to create file at path: \(fileURL.path)")
                }
                outputFileHandle = try FileHandle(forWritingTo: fileURL)
                logger.info("Created new file at: \(fileURL.path)")
            }
        } catch {
            logger.error("File handling error: \(error.localizedDescription)")
            throw DownloadError.fileError("Cannot prepare file for writing: \(error.localizedDescription)")
        }

        startTime = Date()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use Range header for resuming
        if downloadedBytes > 0 {
            request.setValue("bytes=\(downloadedBytes)-", forHTTPHeaderField: "Range")
        }

        IPTVConfiguration.defaultRequestHeaders().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        dataTask = session.dataTask(with: request)
        try await streamData()
    }

    private func streamData() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            dataTask?.resume()
        }
    }

    private func processReceivedData(_ data: Data) {
        buffer.append(data)
        if buffer.count >= Constants.bufferSize {
            flushBuffer()
        }

        let currentTotalBytes = downloadedBytes + Int64(buffer.count)
        let progress = DownloadProgress(
            bytesDownloaded: min(currentTotalBytes, totalBytes),
            totalBytes: totalBytes,
            speed: calculateSpeed(elapsed: Date().timeIntervalSince(startTime ?? Date())),
            eta: calculateETA()
        )
        progressSubject.send(progress)
    }

    private func flushBuffer() {
        guard !buffer.isEmpty else { return }

        do {
            try outputFileHandle?.write(contentsOf: buffer)
            downloadedBytes += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
        } catch {
            logger.error("Error writing data to file: \(error.localizedDescription)")
            currentState = .error(error)
            downloadContinuation?.resume(throwing: DownloadError.fileError(error.localizedDescription))
        }
    }

    private func closeFileHandle() {
        if let fileHandle = outputFileHandle {
            do {
                try fileHandle.synchronize()
                try fileHandle.close()
            } catch {
                logger.error("Error closing file handle: \(error.localizedDescription)")
            }
            outputFileHandle = nil
        }
    }

    private func calculateSpeed(elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return Double(downloadedBytes) / elapsed / 1024 / 1024
    }

    private func calculateETA() -> TimeInterval {
        guard let startTime = startTime,
              totalBytes > 0,
              downloadedBytes > 0 else { return 0 }

        let elapsed = Date().timeIntervalSince(startTime)
        let bytesPerSecond = Double(downloadedBytes) / elapsed
        let remainingBytes = Double(totalBytes - downloadedBytes)

        return bytesPerSecond > 0 ? remainingBytes / bytesPerSecond : 0
    }

    // MARK: - Download State Persistence

    private func saveDownloadState() {
        guard let vodId = currentVodId else { return }

        let downloadState: [String: Any] = [
            "vodId": vodId,
            "bytesDownloaded": downloadedBytes,
            "destinationPath": currentDestinationPath ?? "",
            "timestamp": Date().timeIntervalSince1970
        ]

        UserDefaults.standard.set(downloadState, forKey: "\(downloadStateKey).\(vodId)")
    }

    private func loadDownloadState(forVodId vodId: String) -> (Int64, String)? {
        guard let state = UserDefaults.standard.dictionary(forKey: "\(downloadStateKey).\(vodId)"),
              let bytes = state["bytesDownloaded"] as? Int64,
              let path = state["destinationPath"] as? String else {
            return nil
        }
        return (bytes, path)
    }

    private func clearDownloadState() {
        guard let vodId = currentVodId else { return }
        UserDefaults.standard.removeObject(forKey: "\(downloadStateKey).\(vodId)")
    }

    // MARK: - Helper

    static func getProperFilePath(filename: String, directory: FileManager.SearchPathDirectory = .documentDirectory) -> String {
        let paths = FileManager.default.urls(for: directory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        return documentsDirectory.appendingPathComponent(filename).path
    }
}

// MARK: - URLSessionDataDelegate

extension VideoDownloader {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        processReceivedData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        flushBuffer()

        if let error = error as? URLError, error.code == .cancelled {
            // Check if this was a pause (not a real cancel)
            if currentState == .paused {
                logger.info("Download task cancelled for pause")
                return
            }
            logger.info("Download was cancelled")
            currentState = .cancelled
            progressSubject.send(completion: .finished)
            downloadContinuation?.resume(throwing: DownloadError.downloadCancelled)
            downloadContinuation = nil
            return
        }

        if let error = error {
            logger.error("URLSession task failed: \(error.localizedDescription)")
            currentState = .error(error)
            downloadContinuation?.resume(throwing: error)
            progressSubject.send(completion: .finished)
        } else {
            logger.info("URLSession task completed successfully")
            currentState = .completed
            downloadContinuation?.resume()
            progressSubject.send(completion: .finished)
        }

        downloadContinuation = nil
        closeFileHandle()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            if downloadedBytes > 0 {
                // Resuming: content-length is remaining bytes
                if httpResponse.expectedContentLength > 0 {
                    totalBytes = downloadedBytes + httpResponse.expectedContentLength
                }
            } else {
                totalBytes = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : 0
            }
            logger.info("Expected content length: \(self.totalBytes) bytes")
        }
        completionHandler(.allow)
    }
}
