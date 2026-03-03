import Foundation
import CFFmpegHelper

// MARK: - Transmux Error

/// Errors that can occur during transmuxing operations
public enum TransmuxError: LocalizedError {
    case ffmpegNotFound
    case processStartFailure(Error)
    case processFailure(status: Int)
    case notAvailableOnPlatform

    public var errorDescription: String? {
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

// MARK: - Progressive Transmux Session

/// Result returned immediately after the fMP4 header is written.
/// Playback can begin while the remux loop continues in the background.
public struct ProgressiveTransmuxSession {
    public let sessionID: String
    public let outputPath: String
    public let playlistPath: String
    public let expectedSize: Int64
    public let duration: Double
    public let segmenter: HLSSegmenter
    public let initSegmentSize: Int64
    public let seekHandle: ActiveTransmux
}

// MARK: - Transmux Completion Notification

public extension Notification.Name {
    /// Posted when a transmux session completes successfully.
    /// The notification's `object` is the session ID (`String`).
    static let transmuxDidComplete = Notification.Name("com.mks.iptv.transmuxDidComplete")
}

// MARK: - Transmuxing Service

/// Cross-platform transmuxing service using the FFmpeg C API bundled by KSPlayer.
/// Remuxes MKV (or other non-native containers) to fragmented MP4
/// without re-encoding -- copies video and audio streams as-is.
///
/// ## Progressive Playback
/// `startTransmux(from:)` returns a `ProgressiveTransmuxSession` as soon as the
/// fMP4 header (`moov` atom) is written. The remux loop continues on a background
/// thread. AVPlayer reads from the growing file via `TransmuxServer`.
///
/// NOTE: All AVStream struct field access goes through C helper functions
/// (FFmpegStreamHelper.c) because Swift's import of AVStream has a layout
/// mismatch -- av_class is omitted, shifting all field offsets by 8 bytes.
/// The C compiler sees the correct struct layout.
public actor TransmuxingService {
    /// Default shared instance. Call `configure(streamProxy:)` early in app launch
    /// to inject the HTTPS proxy before any transmux operations.
    public static var shared = TransmuxingService()

    private var activeSessions: [String: URL] = [:]
    private var activeTransmuxes: [String: ActiveTransmux] = [:]
    private let streamProxy: StreamProxyProvider?

    public init(streamProxy: StreamProxyProvider? = nil) {
        self.streamProxy = streamProxy
    }

    /// Replace the shared instance with one configured with the given proxy.
    /// Call once during app startup, before any transmux operations.
    public static func configure(streamProxy: StreamProxyProvider) {
        shared = TransmuxingService(streamProxy: streamProxy)
    }

    // MARK: - Public API

    /// Start transmuxing and return immediately after the fMP4 header is written.
    /// The remux loop continues in the background. Use `cancelTransmux(sessionID:)`
    /// to stop it early.
    public func startTransmux(from sourceURL: URL) async throws -> ProgressiveTransmuxSession {
        let sessionID = UUID().uuidString
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mks-iptv-transmux-\(sessionID)")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        activeSessions[sessionID] = outputDir

        let handle = ActiveTransmux()
        activeTransmuxes[sessionID] = handle

        // FFmpeg's bundled build may lack HTTPS protocol support.
        // Route HTTPS URLs through StreamProxy (URLSession -> http://localhost) if available.
        var proxySessionID: Int?
        let inputPath: String
        if sourceURL.scheme?.lowercased() == "https" {
            if let proxy = streamProxy {
                let proxySession = try await proxy.startProxy(for: sourceURL)
                proxySessionID = proxySession.id
                inputPath = proxySession.localURL.absoluteString
                TransmuxLog.service("Proxied HTTPS -> \(inputPath)")
            } else {
                // No proxy available - try direct HTTPS (may fail)
                inputPath = sourceURL.absoluteString
                TransmuxLog.service("WARNING: No StreamProxy provided for HTTPS URL, attempting direct (may fail if FFmpeg lacks HTTPS support)", level: .warn)
            }
        } else if sourceURL.scheme == "file" {
            // For local files, use path() with percentEncoded: false to avoid URL-encoding issues
            inputPath = sourceURL.path(percentEncoded: false)
        } else {
            inputPath = sourceURL.absoluteString
        }

        TransmuxLog.service("Starting progressive transmux session \(sessionID)")
        TransmuxLog.service("Input: \(inputPath)")
        TransmuxLog.service("Output dir: \(outputDir.path)")

        do {
            let session = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProgressiveTransmuxSession, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.performProgressiveTransmux(
                        inputPath: inputPath,
                        outputDir: outputDir,
                        sessionID: sessionID,
                        handle: handle,
                        proxySessionID: proxySessionID,
                        streamProxy: self.streamProxy,
                        continuation: continuation
                    )
                }
            }
            return session
        } catch {
            // Stop proxy on failure
            if let pid = proxySessionID, let proxy = streamProxy {
                await proxy.stop(sessionID: pid)
            }
            activeTransmuxes.removeValue(forKey: sessionID)
            throw error
        }
    }

    /// Cancel an active transmux session.
    public func cancelTransmux(sessionID: String) {
        guard let handle = activeTransmuxes[sessionID] else { return }
        handle.cancel()
        TransmuxLog.service("Cancellation requested for session \(sessionID)")
    }

    /// Clean up a specific transmux session's temp files.
    public func cleanup(sessionID: String) {
        activeTransmuxes.removeValue(forKey: sessionID)
        guard let dir = activeSessions.removeValue(forKey: sessionID) else { return }
        try? FileManager.default.removeItem(at: dir)
        TransmuxLog.service("Cleaned up session \(sessionID)")
    }

    /// Clean up all transmux sessions.
    public func cleanupAll() {
        for handle in activeTransmuxes.values {
            handle.cancel()
        }
        activeTransmuxes.removeAll()
        for (id, dir) in activeSessions {
            try? FileManager.default.removeItem(at: dir)
            TransmuxLog.service("Cleaned up session \(id)")
        }
        activeSessions.removeAll()
    }

    // MARK: - FFmpeg C API Core (Progressive)

