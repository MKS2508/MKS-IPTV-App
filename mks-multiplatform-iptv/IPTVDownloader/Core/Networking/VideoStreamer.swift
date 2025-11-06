//import Foundation
//import ffmpegkit
//
//final class VideoStreamer {
//    func transcodeRemoteMKVToMP4(
//        vodID: String,
//        isMovie: Bool,
//        onFileCreated: @escaping (String) -> Void,
//        completion: @escaping (Result<String, Error>) -> Void
//    ) {
//        // 1) Construct the remote URL (.mkv)
//        let remoteURL: String
//        if isMovie {
//            remoteURL = IPTVConfiguration.buildMovieURL(vodID: vodID, vodExtension: IPTVConfiguration.fileExtension)
//        } else {
//            remoteURL = IPTVConfiguration.buildSeriesURL(vodID: vodID, vodExtension: IPTVConfiguration.fileExtension)
//        }
//        
//        // 2) Local output path for MP4
//        let localMP4Path = NSTemporaryDirectory().appending("mp4Output_\(vodID)/output.mp4")
//        
//        // Create the mp4Output folder if it doesn't exist
//        do {
//            try FileManager.default.createDirectory(
//                atPath: NSTemporaryDirectory().appending("mp4Output_\(vodID)"),
//                withIntermediateDirectories: true,
//                attributes: nil
//            )
//        } catch {
//            completion(.failure(error))
//            return
//        }
//        
//        // 3) Custom headers
//        let headersDictionary = IPTVConfiguration.defaultRequestHeaders()
//        let headerLines = headersDictionary
//            .map { "\($0.key): \($0.value)\\r\\n" }
//            .joined()
//        
//        // 4) Build the FFmpeg command
//        let command = """
//        -y \
//        -headers "\(headerLines)" \
//        -i "\(remoteURL)" \
//        -c copy \
//        -sn \
//        -f mp4 \
//        -movflags frag_keyframe+empty_moov+default_base_moof \
//        "\(localMP4Path)"
//        """
//        
//        // 5) Start our local server for that folder
//        LocalHTTPServer.shared.startServer(filePath:localMP4Path, vodID: vodID) {
//            print("HTTP server started successfully")
//        }
//        
//        // 6) Calculate the HTTP URL for the MP4 file
//        let httpBaseURL = LocalHTTPServer.shared.baseURL(for: vodID)?
//            .appendingPathComponent("output.mp4")
//        
//        // Start checking for file creation
//        self.checkForFileCreation(filePath: localMP4Path, interval: 0.5) { fileCreated in
//            if fileCreated {
//                if let mp4HTTPURL = httpBaseURL?.absoluteString {
//                    onFileCreated(mp4HTTPURL)
//                }
//            }
//        }
//        
//        // 7) Execute asynchronously with FFmpegKit
//        FFmpegKit.executeAsync(command) { session in
//            guard let returnCode = session?.getReturnCode() else {
//                completion(.failure(NSError(domain: "VideoStreamer",
//                                            code: -1,
//                                            userInfo: [NSLocalizedDescriptionKey: "No return code from FFmpegKit"])))
//                return
//            }
//            
//            if ReturnCode.isSuccess(returnCode) {
//                // Success: Return the HTTP URL of the MP4 file
//                if let mp4HTTPURL = httpBaseURL?.absoluteString {
//                    completion(.success(mp4HTTPURL))
//                } else {
//                    completion(.failure(NSError(domain: "VideoStreamer",
//                                                code: -2,
//                                                userInfo: [NSLocalizedDescriptionKey: "No webserver URL"])))
//                }
//            } else {
//                // Failure
//                let logs = session?.getAllLogsAsString() ?? "No logs"
//                let errorDescription = """
//                Error transcoding with return code: \(returnCode.getValue())
//                Logs:
//                \(logs)
//                """
//                completion(.failure(NSError(domain: "VideoStreamer",
//                                            code: Int(returnCode.getValue()),
//                                            userInfo: [NSLocalizedDescriptionKey: errorDescription])))
//            }
//        }
//    }
//    
//    private func checkForFileCreation(filePath: String, interval: TimeInterval, completion: @escaping (Bool) -> Void) {
//        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
//            if FileManager.default.fileExists(atPath: filePath) {
//                timer.invalidate()
//                completion(true)
//            }
//        }
//    }
//}
//
