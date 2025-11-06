import Foundation
import AVKit

/// Handles stream compatibility checking and automatic transmuxing for AVPlayer
class StreamCompatibilityHandler {
    
    private var httpServer: HTTPStreamServer?
    private var simpleServer: SimpleHTTPStreamServer?
    private var proxyServer: HTTPStreamProxyServer?
    private var directProxy: DirectHTTPProxy?
    private let serverPort: Int
    private var isServerRunning = false
    private let useProxyServer = true // Use proxy server for better compatibility
    private let useSimpleServer = false // Use simple server as fallback
    private let useDirectProxy = true // Use direct proxy as primary option
    
    /// Initialize with a specific port for the HTTP server
    init(serverPort: Int = 8888) {
        self.serverPort = serverPort
        print("[StreamCompatibilityHandler] Initialized with port \(serverPort)")
    }
    
    /// Check stream compatibility and return appropriate URL for AVPlayer
    /// - Parameter originalURL: The original stream URL (MKV or other format)
    /// - Returns: A tuple with (playableURL, needsTransmuxing, metadata)
    @MainActor
    func checkAndPrepareStream(from originalURL: URL) async throws -> (url: URL, needsTransmuxing: Bool, metadata: StreamMetadata) {
        print("[StreamCompatibilityHandler] 🔍 Checking stream: \(originalURL)")
        
        // Step 1: Analyze with FFProbe
        print("[StreamCompatibilityHandler] 📊 Analyzing stream with FFProbe...")
        let metadata = try await FFProbeUtilities.analyzeMKVStream(from: originalURL)
        
        print("[StreamCompatibilityHandler] 📋 Stream details:")
        print("  - Format: \(metadata.formatName)")
        print("  - Video: \(metadata.videoCodec ?? "none")")
        print("  - Audio: \(metadata.audioCodec ?? "none")")
        print("  - Resolution: \(metadata.videoWidth ?? 0)x\(metadata.videoHeight ?? 0)")
        print("  - Compatible with AVPlayer: \(metadata.isCompatibleWithAVPlayer)")
        
        // Step 2: Check if compatible
        if metadata.isCompatibleWithAVPlayer {
            print("[StreamCompatibilityHandler] ✅ Stream is directly compatible with AVPlayer")
            return (originalURL, false, metadata)
        }
        
        // Step 3: If not compatible, check if we can transmux
        if canTransmux(metadata: metadata) {
            print("[StreamCompatibilityHandler] 🔄 Stream needs transmuxing, starting HTTP server...")
            
            // Start HTTP server if not already running
            if !isServerRunning {
                startHTTPServer(for: originalURL)
            } else {
                // Update server with new URL
                cleanup()
                startHTTPServer(for: originalURL)
            }
            
            // Check if server started successfully
            if !isServerRunning {
                print("[StreamCompatibilityHandler] ❌ Failed to start HTTP server for transmuxing")
                throw StreamCompatibilityError.serverStartFailure
            }
            
            // Get the actual URL from the proxy server if available
            let transmuxedURL = directProxy != nil ? URL(string: "http://localhost:\(serverPort + 2)/stream.mp4")! :
                               (proxyServer?.getProxyURL() ?? URL(string: "http://localhost:\(serverPort)/stream.mp4")!)
            print("[StreamCompatibilityHandler] 🎯 Transmuxed URL: \(transmuxedURL)")
            
            // Give the server more time to be ready
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            return (transmuxedURL, true, metadata)
        } else {
            print("[StreamCompatibilityHandler] ❌ Stream cannot be transmuxed to a compatible format")
            throw StreamCompatibilityError.incompatibleFormat(metadata)
        }
    }
    