    /// Two-phase transmux: resumes the continuation after the header is written,
    /// then continues the remux loop on the same background thread.
    private static func performProgressiveTransmux(
        inputPath: String,
        outputDir: URL,
        sessionID: String,
        handle: ActiveTransmux,
        proxySessionID: Int?,
        streamProxy: StreamProxyProvider?,
        continuation: CheckedContinuation<ProgressiveTransmuxSession, Error>
    ) {
        var inputCtx: UnsafeMutablePointer<AVFormatContext>?
        var outputCtx: UnsafeMutablePointer<AVFormatContext>?
        var continuationResumed = false

        // --- Initialize C-level logging to the same file TransmuxLog uses ---
        // Routes FFmpegHelper diagnostics and FFmpeg av_log messages
        // to /tmp/mks-iptv-transmux.log so the web log viewer sees everything.
        mks_log_init(TransmuxLog.filePath)

        // --- Open input ---
        var inputOptions: OpaquePointer?
        av_dict_set(&inputOptions, "user_agent", "VLC/3.0.18 LibVLC/3.0.18", 0)
        av_dict_set(&inputOptions, "timeout", "30000000", 0)
        av_dict_set(&inputOptions, "reconnect", "1", 0)
        av_dict_set(&inputOptions, "reconnect_streamed", "1", 0)
        av_dict_set(&inputOptions, "reconnect_delay_max", "5", 0)
        av_dict_set(&inputOptions, "probesize", "33554432", 0)
        av_dict_set(&inputOptions, "analyzeduration", "30000000", 0)

        var ret = avformat_open_input(&inputCtx, inputPath, nil, &inputOptions)
        av_dict_free(&inputOptions)
        guard ret >= 0, inputCtx != nil else {
            continuation.resume(throwing: TransmuxError.processStartFailure(
                NSError(domain: "FFmpeg", code: Int(ret),
                        userInfo: [NSLocalizedDescriptionKey: "avformat_open_input failed (\(ret))"])
            ))
            return
        }

        guard let inCtx = inputCtx else {
            avformat_close_input(&inputCtx)
            continuation.resume(throwing: TransmuxError.processStartFailure(
                NSError(domain: "FFmpeg", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "inputCtx became nil after open"])
            ))
            return
        }

        let streamCount = Int(mks_format_get_nb_streams(inCtx))
        TransmuxLog.service("avformat_open_input OK, nb_streams=\(streamCount)")

        ret = avformat_find_stream_info(inCtx, nil)
        guard ret >= 0 else {
            TransmuxLog.service("avformat_find_stream_info FAILED: \(ret)", level: .error)
            avformat_close_input(&inputCtx)
            continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
            return
        }

        av_dump_format(inCtx, 0, inputPath, 0)

        // Extract duration and expected size
        let durationSeconds = Double(inCtx.pointee.duration) / Double(AV_TIME_BASE)
        let bitrate = inCtx.pointee.bit_rate
        let expectedSize: Int64
        if bitrate > 0 && durationSeconds > 0 {
            expectedSize = Int64(Double(bitrate) / 8.0 * durationSeconds * 1.02)
        } else {
            expectedSize = 0
        }
        TransmuxLog.service("Duration: \(String(format: "%.1f", durationSeconds))s, bitrate: \(bitrate)bps, expectedSize: \(expectedSize)")

        // Use av_find_best_stream for stream selection
        let bestVideo = av_find_best_stream(inCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        let bestAudio = av_find_best_stream(inCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        TransmuxLog.service("Best streams: video=\(bestVideo) audio=\(bestAudio)")

        // --- Allocate output (always fragmented MP4 for progressive playback) ---
        let mp4Path = outputDir.appendingPathComponent("stream.mp4").path
        ret = avformat_alloc_output_context2(&outputCtx, nil, "mp4", mp4Path)
        guard ret >= 0, let outCtx = outputCtx else {
            avformat_close_input(&inputCtx)
            continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
            return
        }

        // --- Map streams ---
        var streamMapping = [Int](repeating: -1, count: streamCount)
        var outputStreamIndex: Int32 = 0

        let selectedStreams = [(bestVideo, "video"), (bestAudio, "audio")]
        for (streamIdx, label) in selectedStreams {
            guard streamIdx >= 0 else { continue }

            streamMapping[Int(streamIdx)] = Int(outputStreamIndex)
            outputStreamIndex += 1

            guard let outStream = avformat_new_stream(outCtx, nil) else {
                avformat_close_input(&inputCtx)
                if outCtx.pointee.pb != nil { avio_close(outCtx.pointee.pb) }
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: -1))
                return
            }

            ret = mks_stream_copy_codecpar(outStream, inCtx, Int32(streamIdx))
            guard ret >= 0 else {
                avformat_close_input(&inputCtx)
                if outCtx.pointee.pb != nil { avio_close(outCtx.pointee.pb) }
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
                return
            }

            TransmuxLog.service("Mapped \(label) stream[\(streamIdx)] -> output[\(outputStreamIndex - 1)]")
        }

        guard outputStreamIndex > 0 else {
            TransmuxLog.service("No video or audio streams found", level: .error)
            avformat_close_input(&inputCtx)
            avformat_free_context(outCtx)
            continuation.resume(throwing: TransmuxError.processFailure(status: -1))
            return
        }
        TransmuxLog.service("Mapped \(outputStreamIndex) output stream(s)")

        // Set the overall container duration for seeking support during progressive transmux.
        // This allows AVPlayer to know the duration immediately, enabling seeking.
        // Note: We set container duration only - stream durations will be derived from it.
        if durationSeconds > 0 && durationSeconds.isFinite {
            let containerDuration = Int64(durationSeconds * Double(AV_TIME_BASE))
            outCtx.pointee.duration = containerDuration
            TransmuxLog.service("Set container duration: \(containerDuration) (\(durationSeconds)s)")
        }

