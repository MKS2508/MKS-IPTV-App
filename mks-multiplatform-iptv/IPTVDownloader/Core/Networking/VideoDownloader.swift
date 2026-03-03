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
        
        /// File extension for this format
        var fileExtension: String {
            switch self {
            case .mp4: return "mp4"
            case .mkv: return "mkv"
            case .mov: return "mov"
            }
        }
        
        /// FFmpeg format name for output
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
    
     // TODO: [DOWNLOAD-SYSTEM-OVERHAUL] — IN PROGRESS
     // Implementing TransmuxCore-based streaming download pipeline.
     // See full specification below.
     var outputFormat: OutputFormat = .mp4
     
     enum DownloadState: Equatable {
         case notStarted
         case downloading
         case paused
         case completed
         case cancelled
         case converting // Nuevo estado para la conversión
         case error(Error)
         
         static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
             switch (lhs, rhs) {
             case (.notStarted, .notStarted),
                  (.downloading, .downloading),
                  (.paused, .paused),
                  (.completed, .completed),
                  (.cancelled, .cancelled),
                  (.converting, .converting): // Comparación para el nuevo estado
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
    
    private var downloadedBytes: Int64 = 0
    private var totalBytes: Int64 = 0
    private var startTime: Date?
    private var speedSamples: [Double] = []
    private var buffer = Data(capacity: Constants.bufferSize)
    private var currentState: DownloadState = .notStarted
    private var currentVodId: String?
    private var currentDestinationPath: String?
    
    
    private let progressSubject = PassthroughSubject<DownloadProgress, Never>()
    var progressPublisher: AnyPublisher<DownloadProgress, Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    private let logger = Logger(subsystem: "com.example.VideoDownloader", category: "Download")
    private let downloadStateKey = "com.example.VideoDownloader.downloadState"
    
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
    
    
    func cancel() {
        logger.info("Cancelling download for vodID: \(self.currentVodId ?? "unknown")")
        dataTask?.cancel()
        currentState = .cancelled
        clearDownloadState()
        downloadContinuation?.resume(throwing: DownloadError.downloadCancelled)
        downloadContinuation = nil
        closeFileHandle()
    }
    
    func pause() {
        guard case .downloading = currentState else { return }
        logger.info("Pausing download for vodID: \(self.currentVodId ?? "unknown")")
        dataTask?.suspend()
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
    
    // MARK: - TransmuxCore Streaming Download (Stream-Download + Transmux Fusion)
    
    /// Streaming download using TransmuxCore's FFmpeg I/O layer.
    /// Simultaneously downloads and transmuxes to the target container format in a single pass.
    /// Returns a ProgressiveTransmuxSession once the fMP4 header is written, enabling play-while-downloading.
    ///
    /// - Parameters:
    ///   - vodID: The VOD ID from the IPTV server
    ///   - destinationPath: Final output file path
    ///   - vodExtension: Source file extension
    ///   - format: Target container format (MP4/MKV/MOV)
    /// - Returns: ProgressiveTransmuxSession for play-while-downloading support
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
            throw DownloadError.invalidURL
        }
        
        // Ensure destination directory exists
        let fileURL = URL(fileURLWithPath: destinationPath)
        let directoryURL = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            logger.info("Created directory at path: \(directoryURL.path)")
        }
        
        // Start transmux session - this returns once fMP4 header is written
        startTime = Date()
        let session = try await TransmuxingService.shared.startTransmux(from: sourceURL)
        
        logger.info("Transmux session started: \(session.sessionID)")
        logger.info("Output: \(session.outputPath)")
        logger.info("Duration: \(session.duration)s, Expected size: \(session.expectedSize) bytes")
        
        // Update total bytes for progress tracking
        totalBytes = session.expectedSize
        
        // Set up progress monitoring from the session's segmenter
        Task { [weak self] in
            await self?.monitorTransmuxProgress(session: session)
        }
        
        return session
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
                
                let downloadProgress = DownloadProgress(
                    bytesDownloaded: bytesProcessed,
                    totalBytes: session.expectedSize,
                    speed: calculateSpeed(elapsed: Date().timeIntervalSince(startTime ?? Date())),
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
    
    private func download(from urlString: String, to destinationPath: String) async throws {
        guard let url = URL(string: urlString) else {
            throw DownloadError.invalidURL
        }
        
        let fileURL = URL(fileURLWithPath: destinationPath)
        
        do {
            // First, make sure the containing directory exists
            let directoryURL = fileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                logger.info("Created directory at path: \(directoryURL.path)")
            }
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if case .paused = currentState {
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
                // Ensure we can create the file
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
        
        if case .paused = currentState {
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
}

extension VideoDownloader {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        processReceivedData(data)
    }
    // Helper function to get proper iOS file paths
       static func getProperFilePath(filename: String, directory: FileManager.SearchPathDirectory = .documentDirectory) -> String {
           let paths = FileManager.default.urls(for: directory, in: .userDomainMask)
           let documentsDirectory = paths[0]
           let filePath = documentsDirectory.appendingPathComponent(filename).path
           return filePath
       }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        flushBuffer()
        
        if let error = error as? URLError, error.code == .cancelled {
            logger.info("Download was cancelled")
            currentState = .cancelled
            progressSubject.send(completion: .finished)
            downloadContinuation?.resume(throwing: DownloadError.downloadCancelled)
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
            
            // TODO: [DOWNLOAD-SYSTEM-OVERHAUL] — Post-download conversion disabled.
            // Old FFmpegKit convertToMOVAsync removed. Replace with TransmuxCore
            // stream-download+transmux fusion. See TODO at shouldConvertToMOV property.
            //
            // if shouldConvertToMOV, let path = currentDestinationPath {
            //     let outputPath = (path as NSString).deletingPathExtension + ".mov"
            //     currentState = .converting
            //     // ... TransmuxCore-based conversion pipeline here ...
            // }
            if false /* shouldConvertToMOV — disabled until TransmuxCore integration */ {
                // Placeholder: will be replaced by TransmuxCore stream+transmux pipeline
            } else {
                downloadContinuation?.resume()
                progressSubject.send(completion: .finished)
            }
        }
        
        downloadContinuation = nil
        closeFileHandle()
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            switch currentState {
            case .paused:
                if httpResponse.expectedContentLength > 0 {
                    totalBytes = downloadedBytes + httpResponse.expectedContentLength
                }
            default:
                totalBytes = httpResponse.expectedContentLength > 0 ? httpResponse.expectedContentLength : 0
            }
            logger.info("Expected content length: \(self.totalBytes) bytes")
        }
        completionHandler(.allow)
    }
}
