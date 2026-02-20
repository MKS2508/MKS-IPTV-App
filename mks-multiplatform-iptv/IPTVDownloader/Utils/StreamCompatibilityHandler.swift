import Foundation
import AVKit

/// Handles stream compatibility checking for AVPlayer.
/// When a stream is incompatible and AirPlay is requested, triggers transmuxing
/// via TransmuxingService + LocalHLSServer to produce a playable local URL.
class StreamCompatibilityHandler {

    private var activeTransmuxSessionID: String?

    /// Check stream compatibility and return appropriate URL for AVPlayer.
    /// - Parameters:
    ///   - originalURL: The original stream URL (MKV or other format).
    ///   - forAirPlay: When true and the stream is incompatible, triggers transmux + local HLS.
    /// - Returns: A tuple with (playableURL, needsTransmuxing, metadata).
    @MainActor
    func checkAndPrepareStream(
        from originalURL: URL,
        forAirPlay: Bool = false
    ) async throws -> (url: URL, needsTransmuxing: Bool, metadata: StreamMetadata) {
        print("[StreamCompatibilityHandler] Checking stream: \(originalURL)")

        // Analyze with FFProbe C API
        print("[StreamCompatibilityHandler] Analyzing stream...")
        let metadata = try await FFProbeUtilities.analyzeMKVStream(from: originalURL)

        print("[StreamCompatibilityHandler] Stream details:")
        print("  - Format: \(metadata.formatName)")
        print("  - Video: \(metadata.videoCodec ?? "none")")
        print("  - Audio: \(metadata.audioCodec ?? "none")")
        print("  - Resolution: \(metadata.videoWidth ?? 0)x\(metadata.videoHeight ?? 0)")
        print("  - Compatible with AVPlayer: \(metadata.isCompatibleWithAVPlayer)")

        if metadata.isCompatibleWithAVPlayer {
            print("[StreamCompatibilityHandler] Stream is directly compatible with AVPlayer")
            return (originalURL, false, metadata)
        }

        // Not compatible — if AirPlay requested, transmux to local HLS
        if forAirPlay {
            print("[StreamCompatibilityHandler] AirPlay requested, starting transmux pipeline...")
            do {
                let transmuxResult = try await TransmuxingService.shared.transmux(from: originalURL)
                activeTransmuxSessionID = transmuxResult.sessionID

                #if canImport(FlyingFox)
                let localURL = try await LocalHLSServer.shared.serve(
                    directory: transmuxResult.segmentDirectory,
                    playlist: transmuxResult.playlistURL.lastPathComponent
                )
                print("[StreamCompatibilityHandler] Transmux + HLS server ready: \(localURL)")
                return (localURL, true, metadata)
                #else
                // FlyingFox not available — return the file URL directly
                print("[StreamCompatibilityHandler] FlyingFox not available, using file URL")
                return (transmuxResult.playlistURL, true, metadata)
                #endif
            } catch {
                print("[StreamCompatibilityHandler] Transmux failed: \(error), falling back to direct URL")
            }
        }

        // Not compatible but no transmux path — return original URL (player will handle or fail)
        print("[StreamCompatibilityHandler] Stream may not be fully compatible, attempting direct playback")
        return (originalURL, false, metadata)
    }

    /// Create AVPlayer for the given URL.
    /// - Parameter url: The stream URL to play.
    /// - Returns: Configured AVPlayer ready for playback.
    @MainActor
    func createCompatiblePlayer(for url: URL) async throws -> AVPlayer? {
        print("[StreamCompatibilityHandler] Creating player for: \(url)")
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = true
        return player
    }

    /// Cleanup transmux sessions and local server.
    func cleanup() {
        if let sessionID = activeTransmuxSessionID {
            Task {
                await TransmuxingService.shared.cleanup(sessionID: sessionID)
                #if canImport(FlyingFox)
                await LocalHLSServer.shared.stop()
                #endif
            }
            activeTransmuxSessionID = nil
        }
        print("[StreamCompatibilityHandler] Cleanup complete")
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
            viewModel.log("[\(requestId)] Invalid stream URL", type: .error)
            return nil
        }

        viewModel.log("[\(requestId)] Starting compatibility check for: \(item.title)", type: .info)

        do {
            let (playableURL, _, metadata) = try await checkAndPrepareStream(from: url)

            viewModel.log("[\(requestId)] Analysis complete:", type: .info)
            viewModel.log("[\(requestId)]   Format: \(metadata.formatName)", type: .info)
            viewModel.log("[\(requestId)]   Video: \(metadata.videoCodec ?? "none")", type: .info)
            viewModel.log("[\(requestId)]   Audio: \(metadata.audioCodec ?? "none")", type: .info)

            let player = AVPlayer(url: playableURL)
            player.automaticallyWaitsToMinimizeStalling = true

            viewModel.log("[\(requestId)] Player created successfully", type: .success)
            return player

        } catch {
            viewModel.log("[\(requestId)] Compatibility check failed: \(error.localizedDescription)", type: .error)
            return nil
        }
    }
}
