import IPTVCore
import Foundation

#if canImport(CFFmpegHelper)
import CFFmpegHelper
import IPTVCore
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
            return "FFmpeg C API (Libavformat) not available."
        case .invalidURL:
            return "Invalid URL provided for analysis."
        case .executionFailed(let message):
            return "Stream analysis failed: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse stream info: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidOutput:
            return "Stream analysis returned no usable data."
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

    let bitrate: Int?
    let videoWidth: Int?
    let videoHeight: Int?
    let videoFrameRate: Double?
    let audioBitrate: Int?
    let audioSampleRate: Int?
    let audioChannels: Int?
}

// MARK: - FFProbe Utilities (C API)

/// Analyzes media streams using the FFmpeg 8.0.1 C API via TransmuxCore.
/// Replaces the previous shell-based ffprobe approach for cross-platform support.
class FFProbeUtilities {

    // MARK: - Public Methods

    /// Analyzes a remote stream using the FFmpeg C API.
    /// - Parameter url: The URL of the stream to analyze.
    /// - Returns: StreamMetadata containing codec and format information.
    /// - Throws: FFProbeError if analysis fails.
    static func analyzeMKVStream(from url: URL) async throws -> StreamMetadata {
        #if canImport(CFFmpegHelper)
        guard url.scheme == "http" || url.scheme == "https" || url.isFileURL else {
            throw FFProbeError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let metadata = try performAnalysis(url: url)
                    continuation.resume(returning: metadata)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        throw FFProbeError.ffprobeNotFound
        #endif
    }

    /// Checks if the FFmpeg C API is available for stream analysis.
    static func isAvailable() -> Bool {
        #if canImport(CFFmpegHelper)
        return true
        #else
        return false
        #endif
    }

    // MARK: - C API Implementation

    #if canImport(CFFmpegHelper)
    private static func performAnalysis(url: URL) throws -> StreamMetadata {
        var formatCtx: UnsafeMutablePointer<AVFormatContext>?
        let urlString = url.absoluteString

        // Set up options for better remote stream probing
        var opts: OpaquePointer?
        av_dict_set(&opts, "analyzeduration", "5000000", 0)   // 5 seconds
        av_dict_set(&opts, "probesize", "5000000", 0)         // 5 MB
        av_dict_set(&opts, "timeout", "10000000", 0)          // 10 second timeout (microseconds)

        // Open input
        var ret = avformat_open_input(&formatCtx, urlString, nil, &opts)
        av_dict_free(&opts)
        guard ret >= 0, let ctx = formatCtx else {
            throw FFProbeError.executionFailed("avformat_open_input failed (\(ret))")
        }
        defer {
            var mutableCtx: UnsafeMutablePointer<AVFormatContext>? = ctx
            avformat_close_input(&mutableCtx)
        }

        // Find stream info — probe enough data to detect codecs
        ret = avformat_find_stream_info(ctx, nil)
        guard ret >= 0 else {
            throw FFProbeError.executionFailed("avformat_find_stream_info failed (\(ret))")
        }

        // Extract format name
        let formatName: String
        if let iformat = ctx.pointee.iformat, let name = iformat.pointee.name {
            formatName = String(cString: name)
        } else {
            formatName = "unknown"
        }

        // Extract duration
        let duration: Double? = ctx.pointee.duration > 0
            ? Double(ctx.pointee.duration) / Double(AV_TIME_BASE)
            : nil

        // Extract bitrate
        let bitrate: Int? = ctx.pointee.bit_rate > 0 ? Int(ctx.pointee.bit_rate) : nil

        // Find video and audio streams
        var videoCodec: String?
        var audioCodec: String?
        var videoWidth: Int?
        var videoHeight: Int?
        var videoFrameRate: Double?
        var audioBitrate: Int?
        var audioSampleRate: Int?
        var audioChannels: Int?

        let streamCount = Int(ctx.pointee.nb_streams)
        for i in 0..<streamCount {
            guard let stream = ctx.pointee.streams[i],
                  let codecpar = stream.pointee.codecpar else { continue }

            switch codecpar.pointee.codec_type {
            case AVMEDIA_TYPE_VIDEO where videoCodec == nil:
                videoCodec = resolveCodecName(codecpar.pointee.codec_id)
                videoWidth = Int(codecpar.pointee.width)
                videoHeight = Int(codecpar.pointee.height)

                // Frame rate from avg_frame_rate
                let avgFR = stream.pointee.avg_frame_rate
                if avgFR.den > 0 && avgFR.num > 0 {
                    videoFrameRate = Double(avgFR.num) / Double(avgFR.den)
                }

            case AVMEDIA_TYPE_AUDIO where audioCodec == nil:
                audioCodec = resolveCodecName(codecpar.pointee.codec_id)
                audioBitrate = codecpar.pointee.bit_rate > 0 ? Int(codecpar.pointee.bit_rate) : nil
                audioSampleRate = Int(codecpar.pointee.sample_rate)
                audioChannels = Int(codecpar.pointee.ch_layout.nb_channels)

            default:
                break
            }
        }

        let isCompatible = checkAVPlayerCompatibility(
            format: formatName,
            videoCodec: videoCodec,
            audioCodec: audioCodec
        )

        return StreamMetadata(
            formatName: formatName,
            duration: duration,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            isCompatibleWithAVPlayer: isCompatible,
            bitrate: bitrate,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            videoFrameRate: videoFrameRate,
            audioBitrate: audioBitrate,
            audioSampleRate: audioSampleRate,
            audioChannels: audioChannels
        )
    }

    private static func resolveCodecName(_ codecId: AVCodecID) -> String? {
        // Try descriptor first (gives human-readable names)
        if let desc = avcodec_descriptor_get(codecId),
           let name = desc.pointee.name {
            return String(cString: name)
        }
        // Fallback to avcodec_get_name (always returns something for valid IDs)
        let name = String(cString: avcodec_get_name(codecId))
        if name != "unknown" && !name.isEmpty {
            return name
        }
        return nil
    }
    #endif

    // MARK: - Compatibility Check

    private static func checkAVPlayerCompatibility(
        format: String,
        videoCodec: String?,
        audioCodec: String?
    ) -> Bool {
        let supportedFormats = ["mp4", "mov", "m4v", "m4a"]
        let formatComponents = format.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let hasValidFormat = formatComponents.contains {
            supportedFormats.contains($0.lowercased())
        }

        if !hasValidFormat { return false }

        let supportedVideoCodecs = ["h264", "hevc", "h265", "avc", "avc1"]
        let hasValidVideoCodec = videoCodec.map { codec in
            supportedVideoCodecs.contains(codec.lowercased())
        } ?? true

        let supportedAudioCodecs = ["aac", "mp3", "alac", "pcm", "pcm_s16le", "pcm_s24le"]
        let hasValidAudioCodec = audioCodec.map { codec in
            supportedAudioCodecs.contains(codec.lowercased())
        } ?? true

        return hasValidVideoCodec && hasValidAudioCodec
    }
}
