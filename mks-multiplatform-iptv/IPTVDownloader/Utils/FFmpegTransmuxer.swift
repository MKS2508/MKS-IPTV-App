import Foundation

/// Facade for transmuxing MKV streams to MP4/HLS using the FFmpeg C API via TransmuxingService.
/// This replaces the previous macOS-only shell-based approach with cross-platform C API calls.
class FFmpegTransmuxer {

    /// Transmux a remote MKV stream to HLS/fMP4 segments on disk.
    /// - Parameter url: Source stream URL (MKV or other non-native format).
    /// - Returns: A `TransmuxResult` with the playlist URL and segment directory.
    /// - Throws: `TransmuxError` on failure.
    static func transmux(from url: URL) async throws -> TransmuxResult {
        print("[FFmpegTransmuxer] Requesting transmux from \(url)")
        return try await TransmuxingService.shared.transmux(from: url)
    }

    /// Clean up a previous transmux session.
    /// - Parameter sessionID: The session identifier returned in `TransmuxResult`.
    static func cleanup(sessionID: String) async {
        await TransmuxingService.shared.cleanup(sessionID: sessionID)
    }

    /// Clean up all active transmux sessions.
    static func cleanupAll() async {
        await TransmuxingService.shared.cleanupAll()
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
            return "FFmpeg C API not available. Ensure KSPlayer (with FFmpegKit) is linked."
        case .processStartFailure(let error):
            return "Failed to initialize transmuxing: \(error.localizedDescription)"
        case .processFailure(let status):
            return "Transmuxing failed with error code: \(status)"
        case .notAvailableOnPlatform:
            return "FFmpeg transmuxing is not available on this platform (Libavformat not linked)"
        }
    }
}
