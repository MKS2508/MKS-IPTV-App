import Foundation
import CTransmuxFFI

// MARK: - Transcode Tier (Swift)

/// Swift representation of `MKSTranscodeTier` with Comparable support.
///
/// The effective tier for a stream pair is always `max(videoTier, audioTier)`,
/// meaning the highest-cost processing required dictates the pipeline mode.
public enum TranscodeTier: Int, Comparable, Sendable, CustomStringConvertible {
    case passthrough = 0
    case audioOnly = 1
    case videoTranscode = 2
    case fullTranscode = 3

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .passthrough:    return "passthrough"
        case .audioOnly:      return "audio-only"
        case .videoTranscode: return "video-transcode"
        case .fullTranscode:  return "full-transcode"
        }
    }

    /// Convert from the C enum value.
    init(cTier: MKSTranscodeTier) {
        switch cTier {
        case MKS_TIER_PASSTHROUGH:     self = .passthrough
        case MKS_TIER_AUDIO_ONLY:      self = .audioOnly
        case MKS_TIER_VIDEO_TRANSCODE: self = .videoTranscode
        case MKS_TIER_FULL_TRANSCODE:  self = .fullTranscode
        default:                       self = .fullTranscode
        }
    }
}

// MARK: - Tier Decision

/// Complete tier analysis result for a stream pair (video + audio).
///
/// Contains everything the pipeline needs to decide:
/// - Whether to passthrough, transcode audio, transcode video, or both
/// - Which encoder to use and at what bitrate
/// - Whether to apply battery-saving options
/// - Whether PTS fixing is needed (IPTV streams)
public struct TierDecision: Sendable, CustomStringConvertible {
    /// Tier for the video stream alone.
    public let videoTier: TranscodeTier
    /// Tier for the audio stream alone.
    public let audioTier: TranscodeTier
    /// Effective tier: max(videoTier, audioTier).
    public let effectiveTier: TranscodeTier

    /// VideoToolbox encoder name, nil for passthrough.
    /// e.g., "h264_videotoolbox" or "hevc_videotoolbox"
    public let videoTargetCodec: String?
    /// Target bitrate in bits/s for the video encoder. 0 = not applicable.
    public let videoTargetBitrate: Int
    /// Source video dimensions.
    public let sourceWidth: Int
    public let sourceHeight: Int
    /// Source video bitrate in bits/s (0 if unknown).
    public let sourceBitrate: Int

    /// Use battery-saving encoder options.
    public let powerEfficient: Bool
    /// Encode in realtime mode (live content).
    public let realtimeMode: Bool
    /// Apply dts2pts BSF to fix PTS reordering (IPTV streams).
    public let useDts2PtsBSF: Bool

    /// Human-readable explanation of the decision.
    public let reason: String