        // --- Create aac_adtstoasc BSF for AAC audio from MPEG-TS ---
        // MPEG-TS wraps AAC in ADTS format. The MP4 muxer requires raw AAC (ASC).
        // The aac_adtstoasc BSF strips ADTS headers, fixing "Malformed AAC bitstream".
        var aacBsfCtx: UnsafeMutableRawPointer?
        let audioInputStreamIndex: Int32 = bestAudio  // -1 if no audio
        var hasAC3Audio = false
        if bestAudio >= 0 {
            let audioCodecId = mks_stream_get_codec_id(inCtx, bestAudio)
            // AV_CODEC_ID_AAC = 86018, AV_CODEC_ID_AC3 = 86019, AV_CODEC_ID_EAC3 = 86056
            if audioCodecId == 86018 {
                aacBsfCtx = mks_bsf_create_aac_adtstoasc(inCtx, bestAudio)
                if aacBsfCtx != nil {
                    TransmuxLog.service("aac_adtstoasc BSF enabled for audio stream \(bestAudio)")
                } else {
                    TransmuxLog.service("WARNING: Failed to create aac_adtstoasc BSF, audio may fail", level: .warn)
                }
            } else if audioCodecId == 86019 || audioCodecId == 86056 {
                hasAC3Audio = true
                TransmuxLog.service("AC3/EAC3 audio detected (codecId=\(audioCodecId)), will use delay_moov")
            }
        }

        // For AC3 (not EAC3): set frame_size=1536 so delay_moov is not needed.
        // AC3 frames are always 1536 samples. With frame_size set, empty_moov
        // writes the moov immediately -- no init phase needed.
        //
        // EAC3 REQUIRES delay_moov: FFmpeg's mp4 muxer must parse actual EAC3
        // frames to build AudioSpecificConfig in the moov atom. Setting frame_size
        // alone triggers "Cannot write moov atom before EAC3 packets parsed".
        // However, we set frame_size=1536 IN ADDITION TO delay_moov so that
        // the trex box gets default_sample_duration=1536 instead of 0.
        // Without this, AVPlayer fails to build CMTimebase from the moov.
        // For EAC3, the init phase runs but we continue from current position
        // (no truncate/rewind) to keep DTS monotonic.
        if hasAC3Audio && bestAudio >= 0 {
            let audioCodecId = mks_stream_get_codec_id(inCtx, bestAudio)
            let audioOutIdx = Int32(streamMapping[Int(bestAudio)])
            if audioCodecId == 86019 {
                // Pure AC3: frame_size eliminates delay_moov
                mks_stream_set_frame_size(outCtx, audioOutIdx, 1536)
                hasAC3Audio = false
                TransmuxLog.service("AC3: set frame_size=1536, using empty_moov (no delay_moov)")
            } else {
                // EAC3: delay_moov required for AudioSpecificConfig, but we ALSO set
                // frame_size so the trex box gets default_sample_duration=1536 instead of 0.
                // Without this, AVPlayer can't build a valid CMTimebase from the moov.
                mks_stream_set_frame_size(outCtx, audioOutIdx, 1536)
                TransmuxLog.service("EAC3: delay_moov + frame_size=1536, will continue from init position (no truncate/rewind)")
            }
        }

        // --- Set fragmented MP4 muxer options ---
        // - frag_keyframe: Start new fragment at each keyframe
        // - empty_moov: Write initial moov without sample data
        // - default_base_moof: Use default base for moof offsets
        // - delay_moov: ONLY for AC3/EAC3 fallback (when extradata is missing, e.g. MPEG-TS)
        //
        // For AAC/H.264 and AC3 with frame_size set: moov is written immediately after
        // avformat_write_header(), allowing HLSSegmenter to extract it as init.mp4 right away.
        //
        // For AC3/EAC3 without extradata (rare): delay_moov is required. The init phase
        // writes packets until moov appears, then continues from that position (no rewind).
        var options: OpaquePointer?
        let movflags = hasAC3Audio
            ? "frag_keyframe+empty_moov+delay_moov+default_base_moof"
            : "frag_keyframe+empty_moov+default_base_moof"
        av_dict_set(&options, "movflags", movflags, 0)
        TransmuxLog.service("Using movflags: \(movflags)")

        // --- Open output file ---
        TransmuxLog.service("Opening output: \(mp4Path)")
        let oformatFlags = outCtx.pointee.oformat.pointee.flags
        if oformatFlags & AVFMT_NOFILE == 0 {
            ret = avio_open(&outCtx.pointee.pb, mp4Path, AVIO_FLAG_WRITE)
            guard ret >= 0 else {
                av_dict_free(&options)
                avformat_close_input(&inputCtx)
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
                return
            }
        }

        // --- Write header (Phase 1 complete) ---
        TransmuxLog.service("Calling avformat_write_header...")
        ret = avformat_write_header(outCtx, &options)
        av_dict_free(&options)
        guard ret >= 0 else {
            if outCtx.pointee.pb != nil { avio_close(outCtx.pointee.pb) }
            avformat_close_input(&inputCtx)
            avformat_free_context(outCtx)
            continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
            return
        }

        // CRITICAL: Flush the AVIO buffer to disk immediately.
        // avformat_write_header writes ftyp + moov to FFmpeg's internal AVIO buffer
        // (~32KB). Since ftyp (~28B) + moov (~500B) = ~530B total, the buffer never
        // auto-flushes. Without this, the resource loader reads an empty/tiny file,
        // AVPlayer never sees the moov atom, and never reaches .readyToPlay.
        //
        // SPECIAL CASE: For AC3/EAC3 with delay_moov, the moov is NOT written until the first
        // packet is processed. We need to write a few initial packets to force the moov to disk.
        avio_flush(outCtx.pointee.pb)

        var headerFileSize = Self.fileSize(at: mp4Path)
        TransmuxLog.service("Header written and flushed to disk (\(headerFileSize) bytes on disk)")

        // Track last written DTS for each stream (needed for timestamp rebasing after seeks)
        // Initialize BEFORE AC3 initial phase so we track those packets too
        var lastWrittenDts: [Int32: Int64] = [:]
        let AV_NOPTS = Int64(bitPattern: UInt64(0x8000000000000000))

