import Foundation

#if os(iOS) || os(tvOS)
// FFmpegKit para iOS/tvOS - será agregado como dependencia
// import FFmpegKit
#endif

// MARK: - Error Types
enum FFProbeError: Error, LocalizedError {
    case ffprobeNotFound
    case invalidURL
    case executionFailed(String)
    case parsingFailed(String)
    case networkError(String)
    case invalidOutput
    
    var errorDescription: String? {
        switch self {
        case .ffprobeNotFound:
            return "FFprobe binary not found. Please ensure FFmpeg is installed."
        case .invalidURL:
            return "Invalid URL provided for analysis."
        case .executionFailed(let message):
            return "FFprobe execution failed: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse FFprobe output: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidOutput:
            return "FFprobe returned invalid or empty output."
        }
    }
}

// MARK: - Data Models
struct StreamMetadata {
    let formatName: String
    let duration: Double?
    let videoCodec: String?
    let audioCodec: String?
    let isCompatibleWithAVPlayer: Bool
    
    // Additional metadata that might be useful
    let bitrate: Int?
    let videoWidth: Int?
    let videoHeight: Int?
    let videoFrameRate: Double?
    let audioBitrate: Int?
    let audioSampleRate: Int?
    let audioChannels: Int?
}

// MARK: - FFprobe JSON Response Models
private struct FFProbeResponse: Codable {
    let format: FFProbeFormat?
    let streams: [FFProbeStream]?
}

private struct FFProbeFormat: Codable {
    let formatName: String?
    let formatLongName: String?
    let duration: String?
    let bitRate: String?
    let size: String?
    
    enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case formatLongName = "format_long_name"
        case duration
        case bitRate = "bit_rate"
        case size
    }
}

private struct FFProbeStream: Codable {
    let codecName: String?
    let codecLongName: String?
    let codecType: String?
    let codecTagString: String?
    let width: Int?
    let height: Int?
    let rFrameRate: String?
    let avgFrameRate: String?
    let bitRate: String?
    let sampleRate: String?
    let channels: Int?
    
    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case codecType = "codec_type"
        case codecTagString = "codec_tag_string"
        case width
        case height
        case rFrameRate = "r_frame_rate"
        case avgFrameRate = "avg_frame_rate"
        case bitRate = "bit_rate"
        case sampleRate = "sample_rate"
        case channels
    }
}

// MARK: - FFProbe Utilities
class FFProbeUtilities {
    
    // MARK: - Configuration
    private static let ffprobePaths = [
        // Bundled with app (recommended for distribution)
        Bundle.main.bundlePath + "/Contents/Resources/ffmpeg/ffprobe",
        Bundle.main.bundlePath + "/Contents/MacOS/ffprobe",
        
        // System installations
        "/usr/local/bin/ffprobe",
        "/opt/homebrew/bin/ffprobe",
        "/usr/bin/ffprobe",
        
        // Development paths
        "./Resources/ffmpeg/ffprobe",
        "../Resources/ffmpeg/ffprobe"
    ]
    
    // MARK: - Public Methods
    
    /// Analyzes a remote MKV stream using ffprobe
    /// - Parameter url: The URL of the MKV stream to analyze
    /// - Returns: StreamMetadata containing codec and format information
    /// - Throws: FFProbeError if analysis fails
    static func analyzeMKVStream(from url: URL) async throws -> StreamMetadata {
        #if os(macOS)
        // Find ffprobe binary
        guard let ffprobePath = findFFProbe() else {
            throw FFProbeError.ffprobeNotFound
        }
        
        // Validate URL
        guard url.scheme == "http" || url.scheme == "https" else {
            throw FFProbeError.invalidURL
        }
        
        // Execute ffprobe
        let output = try await executeFFProbe(at: ffprobePath, with: url)
        
        // Parse output
        return try parseFFProbeOutput(output)
        #else
        // iOS/tvOS and other platforms don't support FFprobe
        throw FFProbeError.executionFailed("FFprobe analysis is not supported on this platform.")
        #endif
    }
    