    /// Create AVPlayer with automatic compatibility handling
    /// - Parameter url: The stream URL to play
    /// - Returns: Configured AVPlayer ready for playback, or nil if incompatible
    @MainActor
    func createCompatiblePlayer(for url: URL) async throws -> AVPlayer? {
        // Note: checkAndPrepareStream has already been called by the caller
        // We just need to create the player with the appropriate URL
        
        // Check if server is running (meaning we're using transmuxed URL)
        let playableURL = isServerRunning ? 
            (directProxy != nil ? URL(string: "http://localhost:\(serverPort + 2)/stream.mp4")! :
             (proxyServer?.getProxyURL() ?? URL(string: "http://localhost:\(serverPort)/stream.mp4")!)) : url
        let needsTransmuxing = isServerRunning
        
        print("[StreamCompatibilityHandler] 🎬 Creating player for: \(playableURL)")
        print("  - Needs transmuxing: \(needsTransmuxing)")
        
        // Create player
        let player = AVPlayer(url: playableURL)
        
        // Configure player based on stream type
        if needsTransmuxing {
            // For transmuxed streams, we might need different buffering
            player.automaticallyWaitsToMinimizeStalling = true
            if let playerItem = player.currentItem {
                playerItem.preferredForwardBufferDuration = 5.0 // Larger buffer for transmuxed
            }
            print("[StreamCompatibilityHandler] 🔧 Player configured for transmuxed stream")
        }
        
        return player
    }
    
    /// Stop the HTTP server and cleanup
    func cleanup() {
        print("[StreamCompatibilityHandler] 🧹 Cleaning up...")
        httpServer?.shutdown()
        httpServer = nil
        simpleServer?.stop()
        simpleServer = nil
        proxyServer?.stop()
        proxyServer = nil
        directProxy?.stop()
        directProxy = nil
        isServerRunning = false
    }
    
    // MARK: - Private Methods
    
    private func canTransmux(metadata: StreamMetadata) -> Bool {
        // Check if we can transmux this format
        // MKV with H264/H265 video and common audio codecs can be transmuxed
        let supportedVideoCodecs = ["h264", "hevc", "h265", "avc", "avc1"]
        let supportedAudioCodecs = ["aac", "mp3", "ac3", "eac3", "alac", "pcm", "opus", "vorbis", "flac"]
        
        let hasValidVideo = metadata.videoCodec.map { codec in
            supportedVideoCodecs.contains(codec.lowercased())
        } ?? true // No video is OK (audio only)
        
        let hasValidAudio = metadata.audioCodec.map { codec in
            supportedAudioCodecs.contains(codec.lowercased())
        } ?? true // No audio is OK (video only)
        
        // Must be MKV/WebM format and have valid codecs
        let isTransmuxableFormat = metadata.formatName.lowercased().contains("matroska") || 
                                  metadata.formatName.lowercased().contains("webm")
        
        return isTransmuxableFormat && hasValidVideo && hasValidAudio
    }
    
    private func startHTTPServer(for url: URL) {
        if useDirectProxy {
            print("[StreamCompatibilityHandler] Using DirectHTTPProxy")
            // Use a different port to avoid conflicts
            let directProxyPort = serverPort + 2 // 8891 if serverPort is 8889
            directProxy = DirectHTTPProxy(port: directProxyPort)
            if directProxy?.start(mkvURL: url) == true {
                isServerRunning = true
                print("[StreamCompatibilityHandler] ✅ DirectHTTPProxy started successfully")
            } else {
                print("[StreamCompatibilityHandler] ❌ DirectHTTPProxy failed to start")
                isServerRunning = false
            }
        } else if useProxyServer {
            print("[StreamCompatibilityHandler] Using HTTPStreamProxyServer")
            proxyServer = HTTPStreamProxyServer(port: serverPort)
            if let success = proxyServer?.start(mkvURL: url), success {
                isServerRunning = true
                print("[StreamCompatibilityHandler] ✅ HTTPStreamProxyServer started successfully")
            } else {
                print("[StreamCompatibilityHandler] ❌ HTTPStreamProxyServer failed to start")
                isServerRunning = false
            }
        } else if useSimpleServer {
            print("[StreamCompatibilityHandler] Using SimpleHTTPStreamServer")
            simpleServer = SimpleHTTPStreamServer(port: serverPort)
            simpleServer?.start(mkvURL: url)
            isServerRunning = true
        } else {
            httpServer = HTTPStreamServer(port: serverPort)
            httpServer?.startStreaming(from: url)
            isServerRunning = true
        }
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Errors
enum StreamCompatibilityError: LocalizedError {
    case incompatibleFormat(StreamMetadata)
    case serverStartFailure
    case ffprobeNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .incompatibleFormat(let metadata):
            return "Stream format is not compatible: \(metadata.formatName) with video: \(metadata.videoCodec ?? "none"), audio: \(metadata.audioCodec ?? "none")"
        case .serverStartFailure:
            return "Failed to start HTTP streaming server"
        case .ffprobeNotAvailable:
            return "FFProbe is not available for stream analysis"
        }
    }
}