        // AC3/EAC3 with delay_moov: write packets until moov is flushed to disk
        // The moov won't be written until AVIO buffer fills (~32KB) or enough data accumulates.
        // We MUST wait for the moov to be on disk before resuming the continuation,
        // otherwise initSegmentSize=0 → TransmuxServer can't serve init.mp4 → 404 → playback fails.
        if hasAC3Audio && headerFileSize < 100 {
            TransmuxLog.service("AC3/EAC3 detected with small init - writing packets until moov appears on disk...")
            var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
            var packetsWritten = 0
            let maxInitialPackets = 500  // Safety limit to prevent infinite loop
            let targetInitSize: Int64 = 1000  // Moov should be at least ~800 bytes

            while packetsWritten < maxInitialPackets && headerFileSize < targetInitSize {
                ret = av_read_frame(inCtx, packet)
                if ret < 0 {
                    TransmuxLog.service("EOF or error during initial packet read (ret=\(ret))", level: .warn)
                    break
                }

                guard let pkt = packet else { break }
                let streamIndex = Int(pkt.pointee.stream_index)
                guard streamIndex < streamCount, streamMapping[streamIndex] >= 0 else {
                    av_packet_unref(pkt)
                    continue
                }

                let outStreamIdx = Int32(streamMapping[streamIndex])
                pkt.pointee.stream_index = outStreamIdx
                mks_packet_rescale_ts(pkt, inCtx, Int32(streamIndex), outCtx, outStreamIdx)
                mks_packet_clear_pos(pkt)

                // Save DTS before write — av_interleaved_write_frame unrefs the packet
                let dts = mks_packet_get_dts(pkt)

                ret = av_interleaved_write_frame(outCtx, pkt)
                if ret < 0 {
                    TransmuxLog.service("Initial packet write failed (ret=\(ret))", level: .warn)
                    av_packet_unref(pkt)
                    break
                }

                // Track DTS of written packets (saved before write)
                if dts != AV_NOPTS {
                    lastWrittenDts[outStreamIdx] = dts
                }

                packetsWritten += 1
                av_packet_unref(pkt)

                // Check file size every 10 packets
                if packetsWritten % 10 == 0 {
                    avio_flush(outCtx.pointee.pb)
                    headerFileSize = Self.fileSize(at: mp4Path)
                    if headerFileSize >= targetInitSize {
                        TransmuxLog.service("Moov written to disk after \(packetsWritten) packets (\(headerFileSize) bytes)")
                        break
                    }
                }
            }

            av_packet_free(&packet)
            avio_flush(outCtx.pointee.pb)

            headerFileSize = Self.fileSize(at: mp4Path)
            TransmuxLog.service("AC3 init phase complete: \(packetsWritten) packets written, \(headerFileSize) bytes on disk")

            // If still 0 bytes, this is a critical error
            if headerFileSize < 100 {
                TransmuxLog.service("CRITICAL: AC3 moov still not written after \(packetsWritten) packets", level: .error)
            }

            // AC3 init phase produced moov + first fragments. Continue from here.
            // DO NOT truncate or rewind -- the muxer's internal DTS state can't be reset.
            TransmuxLog.service("AC3 init phase complete, continuing from current position (no truncate/rewind)")

            // The file now contains [ftyp][moov][moof][mdat]... but the HLS init segment
            // (/init.mp4) must be ONLY [ftyp][moov]. The moof+mdat fragments from the init
            // phase are regular media data — HLSSegmenter will scan and serve them as segments.
            // Without this fix, AVPlayer gets a 7MB "init segment" containing media data,
            // which corrupts CMTimebase setup and causes audio cutting.
            let trueInitSize = Self.findInitSegmentEnd(at: mp4Path)
            if trueInitSize > 0 && trueInitSize < headerFileSize {
                TransmuxLog.service("AC3 init: total file=\(headerFileSize) bytes, true init (ftyp+moov)=\(trueInitSize) bytes, \(headerFileSize - trueInitSize) bytes of fragments will be scanned as HLS segments")
                headerFileSize = trueInitSize
            }
        }

        // Verify init segment has reasonable size (should be 400-800 bytes for typical streams)
        if headerFileSize < 100 {
            TransmuxLog.service("WARNING: Init segment suspiciously small (\(headerFileSize) bytes), may cause playback issues", level: .warn)
        }

        // Create HLS segmenter with known duration to generate a VOD playlist upfront
        let playlistPath = outputDir.appendingPathComponent("stream.m3u8").path
        let segmenter = HLSSegmenter(
            fmp4Path: mp4Path,
            playlistPath: playlistPath,
            initSegmentSize: headerFileSize,
            duration: durationSeconds
        )
        segmenter.start()
        handle.segmenter = segmenter

        TransmuxLog.service("HLS segmenter started with VOD playlist, resuming caller for progressive playback")

        // Resume the continuation: caller gets the session and can start AVPlayer.
        // Pass the ActiveTransmux handle so TransmuxServer can request seek-redirects.
        let session = ProgressiveTransmuxSession(
            sessionID: sessionID,
            outputPath: mp4Path,
            playlistPath: playlistPath,
            expectedSize: expectedSize,
            duration: durationSeconds,
            segmenter: segmenter,
            initSegmentSize: headerFileSize,
            seekHandle: handle
        )
        continuation.resume(returning: session)
        continuationResumed = true

        // --- Phase 2: Remux loop (continues on this background thread) ---
        TransmuxLog.remux("Starting remux loop (videoOut=\(bestVideo) audioOut=\(bestAudio) streams=\(outputStreamIndex))")
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        var packetCount = 0
        var lastProgressLog = 0
        var totalSeekCount = 0

        // --- Per-stream timestamp rebasing after seek ---
        // Each stream gets its OWN rebase offset because output streams may have
        // different timebases (e.g. video at 90kHz, audio at 48kHz). A single
        // global offset in one timebase produces non-monotonic DTS in the other.
        // The video offset is computed from buffered keyframes; the audio offset
        // is computed from the first rescaled buffered audio packet's DTS.
        var streamRebaseOffsets: [Int32: Int64] = [:]
        // Note: lastWrittenDts and AV_NOPTS are declared above (before AC3 initial phase)