    /// Checks if ffprobe is available in the system
    /// - Returns: Path to ffprobe if found, nil otherwise
    static func findFFProbe() -> String? {
        #if os(macOS)
        for path in ffprobePaths {
            if FileManager.default.fileExists(atPath: path) {
                // Check if we can access the file
                let fileURL = URL(fileURLWithPath: path)
                if FileManager.default.isReadableFile(atPath: path) {
                    LiveLogger.debug("✅ Found ffprobe at: \(path)")
                    // Try to check if it's actually executable by checking permissions
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: path)
                        if let permissions = attributes[.posixPermissions] as? NSNumber {
                            let perms = permissions.uint16Value
                            // Check if any execute bit is set (owner, group, or other)
                            if (perms & 0o111) != 0 {
                                LiveLogger.debug("✅ FFprobe is executable (permissions: \(String(perms, radix: 8)))")
                                return path
                            } else {
                                LiveLogger.debug("⚠️ FFprobe found but not executable (permissions: \(String(perms, radix: 8)))")
                            }
                        }
                    } catch {
                        LiveLogger.debug("⚠️ Could not check permissions: \(error)")
                        // If we can't check permissions, try anyway
                        return path
                    }
                } else {
                    LiveLogger.debug("⚠️ Found ffprobe at \(path) but it's not readable")
                }
            }
        }
        
        // Try using 'which' command as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffprobe"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Ignore errors, will return nil
        }
        
        return nil
        #elseif os(iOS) || os(tvOS)
        // FFmpegKit is available on iOS/tvOS
        return "FFmpegKit"
        #else
        // Unsupported platform
        return nil
        #endif
    }
    
    // MARK: - Private Methods
    
    private static func executeFFProbe(at path: String, with url: URL) async throws -> Data {
        #if os(macOS)
        return try await withCheckedThrowingContinuation { continuation in
            // Verify the file exists before creating process
            guard FileManager.default.fileExists(atPath: path) else {
                continuation.resume(throwing: FFProbeError.executionFailed("FFprobe not found at \(path)"))
                return
            }
            
            LiveLogger.debug("🔧 Attempting to execute ffprobe at: \(path)")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            
            // Configure arguments for minimal data transfer
            process.arguments = [
                "-v", "quiet",                    // Suppress all output except the result
                "-print_format", "json",          // Output in JSON format
                "-show_format",                   // Show container format info
                "-show_streams",                  // Show stream info
                "-analyzeduration", "1000000",    // Analyze only first 1 second
                "-probesize", "1000000",          // Probe only first 1MB
                url.absoluteString                // Input URL
            ]
            
            // Set up pipes for output
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Set up termination handler
            process.terminationHandler = { process in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                if process.terminationStatus != 0 {
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: FFProbeError.executionFailed(errorMessage))
                } else if outputData.isEmpty {
                    continuation.resume(throwing: FFProbeError.invalidOutput)
                } else {
                    continuation.resume(returning: outputData)
                }
            }
            
            // Set working directory to avoid path issues
            process.currentDirectoryURL = URL(fileURLWithPath: "/")
            
            // Start the process
            do {
                try process.run()
            } catch {
                LiveLogger.error("Failed to run ffprobe process: \(error)")
                LiveLogger.error("Path: \(path)")
                LiveLogger.error("URL: \(url.absoluteString)")
                continuation.resume(throwing: FFProbeError.executionFailed("Process launch failed: \(error.localizedDescription)"))
            }
        }
        #else
        throw FFProbeError.executionFailed("FFprobe execution is not supported on iOS")
        #endif
    }
    
    private static func parseFFProbeOutput(_ data: Data) throws -> StreamMetadata {
        let decoder = JSONDecoder()
        
        do {
            let response = try decoder.decode(FFProbeResponse.self, from: data)
            
            // Extract format info
            let formatName = response.format?.formatName ?? "unknown"
            let duration = response.format?.duration.flatMap { Double($0) }
            let bitrate = response.format?.bitRate.flatMap { Int($0) }
            
            // Extract video stream info
            let videoStream = response.streams?.first { $0.codecType == "video" }
            let videoCodec = videoStream?.codecName
            let videoWidth = videoStream?.width
            let videoHeight = videoStream?.height
            let videoFrameRate = parseFrameRate(videoStream?.avgFrameRate ?? videoStream?.rFrameRate)
            
            // Extract audio stream info
            let audioStream = response.streams?.first { $0.codecType == "audio" }
            let audioCodec = audioStream?.codecName
            let audioBitrate = audioStream?.bitRate.flatMap { Int($0) }
            let audioSampleRate = audioStream?.sampleRate.flatMap { Int($0) }
            let audioChannels = audioStream?.channels
            
            // Check compatibility
            let isCompatibleWithAVPlayer = checkAVPlayerCompatibility(
                format: formatName,
                videoCodec: videoCodec,
                audioCodec: audioCodec
            )
            
            return StreamMetadata(
                formatName: formatName,
                duration: duration,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                isCompatibleWithAVPlayer: isCompatibleWithAVPlayer,
                bitrate: bitrate,
                videoWidth: videoWidth,
                videoHeight: videoHeight,
                videoFrameRate: videoFrameRate,
                audioBitrate: audioBitrate,
                audioSampleRate: audioSampleRate,
                audioChannels: audioChannels
            )
            
        } catch {
            throw FFProbeError.parsingFailed(error.localizedDescription)
        }
    }
    
    private static func checkAVPlayerCompatibility(format: String, videoCodec: String?, audioCodec: String?) -> Bool {
        // AVPlayer only supports MP4, MOV, and M4V containers directly
        // MKV and WebM are NOT supported, even with compatible codecs
        let supportedFormats = ["mp4", "mov", "m4v", "m4a"]
        let formatComponents = format.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let hasValidFormat = formatComponents.contains { supportedFormats.contains($0.lowercased()) }
        
        // If it's not a supported container, it's not compatible
        if !hasValidFormat {
            return false
        }
        
        // Check video codec
        let supportedVideoCodecs = ["h264", "hevc", "h265", "avc", "avc1"]
        let hasValidVideoCodec = videoCodec.map { codec in
            supportedVideoCodecs.contains(codec.lowercased())
        } ?? true // No video is acceptable (audio only)
        
        // Check audio codec - AVPlayer is more restrictive
        let supportedAudioCodecs = ["aac", "mp3", "alac", "pcm"]
        let hasValidAudioCodec = audioCodec.map { codec in
            supportedAudioCodecs.contains(codec.lowercased())
        } ?? true // No audio is acceptable (video only)
        
        return hasValidFormat && hasValidVideoCodec && hasValidAudioCodec
    }
    
    private static func parseFrameRate(_ frameRateString: String?) -> Double? {
        guard let frameRateString = frameRateString else { return nil }
        
        // Handle fraction format (e.g., "24000/1001")
        if frameRateString.contains("/") {
            let components = frameRateString.split(separator: "/")
            if components.count == 2,
               let numerator = Double(components[0]),
               let denominator = Double(components[1]),
               denominator > 0 {
                return numerator / denominator
            }
        }
        
        // Handle decimal format
        return Double(frameRateString)
    }
}