// MARK: - Debug Integration Extension
extension StreamCompatibilityHandler {
    
    /// Integration method for DebugStreamingView
    /// - Parameters:
    ///   - item: The debug stream item to test
    ///   - viewModel: The debug view model for logging
    /// - Returns: AVPlayer if successful, nil otherwise
    @MainActor
    func testStreamWithCompatibility(
        item: DebugStreamItem,
        viewModel: DebugStreamingViewModel
    ) async -> AVPlayer? {
        
        let requestId = UUID().uuidString.prefix(8)
        
        guard let urlString = item.streamURL,
              let url = URL(string: urlString) else {
            viewModel.log("[\(requestId)] ❌ Invalid stream URL", type: .error)
            return nil
        }
        
        viewModel.log("[\(requestId)] 🔄 Starting compatibility check for: \(item.title)", type: .info)
        
        do {
            // Check and prepare stream
            let (playableURL, needsTransmuxing, metadata) = try await checkAndPrepareStream(from: url)
            
            // Log results
            viewModel.log("[\(requestId)] 📊 Analysis complete:", type: .info)
            viewModel.log("[\(requestId)]   Format: \(metadata.formatName)", type: .info)
            viewModel.log("[\(requestId)]   Video: \(metadata.videoCodec ?? "none") (\(metadata.videoWidth ?? 0)x\(metadata.videoHeight ?? 0))", type: .info)
            viewModel.log("[\(requestId)]   Audio: \(metadata.audioCodec ?? "none")", type: .info)
            viewModel.log("[\(requestId)]   AVPlayer Compatible: \(metadata.isCompatibleWithAVPlayer)", type: .info)
            
            if needsTransmuxing {
                viewModel.log("[\(requestId)] 🔄 Transmuxing required - Server started at: \(playableURL)", type: .warning)
            } else {
                viewModel.log("[\(requestId)] ✅ Direct playback supported", type: .success)
            }
            
            // Create player directly with the playable URL
            let player = AVPlayer(url: playableURL)
            
            // Configure player based on stream type
            if needsTransmuxing {
                player.automaticallyWaitsToMinimizeStalling = true
                if let playerItem = player.currentItem {
                    playerItem.preferredForwardBufferDuration = 5.0
                }
                viewModel.log("[\(requestId)] 🔧 Player configured for transmuxed stream", type: .info)
            }
            
            viewModel.log("[\(requestId)] 🎮 Player created successfully", type: .success)
            return player
            
        } catch {
            viewModel.log("[\(requestId)] ❌ Compatibility check failed: \(error.localizedDescription)", type: .error)
            
            // Detailed error logging
            if let compatError = error as? StreamCompatibilityError {
                switch compatError {
                case .incompatibleFormat(let metadata):
                    viewModel.log("  Unsupported format details:", type: .error)
                    viewModel.log("  - Container: \(metadata.formatName)", type: .error)
                    viewModel.log("  - Video codec: \(metadata.videoCodec ?? "none")", type: .error)
                    viewModel.log("  - Audio codec: \(metadata.audioCodec ?? "none")", type: .error)
                case .serverStartFailure:
                    viewModel.log("  HTTP server failed to start", type: .error)
                case .ffprobeNotAvailable:
                    viewModel.log("  FFProbe is not installed or accessible", type: .error)
                }
            }
            
            return nil
        }
    }
}