        // State for computing offsets after seek
        // Buffer first N video keyframes; use MINIMUM DTS (not average) to guarantee
        // the earliest keyframe maps to exactly lastWrittenDts + 1.
        var bufferedVideoKeyframes: [UnsafeMutablePointer<AVPacket>] = []
        var firstNVideoDtsAfterSeek: [Int64] = []
        let videoDtsAveragingCount = 1
        var globalOffsetComputed = false

        // After a seek: skip packets until first video keyframe, then compute global offset.
        var seekPending = false
        var videoKeyframeReceived = false
        var skippedPacketsAfterSeek = 0

        // Audio packet buffer during seek: instead of discarding audio packets,
        // buffer them and process after video keyframe establishes global offset.
        // This preserves A/V sync by keeping the temporal relationship intact.
        // Helper function to free a packet from the buffer
        func freePacketFromBuffer(_ ptr: UnsafeMutablePointer<AVPacket>) {
            var mutablePtr: UnsafeMutablePointer<AVPacket>? = ptr
            av_packet_free(&mutablePtr)
        }
        var pendingAudioPackets: [UnsafeMutablePointer<AVPacket>] = []
        let maxPendingAudioPackets = 500  // ~10 seconds of audio at 50 pkt/sec (handles longer seeks)

        // Map output stream indices for video and audio
        let videoOutputIdx: Int32 = bestVideo >= 0 ? Int32(streamMapping[Int(bestVideo)]) : -1
        let audioOutputIdx: Int32 = bestAudio >= 0 ? Int32(streamMapping[Int(bestAudio)]) : -1

        // Seek cooldown: require minimum time between seeks to prevent cascading
        var lastSeekCompletionTime: Date? = nil
        let seekCooldownSeconds: TimeInterval = 2.0

