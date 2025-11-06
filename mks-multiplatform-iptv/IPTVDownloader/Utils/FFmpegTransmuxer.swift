import Foundation

/// Handles transmuxing MKV streams to MP4 format using FFmpeg
class FFmpegTransmuxer {
    
    /// Path to ffmpeg binary
    private static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
    
    /// Transmux MKV stream to MP4 format and write to output handle
    /// - Parameters:
    ///   - url: Source MKV stream URL
    ///   - outputHandle: FileHandle to write the MP4 output
    /// - Throws: Error if ffmpeg is not found or process fails
    static func transmuxMKVToMP4Stream(from url: URL, to outputHandle: FileHandle) async throws {
        #if os(macOS)
        print("[FFmpegTransmuxer] Starting transmux from \(url) to MP4")
        
        // Check if ffmpeg exists
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            print("[FFmpegTransmuxer] ❌ FFmpeg not found at \(ffmpegPath)")
            throw TransmuxError.ffmpegNotFound
        }
        
        // Create process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        // Configure arguments for transmuxing
        process.arguments = [
            "-i", url.absoluteString,           // Input URL
            "-c:v", "copy",                     // Copy video codec (no re-encoding)
            "-c:a", "copy",                     // Copy audio codec (no re-encoding)
            "-movflags", "+frag_keyframe+empty_moov+delay_moov+default_base_moof", // Enable streaming-friendly MP4 with AC3 support
            "-frag_duration", "1000000",        // 1 second fragments
            "-f", "mp4",                        // Output format
            "-"                                 // Output to stdout
        ]
        
        // Set up pipes
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Handle output data
        let outputSource = DispatchSource.makeReadSource(
            fileDescriptor: outputPipe.fileHandleForReading.fileDescriptor,
            queue: .global()
        )
        
        outputSource.setEventHandler {
            let data = outputPipe.fileHandleForReading.availableData
            if !data.isEmpty {
                do {
                    try outputHandle.write(contentsOf: data)
                    print("[FFmpegTransmuxer] Written \(data.count) bytes")
                } catch {
                    print("[FFmpegTransmuxer] ❌ Error writing data: \(error)")
                }
            }
        }
        
        outputSource.setCancelHandler {
            outputPipe.fileHandleForReading.closeFile()
        }
        
        outputSource.resume()
        
        // Handle error output for logging
        let errorSource = DispatchSource.makeReadSource(
            fileDescriptor: errorPipe.fileHandleForReading.fileDescriptor,
            queue: .global()
        )
        
        errorSource.setEventHandler {
            let data = errorPipe.fileHandleForReading.availableData
            if !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                print("[FFmpegTransmuxer] FFmpeg: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        errorSource.setCancelHandler {
            errorPipe.fileHandleForReading.closeFile()
        }
        
        errorSource.resume()
        
        // Start process
        do {
            print("[FFmpegTransmuxer] Starting ffmpeg process...")
            try process.run()
            
            // Wait for process to complete
            await withCheckedContinuation { continuation in
                process.terminationHandler = { process in
                    outputSource.cancel()
                    errorSource.cancel()
                    
                    if process.terminationStatus == 0 {
                        print("[FFmpegTransmuxer] ✅ Transmux completed successfully")
                    } else {
                        print("[FFmpegTransmuxer] ❌ FFmpeg exited with status: \(process.terminationStatus)")
                    }
                    
                    continuation.resume()
                }
            }
            
            if process.terminationStatus != 0 {
                throw TransmuxError.processFailure(status: Int(process.terminationStatus))
            }
            
        } catch {
            outputSource.cancel()
            errorSource.cancel()
            print("[FFmpegTransmuxer] ❌ Failed to start ffmpeg: \(error)")
            throw TransmuxError.processStartFailure(error)
        }
        #else
        // On iOS, we can't run FFmpeg process
        print("[FFmpegTransmuxer] ⚠️ FFmpeg not available on iOS")
        throw TransmuxError.notAvailableOnPlatform
        #endif
    }
}

// MARK: - Errors
enum TransmuxError: LocalizedError {
    case ffmpegNotFound
    case processStartFailure(Error)
    case processFailure(status: Int)
    case notAvailableOnPlatform
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found at expected path. Please install with: brew install ffmpeg"
        case .processStartFailure(let error):
            return "Failed to start FFmpeg process: \(error.localizedDescription)"
        case .processFailure(let status):
            return "FFmpeg process failed with exit status: \(status)"
        case .notAvailableOnPlatform:
            return "FFmpeg transmuxing is not available on this platform"
        }
    }
}