// MARK: - Installation Instructions
/*
 FFmpeg Installation Guide for Xcode Project:
 
 Option 1: Bundle FFmpeg with your app (Recommended for distribution)
 ---------------------------------------------------------------
 1. Download FFmpeg static builds for macOS from: https://evermeet.cx/ffmpeg/
    - Download both ffmpeg and ffprobe binaries
 
 2. Add to Xcode project:
    - Create a folder: "Resources/ffmpeg" in your project
    - Drag the ffprobe binary into this folder
    - In Xcode, ensure "Copy items if needed" is checked
    - Target membership should be checked for your app
 
 3. Make executable:
    - Add a Build Phase script:
      chmod +x "${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Resources/ffmpeg/ffprobe"
 
 4. Code signing:
    - The binary needs to be signed with your app
    - Add to your entitlements if needed
 
 Option 2: Use system-installed FFmpeg (For development)
 ------------------------------------------------------
 1. Install via Homebrew:
    brew install ffmpeg
 
 2. The binary will be at: /opt/homebrew/bin/ffprobe (Apple Silicon)
    or /usr/local/bin/ffprobe (Intel)
 
 Option 3: Download at runtime (Not recommended)
 ---------------------------------------------
 - You could download ffprobe on first run
 - Store in Application Support directory
 - Requires additional error handling and user communication
 
 Usage Example:
 -------------
 Task {
     do {
         let url = URL(string: "http://example.com/video.mkv")!
         let metadata = try await FFProbeUtilities.analyzeMKVStream(from: url)
         
         print("Format: \(metadata.formatName)")
         print("Video Codec: \(metadata.videoCodec ?? "none")")
         print("Audio Codec: \(metadata.audioCodec ?? "none")")
         print("Compatible with AVPlayer: \(metadata.isCompatibleWithAVPlayer)")
         
         if let duration = metadata.duration {
             print("Duration: \(duration) seconds")
         }
         
         if let width = metadata.videoWidth, let height = metadata.videoHeight {
             print("Resolution: \(width)x\(height)")
         }
     } catch {
         print("Error analyzing stream: \(error)")
     }
 }
 */