        while !handle.isCancelled {
            // Check for seek request BEFORE reading next packet.
            // This redirects the INPUT to a new position while keeping the
            // SAME output context — all moof+mdat remain compatible with the init segment.
            // Timestamp rebasing ensures output DTS stays monotonically increasing.
            //
            // CRITICAL: Only accept a new seek when the previous seek's rebase is
            // fully complete (all streams have their offsets). Without this guard,
            // seeks cascade faster than audio can be rebased, leaving audio at a
            // stale DTS offset → permanent A/V desync.
            if !seekPending, let seekTime = handle.consumeSeekRequest() {
                // Check cooldown: prevent rapid seeks that overwhelm timestamp rebasing
                if let lastCompletion = lastSeekCompletionTime {
                    let elapsed = Date().timeIntervalSince(lastCompletion)
                    if elapsed < seekCooldownSeconds {
                        TransmuxLog.remux("REJECTING seek, cooldown not met (elapsed=\(String(format: "%.1f", elapsed))s, required=\(seekCooldownSeconds)s)", level: .warn)
                        continue
                    }
                }
                totalSeekCount += 1
                let preSeekDts = lastWrittenDts.map { "stream\($0.key)=\($0.value)" }.joined(separator: ", ")
                TransmuxLog.remux("===== SEEK #\(totalSeekCount) to \(String(format: "%.1f", seekTime))s =====")

                // 1. Flush the interleaver queue — writes any buffered packets
                av_interleaved_write_frame(outCtx, nil)
                avio_flush(outCtx.pointee.pb)
                // Flushed interleaver + AVIO

                // 2. Flush input demuxer buffers (stale MPEG-TS PES packets)
                mks_format_flush_input(inCtx)

                // 3. Seek the input — CHECK return value
                let seekTS = Int64(seekTime * Double(AV_TIME_BASE))
                let seekRet = av_seek_frame(inCtx, -1, seekTS, AVSEEK_FLAG_BACKWARD)
                if seekRet < 0 {
                    TransmuxLog.remux("WARNING: av_seek_frame failed (\(seekRet)), continuing from current position", level: .warn)
                    continue
                }
                // av_seek_frame OK

                // 4. Flush AAC BSF state (partial ADTS frames from before seek)
                if let bsf = aacBsfCtx {
                    mks_bsf_flush(bsf)
                    // AAC BSF flushed
                }

                // 5. Set seek-pending: skip until video keyframe, then compute global offset
                seekPending = true
                videoKeyframeReceived = false
                skippedPacketsAfterSeek = 0
                globalOffsetComputed = false

                // Clear buffered video keyframes from previous seek
                for pkt in bufferedVideoKeyframes {
                    var mutablePtr: UnsafeMutablePointer<AVPacket>? = pkt
                    av_packet_free(&mutablePtr)
                }
                bufferedVideoKeyframes.removeAll()
                firstNVideoDtsAfterSeek.removeAll()

                // 6. Notify segmenter with source time for virtual-to-real mapping
                segmenter.notifySeekDiscontinuity(seekTargetTime: seekTime)

                packetCount = 0  // reset for aggressive flushing after seek
                // Seek prepared: awaiting video keyframe
                continue
            }

            // Safety valve: if seekPending for too many packets, force-clear to prevent lockout.
            // This can happen if a stream has no packets after seek (e.g., video-only source).
            if seekPending && packetCount > 500 {
                TransmuxLog.remux("WARNING: force-clearing seekPending after \(packetCount) packets", level: .warn)
                seekPending = false
                globalOffsetComputed = true
            }

            ret = av_read_frame(inCtx, packet)
            if ret < 0 {
                TransmuxLog.remux("av_read_frame ended: ret=\(ret) (EOF or error)")
                break
            }

            guard let pkt = packet else {
                TransmuxLog.remux("Warning: packet became nil, ending remux loop", level: .warn)
                break
            }
            let streamIndex = Int(pkt.pointee.stream_index)
            guard streamIndex < streamCount, streamMapping[streamIndex] >= 0 else {
                av_packet_unref(pkt)
                continue
            }

            let outStreamIdx = Int32(streamMapping[streamIndex])
            let isVideo = outStreamIdx == videoOutputIdx
            let rawDtsBefore = mks_packet_get_dts(pkt)
            let rawPtsBefore = mks_packet_get_pts(pkt)

            // Filter AAC audio packets through aac_adtstoasc BSF BEFORE rescaling.
            // The BSF expects packets in the input stream's time_base.
            if let bsf = aacBsfCtx, Int32(streamIndex) == audioInputStreamIndex {
                let bsfRet = mks_bsf_filter_packet(bsf, pkt)
                if bsfRet < 0 {
                    if seekPending {
                        TransmuxLog.remux("BSF filter failed (ret=\(bsfRet)) during seek-pending, skipping", level: .warn)
                    }
                    av_packet_unref(pkt)
                    packetCount += 1
                    continue
                }
            }

            // --- Keyframe handling after seek ---
            // Buffer audio packets until the global offset is fully computed.
            // Video non-keyframes are skipped (can't start decoding from them).
            // Audio MUST be buffered for the ENTIRE seek-pending period — not just
            // until the first video keyframe. Without this, audio packets that arrive
            // between videoKeyframeReceived=true and globalOffsetComputed=true bypass
            // the buffer and get written with offset=0, corrupting the timeline.
            if seekPending && !globalOffsetComputed {
                skippedPacketsAfterSeek += 1
                if outStreamIdx == videoOutputIdx {
                    if !videoKeyframeReceived {
                        if mks_packet_is_keyframe(pkt) == 0 {
                            // Skip non-keyframe video before first keyframe
                            av_packet_unref(pkt)
                            packetCount += 1
                            continue
                        }
                        videoKeyframeReceived = true
                        // First video keyframe after seek
                    }
                    // Video keyframes fall through to the offset computation block below
                } else {
                    // Buffer ALL audio packets until global offset is computed
                    if pendingAudioPackets.count < maxPendingAudioPackets {
                        if let clonedPkt = av_packet_clone(pkt) {
                            pendingAudioPackets.append(clonedPkt)
                        }
                    } else {
                        TransmuxLog.remux("WARNING: audio buffer full (\(pendingAudioPackets.count) packets), dropping oldest", level: .warn)
                        let old = pendingAudioPackets.removeFirst()
                        freePacketFromBuffer(old)
                        if let clonedPkt = av_packet_clone(pkt) {
                            pendingAudioPackets.append(clonedPkt)
                        }
                    }
                    av_packet_unref(pkt)
                    packetCount += 1
                    continue
                }
            }

            pkt.pointee.stream_index = outStreamIdx
            mks_packet_rescale_ts(pkt, inCtx, Int32(streamIndex), outCtx, outStreamIdx)
            mks_packet_clear_pos(pkt)

            let rescaledDtsBeforeRebase = mks_packet_get_dts(pkt)
            let rescaledPtsBeforeRebase = mks_packet_get_pts(pkt)

            // --- Per-stream timestamp rebasing after seek ---
            // Buffer video keyframes to compute the video offset, then derive
            // the audio offset from the first rescaled buffered audio packet.
            // Using MINIMUM DTS (not average) guarantees monotonicity.
            if seekPending && !globalOffsetComputed {
                if isVideo && videoKeyframeReceived {
                    var newDts = mks_packet_get_dts(pkt)

                    // Recover keyframes with invalid DTS but valid PTS (common after av_seek_frame)
                    // For keyframes, DTS <= PTS. Use PTS as DTS estimate to avoid losing ~80ms of video.
                    if newDts == AV_NOPTS {
                        let pts = mks_packet_get_pts(pkt)
                        if pts != AV_NOPTS {
                            mks_packet_set_dts(pkt, pts)
                            newDts = pts
                            // Recovered AV_NOPTS keyframe using PTS
                        } else {
                            TransmuxLog.remux("Skipping keyframe: both DTS and PTS are AV_NOPTS", level: .warn)
                            av_packet_unref(pkt)
                            packetCount += 1
                            continue
                        }
                    }

                    if bufferedVideoKeyframes.count < videoDtsAveragingCount {
                        // Buffer this keyframe and collect its DTS
                        if let clonedPkt = av_packet_clone(pkt) {
                            bufferedVideoKeyframes.append(clonedPkt)
                            firstNVideoDtsAfterSeek.append(newDts)
                            // Keyframe buffered
                        }

                        // Don't write yet - wait until we have N keyframes
                        av_packet_unref(pkt)
                        packetCount += 1
                        continue
                    }

                    // Once we have N keyframes, compute per-stream offsets
                    if bufferedVideoKeyframes.count >= videoDtsAveragingCount {
                        let anchorDts = firstNVideoDtsAfterSeek[0]

                        // Query output stream timebases
                        var vTbNum: Int32 = 0, vTbDen: Int32 = 0
                        var aTbNum: Int32 = 0, aTbDen: Int32 = 0
                        mks_stream_get_time_base(outCtx, videoOutputIdx, &vTbNum, &vTbDen)
                        if audioOutputIdx >= 0 {
                            mks_stream_get_time_base(outCtx, audioOutputIdx, &aTbNum, &aTbDen)
                        }

                        // Compute target output ticks for each stream using INTEGER math.
                        // Cross-convert each stream's last DTS into the other's timebase,
                        // then take the max + 1. This guarantees:
                        //   1. Both streams advance past their own last DTS (monotonic)
                        //   2. Both streams land at the same wall-clock time (A/V sync)
                        // Using ceil() on cross-timebase conversion prevents the truncation
                        // bug where 1/90000 epsilon vanishes in 48kHz audio ticks.
                        let lastVTicks = lastWrittenDts[videoOutputIdx] ?? 0
                        let lastATicks = (audioOutputIdx >= 0) ? (lastWrittenDts[audioOutputIdx] ?? 0) : Int64(0)

                        let targetVideoTicks: Int64
                        let targetAudioTicks: Int64
                        if vTbDen > 0 && aTbDen > 0 && lastVTicks != AV_NOPTS && lastATicks != AV_NOPTS {
                            // Cross-timebase: last audio time in video ticks and vice versa
                            let lastAInVTicks = Int64(ceil(Double(lastATicks) / Double(aTbDen) * Double(vTbDen)))
                            let lastVInATicks = Int64(ceil(Double(lastVTicks) / Double(vTbDen) * Double(aTbDen)))
                            targetVideoTicks = max(lastVTicks, lastAInVTicks) + 1
                            targetAudioTicks = max(lastATicks, lastVInATicks) + 1
                        } else {
                            targetVideoTicks = lastVTicks + 1
                            targetAudioTicks = lastATicks + 1
                        }

                        // Derive video offset
                        let videoOffset: Int64
                        if vTbDen > 0, lastWrittenDts[videoOutputIdx] != nil {
                            videoOffset = targetVideoTicks - anchorDts
                            streamRebaseOffsets[videoOutputIdx] = videoOffset
                        } else {
                            videoOffset = 0
                            streamRebaseOffsets[videoOutputIdx] = 0
                        }

                        let targetVSec = vTbDen > 0 ? Double(targetVideoTicks) / Double(vTbDen) : 0
                        let targetASec = aTbDen > 0 ? Double(targetAudioTicks) / Double(aTbDen) : 0
                        TransmuxLog.remux("Seek #\(totalSeekCount) OFFSETS: videoTarget=\(String(format: "%.3f", targetVSec))s audioTarget=\(String(format: "%.3f", targetASec))s videoOffset=\(videoOffset) (lastV=\(String(format: "%.3f", Double(lastVTicks)/max(1, Double(vTbDen))))s lastA=\(String(format: "%.3f", Double(lastATicks)/max(1, Double(aTbDen))))s)")

                        globalOffsetComputed = true
                        seekPending = false
                        lastSeekCompletionTime = Date()

                        // Write buffered video keyframe
                        for videoPkt in bufferedVideoKeyframes {
                            if videoOffset != 0 {
                                mks_packet_adjust_ts(videoPkt, videoOffset)
                            }
                            let videoDts = mks_packet_get_dts(videoPkt)
                            ret = av_interleaved_write_frame(outCtx, videoPkt)
                            if ret >= 0, videoDts != AV_NOPTS {
                                lastWrittenDts[videoOutputIdx] = videoDts
                            }
                            packetCount += 1
                            var mutablePtr: UnsafeMutablePointer<AVPacket>? = videoPkt
                            av_packet_free(&mutablePtr)
                        }
                        bufferedVideoKeyframes.removeAll()

                        // Process buffered audio packets
                        if !pendingAudioPackets.isEmpty {
                            var audioOffsetComputed = false

                            for audioPkt in pendingAudioPackets {
                                let audioInStreamIdx = Int(audioPkt.pointee.stream_index)
                                guard audioInStreamIdx < streamCount, streamMapping[audioInStreamIdx] >= 0 else {
                                    freePacketFromBuffer(audioPkt)
                                    continue
                                }
                                let audioOutIdx = Int32(streamMapping[audioInStreamIdx])

                                // Rescale timestamps to output timebase (BSF already applied)
                                audioPkt.pointee.stream_index = audioOutIdx
                                mks_packet_rescale_ts(audioPkt, inCtx, Int32(audioInStreamIdx), outCtx, audioOutIdx)
                                mks_packet_clear_pos(audioPkt)

                                // Compute audio offset from target ticks (integer-precise)
                                if !audioOffsetComputed {
                                    let firstAudioDts = mks_packet_get_dts(audioPkt)
                                    if firstAudioDts != AV_NOPTS {
                                        if lastWrittenDts[audioOutIdx] != nil, aTbDen > 0 {
                                            let audioOffset = targetAudioTicks - firstAudioDts
                                            streamRebaseOffsets[audioOutIdx] = audioOffset
                                            TransmuxLog.remux("Seek #\(totalSeekCount) AUDIO: offset=\(audioOffset) firstDts=\(firstAudioDts) → targetTick=\(targetAudioTicks)")
                                        } else {
                                            streamRebaseOffsets[audioOutIdx] = 0
                                        }
                                        audioOffsetComputed = true
                                    }
                                }

                                // Apply offset
                                let audioOff = streamRebaseOffsets[audioOutIdx] ?? 0
                                if audioOff != 0 {
                                    mks_packet_adjust_ts(audioPkt, audioOff)
                                }

                                var audioTrackDts = mks_packet_get_dts(audioPkt)

                                // Skip non-monotonic audio (expected for first packet at seek boundary)
                                if audioTrackDts != AV_NOPTS {
                                    if let prevDts = lastWrittenDts[audioOutIdx], audioTrackDts <= prevDts {
                                        freePacketFromBuffer(audioPkt)
                                        packetCount += 1
                                        continue
                                    }
                                }

                                ret = av_interleaved_write_frame(outCtx, audioPkt)
                                if ret >= 0, audioTrackDts != AV_NOPTS {
                                    lastWrittenDts[audioOutIdx] = audioTrackDts
                                }
                                packetCount += 1
                                freePacketFromBuffer(audioPkt)
                            }
                            pendingAudioPackets.removeAll()

                            // A/V sync diagnostic
                            if videoOutputIdx >= 0 && audioOutputIdx >= 0,
                               let vDts = lastWrittenDts[videoOutputIdx],
                               let aDts = lastWrittenDts[audioOutputIdx],
                               vTbDen > 0, aTbDen > 0 {
                                let vSec = Double(vDts) / Double(vTbDen)
                                let aSec = Double(aDts) / Double(aTbDen)
                                TransmuxLog.remux("Seek #\(totalSeekCount) SYNC: video=\(String(format: "%.3f", vSec))s audio=\(String(format: "%.3f", aSec))s gap=\(String(format: "%.3f", aSec - vSec))s")
                            }
                        } else {
                            TransmuxLog.remux("Seek #\(totalSeekCount) COMPLETE (no buffered audio)")
                        }

                        // Current packet (4th+ keyframe) needs to continue processing normally
                        // Fall through to normal packet write below
                    }
                }
            }

            // Apply per-stream rebase offset
            if let offset = streamRebaseOffsets[outStreamIdx], offset != 0 {
                mks_packet_adjust_ts(pkt, offset)
            }

            let rescaledDts = mks_packet_get_dts(pkt)
            let rescaledPts = mks_packet_get_pts(pkt)

            // Save DTS before write — av_interleaved_write_frame unrefs the packet,
            // resetting dts to AV_NOPTS_VALUE, so we must capture it beforehand.
            var dtsToTrack = rescaledDts

            // Detect and handle non-monotonic DTS BEFORE writing
            if rescaledDts != AV_NOPTS {
                if let prevDts = lastWrittenDts[outStreamIdx], rescaledDts <= prevDts {
                    if isVideo {
                        // Video: silently drop (expected B-frames after seek)
                        av_packet_unref(pkt)
                        packetCount += 1
                        continue
                    } else {
                        // Audio: recover severe backward jumps
                        let dtsDelta = rescaledDts - prevDts
                        if dtsDelta < -2000 {
                            let correctedDts = prevDts + 1
                            mks_packet_adjust_ts(pkt, correctedDts - rescaledDts)
                            dtsToTrack = correctedDts
                        }
                    }
                }
            }

            ret = av_interleaved_write_frame(outCtx, pkt)
            if ret < 0 {
                TransmuxLog.remux("write_frame ERROR (\(ret)) at packet \(packetCount), stream=\(outStreamIdx) dts=\(dtsToTrack)", level: .error)
            } else if dtsToTrack != AV_NOPTS {
                lastWrittenDts[outStreamIdx] = dtsToTrack
            }
            packetCount += 1

            // Flush AVIO buffer to disk periodically for progressive playback.
            // Aggressive at start (every 50 packets) so AVPlayer gets first fragments
            // ASAP, then less frequent (every 500 packets) to reduce syscall overhead.
            if packetCount < 500 {
                if packetCount % 50 == 0 {
                    avio_flush(outCtx.pointee.pb)
                }
            } else if packetCount % 500 == 0 {
                avio_flush(outCtx.pointee.pb)
            }

            if packetCount / 5000 > lastProgressLog {
                lastProgressLog = packetCount / 5000
                let currentSize = Self.fileSize(at: mp4Path)
                TransmuxLog.remux("Progress: \(packetCount) packets, \(currentSize / 1_048_576) MB, seeks=\(totalSeekCount)")
            }
        }

