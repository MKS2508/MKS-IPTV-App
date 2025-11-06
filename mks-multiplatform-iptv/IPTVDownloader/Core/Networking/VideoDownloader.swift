import Foundation
import Combine
import os
//import ffmpegkit


extension VideoDownloader {
    func convertToMOVAsync(inputPath: String, outputPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // Construimos el comando FFmpeg
        let command = "-y -i \"\(inputPath)\" -c copy \"\(outputPath)\""
        
        // Llamada ASÍNCRONA
//        FFmpegKit.executeAsync(command) { session in
//            let returnCode = session?.getReturnCode()
//            
//            if let returnCode = returnCode, ReturnCode.isSuccess(returnCode) {
//                print("Remux a MOV completado (asíncrono). Path: \(outputPath)")
//                completion(.success(()))
//            } else if let returnCode = returnCode, ReturnCode.isCancel(returnCode) {
//                print("La operación FFmpeg fue cancelada.")
//                completion(.failure(NSError(domain: "FFmpegKit", code: Int(returnCode.getValue()), userInfo: [NSLocalizedDescriptionKey: "Operación cancelada"])))
//            } else {
//                let errorLogs = session?.getAllLogsAsString() ?? "No logs available"
//                let errorDescription = "Ocurrió un error al remuxear. returnCode: \(String(describing: returnCode))"
//                print(errorDescription)
//                print("Logs:\n\(errorLogs)")
//                
//                completion(.failure(NSError(domain: "FFmpegKit", code: Int(returnCode?.getValue() ?? -1), userInfo: [NSLocalizedDescriptionKey: errorDescription])))
//            }
//        }
    }
}

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
    
     var shouldConvertToMOV: Bool = false // Propiedad configurable para habilitar/deshabilitar la conversión
     
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
        configuration.httpShouldUsePipelining = true
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
            
            if shouldConvertToMOV, let path = currentDestinationPath {
                let outputPath = (path as NSString).deletingPathExtension + ".mov"
                
                // Cambiamos el estado a `converting` antes de iniciar la conversión
                currentState = .converting
                
                // Ejecutamos la conversión asíncrona
                convertToMOVAsync(inputPath: path, outputPath: outputPath) { [weak self] result in
                    guard let self = self else { return }
                    
                    switch result {
                    case .success:
                        self.logger.info("¡Conversión a MOV finalizada!: \(outputPath)")
                        self.currentState = .completed // Cambio de estado al completar la conversión
                    case .failure(let conversionError):
                        self.logger.error("Error al convertir a MOV: \(conversionError.localizedDescription)")
                        self.currentState = .error(conversionError) // Cambio de estado en caso de error
                    }
                    
                    self.downloadContinuation?.resume()
                    self.progressSubject.send(completion: .finished)
                }
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
