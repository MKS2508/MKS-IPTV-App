import Foundation
import AVKit

/// Handles stream compatibility checking for AVPlayer
/// Note: Transmuxing via HTTP server has been removed as it was legacy/test code
class StreamCompatibilityHandler {

    /// Check stream compatibility and return appropriate URL for AVPlayer
    /// - Parameter originalURL: The original stream URL (MKV or other format)
    /// - Returns: A tuple with (playableURL, needsTransmuxing, metadata)
    @MainActor
    func checkAndPrepareStream(from originalURL: URL) async throws -> (url: URL, needsTransmuxing: Bool, metadata: StreamMetadata) {
        print("[StreamCompatibilityHandler] 🔍 Checking stream: \(originalURL)")

        // Analyze with FFProbe
        print("[StreamCompatibilityHandler] 📊 Analyzing stream with FFProbe...")
        let metadata = try await FFProbeUtilities.analyzeMKVStream(from: originalURL)

        print("[StreamCompatibilityHandler] 📋 Stream details:")
        print("  - Format: \(metadata.formatName)")
        print("  - Video: \(metadata.videoCodec ?? "none")")
        print("  - Audio: \(metadata.audioCodec ?? "none")")
        print("  - Resolution: \(metadata.videoWidth ?? 0)x\(metadata.videoHeight ?? 0)")
        print("  - Compatible with AVPlayer: \(metadata.isCompatibleWithAVPlayer)")

        // Check if compatible
        if metadata.isCompatibleWithAVPlayer {
            print("[StreamCompatibilityHandler] ✅ Stream is directly compatible with AVPlayer")
            return (originalURL, false, metadata)
        }

        // Not compatible - return original URL anyway (player will handle or fail)
        print("[StreamCompatibilityHandler] ⚠️ Stream may not be fully compatible, but attempting direct playback")
        return (originalURL, false, metadata)
    }

    /// Create AVPlayer for the given URL
    /// - Parameter url: The stream URL to play
    /// - Returns: Configured AVPlayer ready for playback
    @MainActor
    func createCompatiblePlayer(for url: URL) async throws -> AVPlayer? {
        print("[StreamCompatibilityHandler] 🎬 Creating player for: \(url)")

        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true

        return player
    }

    /// Cleanup (no-op, kept for API compatibility)
    func cleanup() {
        print("[StreamCompatibilityHandler] 🧹 Cleanup (no-op)")
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
            let (playableURL, _, metadata) = try await checkAndPrepareStream(from: url)

            viewModel.log("[\(requestId)] 📊 Analysis complete:", type: .info)
            viewModel.log("[\(requestId)]   Format: \(metadata.formatName)", type: .info)
            viewModel.log("[\(requestId)]   Video: \(metadata.videoCodec ?? "none")", type: .info)
            viewModel.log("[\(requestId)]   Audio: \(metadata.audioCodec ?? "none")", type: .info)

            let player = AVPlayer(url: playableURL)
            player.automaticallyWaitsToMinimizeStalling = true

            viewModel.log("[\(requestId)] 🎮 Player created successfully", type: .success)
            return player

        } catch {
            viewModel.log("[\(requestId)] ❌ Compatibility check failed: \(error.localizedDescription)", type: .error)
            return nil
        }
    }
}