        av_packet_free(&packet)

        // --- Cleanup BSF ---
        if aacBsfCtx != nil {
            mks_bsf_free(aacBsfCtx)
            aacBsfCtx = nil
        }

        // --- Finalize ---
        let finalDtsState = lastWrittenDts.sorted(by: { $0.key < $1.key }).map { "s\($0.key)=\($0.value)" }.joined(separator: " ")
        if handle.isCancelled {
            TransmuxLog.remux("Transmux CANCELLED for session \(sessionID) after \(packetCount) packets, \(totalSeekCount) seeks, finalDts=[\(finalDtsState)]")
        } else {
            TransmuxLog.remux("Writing trailer...")
            av_write_trailer(outCtx)
            TransmuxLog.remux("Transmux COMPLETE for session \(sessionID), \(packetCount) packets, \(totalSeekCount) seeks, finalDts=[\(finalDtsState)]")
        }

        // Finalize HLS segmenter — writes #EXT-X-ENDLIST
        segmenter.markComplete()

        // Write sentinel file so TransmuxServer knows transmux is done
        let sentinelPath = outputDir.appendingPathComponent(".transmux_complete").path
        FileManager.default.createFile(atPath: sentinelPath, contents: nil)

        // Notify TransmuxServer
        Task {
            await TransmuxServer.shared.setComplete()
        }