    public var description: String {
        var parts = ["Tier \(effectiveTier.rawValue) (\(effectiveTier))"]
        parts.append("video=\(videoTier), audio=\(audioTier)")
        if let codec = videoTargetCodec {
            parts.append("encoder=\(codec)")
            parts.append("bitrate=\(BitrateCalculator.formatBitrate(videoTargetBitrate))")
        }
        if powerEfficient { parts.append("power_efficient") }
        if realtimeMode { parts.append("realtime") }
        if useDts2PtsBSF { parts.append("dts2pts") }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Tier Decision Engine

/// Analyzes streams and produces a `TierDecision` with everything the pipeline needs.
///
/// This is the single decision point for the entire transcode tier system.
/// Replaces the hardcoded `Set<Int32>` codec ID checks scattered through
/// TransmuxingService with a centralized, extensible classification.
///
/// Thread safety: All methods are static and pure (no mutable state).
public enum TierDecisionEngine {

    /// Analyze a format context and produce a tier decision.
    ///
    /// - Parameters:
    ///   - formatContext: Opaque `AVFormatContext*` from CTransmuxFFI.
    ///   - videoStreamIndex: Index of the selected video stream (-1 if none).
    ///   - audioStreamIndex: Index of the selected audio stream (-1 if none).
    ///   - isLive: Whether the content is a live stream (affects encoder mode).
    ///   - isBatteryPowered: Whether to enable power-efficient encoding.
    ///   - transcodeAudio: Whether audio transcoding is enabled.
    ///   - transcodeVideo: Whether video transcoding is enabled.
    /// - Returns: A complete `TierDecision` describing the processing needed.
    public static func analyze(
        formatContext: OpaquePointer,
        videoStreamIndex: Int32,
        audioStreamIndex: Int32,
        isLive: Bool = false,
        isBatteryPowered: Bool = false,
        transcodeAudio: Bool = true,
        transcodeVideo: Bool = true
    ) -> TierDecision {
        // Convert OpaquePointer to UnsafeRawPointer for C function calls
        let ctx = UnsafeRawPointer(formatContext)

        // --- Video tier ---
        let videoTier: TranscodeTier
        if videoStreamIndex >= 0 {
            let cTier = mks_tier_detect_video(ctx, videoStreamIndex)
            videoTier = TranscodeTier(cTier: cTier)
        } else {
            videoTier = .passthrough
        }

        // --- Audio tier ---
        let audioTier: TranscodeTier
        if audioStreamIndex >= 0 {
            let cTier = mks_tier_detect_audio(ctx, audioStreamIndex)
            audioTier = TranscodeTier(cTier: cTier)
        } else {
            audioTier = .passthrough
        }

        // --- Effective tier (respecting user toggles) ---
        let actualVideoTier = transcodeVideo ? videoTier : .passthrough
        let actualAudioTier = transcodeAudio ? audioTier : .passthrough
        let effectiveTier = max(actualVideoTier, actualAudioTier)

        // --- Video encoder selection & bitrate ---
        var videoTargetCodec: String? = nil
        var videoTargetBitrate = 0
        var sourceWidth = 0
        var sourceHeight = 0
        var sourceBitrate = 0

        if videoStreamIndex >= 0 {
            sourceWidth = Int(mks_stream_get_width(ctx, videoStreamIndex))
            sourceHeight = Int(mks_stream_get_height(ctx, videoStreamIndex))
            sourceBitrate = Int(mks_stream_get_bit_rate(ctx, videoStreamIndex))

            if actualVideoTier >= .videoTranscode {
                videoTargetCodec = CodecSelector.selectOutputCodec(
                    width: sourceWidth,
                    height: sourceHeight,
                    sourceBitrate: sourceBitrate
                )
                videoTargetBitrate = BitrateCalculator.calculate(
                    width: sourceWidth,
                    height: sourceHeight,
                    sourceBitrate: sourceBitrate
                )
            }
        }

        // --- Reason string ---
        let reason = buildReason(
            videoTier: videoTier,
            audioTier: audioTier,
            effectiveTier: effectiveTier,
            transcodeAudio: transcodeAudio,
            transcodeVideo: transcodeVideo,
            videoTargetCodec: videoTargetCodec,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight
        )

        return TierDecision(
            videoTier: videoTier,
            audioTier: audioTier,
            effectiveTier: effectiveTier,
            videoTargetCodec: videoTargetCodec,
            videoTargetBitrate: videoTargetBitrate,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            sourceBitrate: sourceBitrate,
            powerEfficient: isBatteryPowered,
            realtimeMode: isLive,
            useDts2PtsBSF: isLive,
            reason: reason
        )
    }

    /// Classify a video codec ID without a format context.
    /// Useful for quick checks when you already have the codec ID.
    public static func classifyVideoCodec(_ codecId: Int32) -> TranscodeTier {
        TranscodeTier(cTier: mks_tier_classify_video_codec(codecId))
    }

    /// Classify an audio codec ID without a format context.
    public static func classifyAudioCodec(_ codecId: Int32) -> TranscodeTier {
        TranscodeTier(cTier: mks_tier_classify_audio_codec(codecId))
    }

    // MARK: - Private

    private static func buildReason(
        videoTier: TranscodeTier,
        audioTier: TranscodeTier,
        effectiveTier: TranscodeTier,
        transcodeAudio: Bool,
        transcodeVideo: Bool,
        videoTargetCodec: String?,
        sourceWidth: Int,
        sourceHeight: Int
    ) -> String {
        var parts: [String] = []

        switch effectiveTier {
        case .passthrough:
            parts.append("All streams AVPlayer-native, zero CPU cost")
        case .audioOnly:
            parts.append("Audio needs transcode to AAC, video passthrough")
        case .videoTranscode:
            if let codec = videoTargetCodec {
                parts.append("Video \(sourceWidth)x\(sourceHeight) → \(codec)")
            }
            if audioTier >= .audioOnly {
                parts.append("+ audio transcode to AAC")
            }
        case .fullTranscode:
            parts.append("Unknown codec(s), full transcode pipeline")
        }

        if !transcodeVideo && videoTier >= .videoTranscode {
            parts.append("(video transcode disabled by user)")
        }
        if !transcodeAudio && audioTier >= .audioOnly {
            parts.append("(audio transcode disabled by user)")
        }

        return parts.joined(separator: "; ")
    }
}

// MARK: - Bitrate Calculator

/// Resolution-aware target bitrate calculation for VideoToolbox encoding.
///
/// Uses VBR with qmin/qmax bounds (CRF is IGNORED by VT hardware encoder).
/// Never exceeds the source bitrate — transcoding should not inflate the file.
public enum BitrateCalculator {

    /// Calculate target bitrate for a given resolution.
    ///
    /// Strategy: Use sensible defaults per resolution tier, but never exceed
    /// the source bitrate (transcoding shouldn't produce a larger file).
    ///
    /// - Parameters:
    ///   - width: Source video width in pixels.
    ///   - height: Source video height in pixels.
    ///   - sourceBitrate: Source video bitrate in bits/s (0 if unknown).
    /// - Returns: Target bitrate in bits/s.
    public static func calculate(width: Int, height: Int, sourceBitrate: Int) -> Int {
        let pixels = width * height
        let target: Int

        switch pixels {
        case ..<(640 * 480):        // ≤480p
            target = 2_000_000
        case ..<(1280 * 720):       // ≤720p
            target = 4_000_000
        case ..<(1920 * 1080):      // ≤1080p
            target = 8_000_000
        case ..<(2560 * 1440):      // ≤1440p
            target = 12_000_000
        default:                    // 2160p+
            target = 20_000_000
        }

        // Never exceed source bitrate (don't inflate the file)
        if sourceBitrate > 0 {
            return min(target, sourceBitrate)
        }
        return target
    }

    /// Format bitrate for human-readable display.
    public static func formatBitrate(_ bitsPerSec: Int) -> String {
        if bitsPerSec >= 1_000_000 {
            let mbps = Double(bitsPerSec) / 1_000_000.0
            return String(format: "%.1f Mbps", mbps)
        } else if bitsPerSec >= 1_000 {
            let kbps = Double(bitsPerSec) / 1_000.0
            return String(format: "%.0f kbps", kbps)
        }
        return "\(bitsPerSec) bps"
    }
}

// MARK: - Codec Selector

/// Selects the optimal output codec (H.264 vs H.265) based on content characteristics.
///
/// H.265 (HEVC) is more efficient at high resolutions but has narrower compatibility.
/// H.264 is universally supported. We use HEVC only when the efficiency gain justifies it.
public enum CodecSelector {

    /// Select "h264_videotoolbox" or "hevc_videotoolbox" based on content.
    ///
    /// HEVC triggers:
    /// - 4K (2160p) or higher: HEVC efficiency is significant at these resolutions
    /// - 1440p with high bitrate (>10 Mbps): HEVC helps reduce output size
    ///
    /// Everything else gets H.264 for maximum compatibility.
    public static func selectOutputCodec(
        width: Int,
        height: Int,
        sourceBitrate: Int = 0
    ) -> String {
        let pixels = width * height

        // 4K+ always HEVC
        if pixels >= 3840 * 2160 {
            return "hevc_videotoolbox"
        }

        // 1440p with high bitrate → HEVC
        if pixels >= 2560 * 1440 && sourceBitrate > 10_000_000 {
            return "hevc_videotoolbox"
        }

        // Everything else → H.264 (wider compatibility)
        return "h264_videotoolbox"
    }
}
