import Foundation
import Combine
import os

class VideoDownloader: NSObject, URLSessionDataDelegate {
    private enum Constants {
        static let bufferSize: Int = 2 * 1024 * 1024
        static let maxRetries = 3
        static let retryDelay: TimeInterval = 1.0
        static let speedSampleCount = 10
    }
    
    private let profile: IPTVProfile
    
    enum DownloadError: Error {
        case invalidURL
        case invalidResponse
        case downloadFailed(String)
        case fileError(String)
        case downloadCancelled
        case downloadPaused
    }
    
     // TODO: [DOWNLOAD-SYSTEM-OVERHAUL] — Complete rewrite of post-download conversion
     // Currently disabled: old FFmpegKit-based convertToMOVAsync was removed.
     // This flag and the conversion code block below must be replaced with:
     //
     // 1. MULTIPLE OUTPUT FORMATS — Not just MOV. Support MP4, MKV, MOV.
     //    Let the user choose target container format in the download dialog
     //    (MediaDetailSheet download options). Default: MP4 for Apple ecosystem.
     //
     // 2. STREAM-DOWNLOAD + TRANSMUX FUSION — Replace URLSession bulk download
     //    with TransmuxCore's streaming FFmpeg I/O approach:
     //    - Use FFmpeg's avio/protocol layer to stream-download + remux simultaneously
     //    - Progressive write to final container format during download (no post-download conversion)
     //    - Much faster than download-then-convert: single pass, no temp files
     //    - Leverage TransmuxingService for the remux pipeline
     //
     // 3. PLAY WHILE DOWNLOADING — Enable playback once ~10% is buffered:
     //    - TransmuxServer serves partial fMP4 segments as they're written
     //    - Seeking restricted to already-downloaded/transmuxed fragments only
     //    - Cannot seek to future positions (only within existing written data)
     //    - Fullness gate: minimum 10% buffered before allowing playback start
     //    - AVPlayer reads from TransmuxServer while download continues in background
     //
     // 4. METADATA EMBEDDING (Subler-like) — After download/transmux completes:
     //    - Use FFmpegMetadataWriter + MetadataEnrichmentService (already in app)
     //    - Embed title, genre, cast, director, plot, year, rating into MP4/MKV/MOV
     //    - Embed cover artwork as attached picture stream
     //    - Automatic: enrich from TMDB/OMDB, then write to final file
     //
     // 5. PAUSE AND RESUME DOWNLOADS:
     //    - HTTP Range request support for resuming partial downloads
     //    - Persist download state (bytes downloaded, last fragment) across app restarts
     //    - Resume transmux from last written fragment position
     //    - Handle server support detection (Accept-Ranges header)
     //
     // 6. UPDATE DOWNLOAD DIALOG — MediaDetailSheet must show:
     //    - Format picker (MP4/MKV/MOV) instead of hardcoded MOV toggle
     //    - Quality/codec info from FFProbeUtilities
     //    - Estimated file size
     //    - "Play while downloading" toggle
     //
     // See: VideoDownloader, TransmuxingService, FFmpegMetadataWriter,
     //      MetadataEnrichmentService, MediaDetailSheet
     var shouldConvertToMOV: Bool = false
     
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