        // Notify FFmpegPlayerImplementation so it can reload AVPlayerItem as VOD
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .transmuxDidComplete,
                object: sessionID
            )
        }

        // Cleanup FFmpeg contexts
        if outCtx.pointee.pb != nil {
            avio_close(outCtx.pointee.pb)
        }
        avformat_free_context(outCtx)
        avformat_close_input(&inputCtx)

        // Stop StreamProxy if we were using it
        if let pid = proxySessionID, let proxy = streamProxy {
            Task {
                await proxy.stop(sessionID: pid)
            }
        }

        // NOTE: Do NOT self-cleanup here. AVPlayer is still reading the
        // fMP4 and HLS playlist from disk. Cleanup happens in
        // FFmpegPlayerImplementation.stop() -> cancelTransmux() -> cleanup().
    }

    /// Quick file size check for logging.
    private static func fileSize(at path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    /// Find the byte offset where the init segment ends (ftyp+moov only).
    /// For delay_moov AC3/EAC3, the file after the init phase contains
    /// [ftyp][moov][moof][mdat]... — the init segment should be just [ftyp][moov].
    /// Returns the offset of the first moof box, or the full file size if no moof found.
    private static func findInitSegmentEnd(at path: String) -> Int64 {
        guard let handle = FileHandle(forReadingAtPath: path) else { return 0 }
        defer { try? handle.close() }

        let totalSize = fileSize(at: path)
        var offset: UInt64 = 0

        while offset + 8 <= UInt64(totalSize) {
            do { try handle.seek(toOffset: offset) } catch { break }
            let headerData = handle.readData(ofLength: 8)
            guard headerData.count == 8 else { break }

            let size32 = headerData.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: 0, as: UInt32.self).bigEndian
            }
            let typeBytes = headerData.subdata(in: 4..<8)
            let boxType = String(data: typeBytes, encoding: .ascii) ?? "????"

            let boxSize: UInt64
            if size32 == 1 {
                let extData = handle.readData(ofLength: 8)
                guard extData.count == 8 else { break }
                boxSize = extData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            } else if size32 == 0 {
                boxSize = UInt64(totalSize) - offset
            } else {
                boxSize = UInt64(size32)
            }

            if boxSize < 8 { break }

            TransmuxLog.service("  box[\(boxType)] offset=\(offset) size=\(boxSize)")

            // First moof marks the end of the init segment
            if boxType == "moof" {
                return Int64(offset)
            }

            offset += boxSize
        }

        // No moof found — entire file is the init segment
        return totalSize
    }
}
