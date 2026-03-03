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
    public static let shared = TransmuxingService()

    private var activeSessions: [String: URL] = [:]
    private var activeTransmuxes: [String: ActiveTransmux] = [:]
    private let streamProxy: StreamProxyProvider?

    public init(streamProxy: StreamProxyProvider? = nil) {
        self.streamProxy = streamProxy
        // av_register_all() is no longer needed in FFmpeg 4+; formats are auto-registered.
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

        // --- Set fragmented MP4 muxer options ---
        // - frag_keyframe: Start new fragment at each keyframe
        // - empty_moov: Write initial moov without sample data
        // - default_base_moof: Use default base for moof offsets
        // - delay_moov: ONLY for AC3/EAC3 (required because codec frame size is not set until first packet)
        //
        // For AAC/H.264: moov is written immediately after avformat_write_header(), allowing
        // HLSSegmenter to extract it as init.mp4 right away.
        //
        // For AC3/EAC3: delay_moov is required (FFmpeg will error without it). The init.mp4
        // will be extracted after the first packet is written. This adds ~200ms delay but is necessary.
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

                ret = av_interleaved_write_frame(outCtx, pkt)
                if ret < 0 {
                    TransmuxLog.service("Initial packet write failed (ret=\(ret))", level: .warn)
                    av_packet_unref(pkt)
                    break
                }

                // Track DTS of written packets
                let dts = mks_packet_get_dts(pkt)
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

            // CRITICAL: Reset both input and output after AC3 init phase
            // The init phase wrote packets to force moov to disk. Now we need to:
            // 1. Truncate output back to just the init segment (ftyp+moov)
            // 2. Seek input back to beginning
            // 3. Reset muxer state to accept packets from DTS=0 again

            TransmuxLog.service("Resetting after AC3 init phase...")

            // Flush and truncate output to init segment size
            avio_flush(outCtx.pointee.pb)
            let initSegmentEnd = headerFileSize
            let seekResult = avio_seek(outCtx.pointee.pb, Int64(initSegmentEnd), SEEK_SET)
            if seekResult < 0 {
                TransmuxLog.service("WARNING: Failed to truncate output to init size (ret=\(seekResult))", level: .warn)
            } else {
                TransmuxLog.service("Truncated output to init segment size (\(initSegmentEnd) bytes)")
            }

            // Seek input back to beginning
            ret = av_seek_frame(inCtx, -1, 0, AVSEEK_FLAG_BACKWARD)
            if ret < 0 {
                TransmuxLog.service("WARNING: Failed to seek input to beginning (ret=\(ret))", level: .warn)
            } else {
                TransmuxLog.service("Seeked input back to beginning")
            }

            // Flush codec buffers
            avformat_flush(inCtx)

            // Reset lastWrittenDts since we're starting fresh
            lastWrittenDts.removeAll()
            TransmuxLog.service("Reset lastWrittenDts to start fresh from beginning")

            TransmuxLog.service("AC3 init phase reset complete, ready to remux from beginning")
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

        // --- Timestamp rebasing state (GLOBAL OFFSET for A/V sync) ---
        // After each seek, a SINGLE global offset is computed from the video stream
        // and applied to ALL streams. This preserves the temporal relationship
        // between audio and video, preventing A/V desync.
        var globalRebaseOffset: Int64 = 0
        // Note: lastWrittenDts and AV_NOPTS are declared above (before AC3 initial phase)

        // State for computing global offset after seek
        // Buffer first N video keyframes to compute averaged offset (more robust than single keyframe)
        var bufferedVideoKeyframes: [UnsafeMutablePointer<AVPacket>] = []
        var firstNVideoDtsAfterSeek: [Int64] = []
        let videoDtsAveragingCount = 3
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

        // Map output stream index to whether it's the video stream
        let videoOutputIdx: Int32 = bestVideo >= 0 ? Int32(streamMapping[Int(bestVideo)]) : -1

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
                TransmuxLog.remux("Pre-seek state: packetCount=\(packetCount) lastWrittenDts=[\(preSeekDts)]")
                TransmuxLog.remux("Pre-seek globalOffset=\(globalRebaseOffset)")

                // 1. Flush the interleaver queue — writes any buffered packets
                av_interleaved_write_frame(outCtx, nil)
                avio_flush(outCtx.pointee.pb)
                TransmuxLog.remux("Flushed interleaver + AVIO before seek")

                // 2. Flush input demuxer buffers (stale MPEG-TS PES packets)
                mks_format_flush_input(inCtx)

                // 3. Seek the input — CHECK return value
                let seekTS = Int64(seekTime * Double(AV_TIME_BASE))
                let seekRet = av_seek_frame(inCtx, -1, seekTS, AVSEEK_FLAG_BACKWARD)
                if seekRet < 0 {
                    TransmuxLog.remux("WARNING: av_seek_frame failed (\(seekRet)), continuing from current position", level: .warn)
                    continue
                }
                TransmuxLog.remux("av_seek_frame OK (ts=\(seekTS), ret=\(seekRet))")

                // 4. Flush AAC BSF state (partial ADTS frames from before seek)
                if let bsf = aacBsfCtx {
                    mks_bsf_flush(bsf)
                    TransmuxLog.remux("AAC BSF flushed")
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
                TransmuxLog.remux("Seek #\(totalSeekCount) prepared: awaiting video keyframe for global offset computation")
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
            // Buffer audio packets until the first video keyframe arrives.
            // Video non-keyframes are still skipped (can't start decoding from them).
            // This preserves A/V sync by keeping all audio data.
            if seekPending && !videoKeyframeReceived {
                skippedPacketsAfterSeek += 1
                if outStreamIdx == videoOutputIdx {
                    if mks_packet_is_keyframe(pkt) == 0 {
                        // Skip non-keyframe video
                        av_packet_unref(pkt)
                        packetCount += 1
                        continue
                    }
                    videoKeyframeReceived = true
                    TransmuxLog.remux("First video KEYFRAME after seek #\(totalSeekCount) at packet \(packetCount), buffer has \(pendingAudioPackets.count) audio packets, rawDts=\(rawDtsBefore) rawPts=\(rawPtsBefore)")
                } else {
                    // Buffer audio packet instead of discarding
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

            // --- Global timestamp rebasing after seek (A/V sync preserved) ---
            // Buffer the first N video keyframes to compute AVERAGED global offset.
            // Averaging is more robust against DTS outliers and jitter than using a single keyframe.
            // This SAME offset is applied to ALL streams (video AND audio),
            // preserving their temporal relationship and preventing A/V desync.
            if seekPending && !globalOffsetComputed {
                if isVideo && videoKeyframeReceived {
                    let newDts = mks_packet_get_dts(pkt)

                    // Skip keyframes with invalid DTS (can happen after seek)
                    if newDts == AV_NOPTS {
                        TransmuxLog.remux("Skipping keyframe with invalid DTS (AV_NOPTS)", level: .warn)
                        av_packet_unref(pkt)
                        packetCount += 1
                        continue
                    }

                    if bufferedVideoKeyframes.count < videoDtsAveragingCount {
                        // Buffer this keyframe and collect its DTS
                        if let clonedPkt = av_packet_clone(pkt) {
                            bufferedVideoKeyframes.append(clonedPkt)
                            firstNVideoDtsAfterSeek.append(newDts)
                            TransmuxLog.remux("Buffered video keyframe #\(bufferedVideoKeyframes.count) with DTS=\(newDts)")
                        }

                        // Don't write yet - wait until we have N keyframes
                        av_packet_unref(pkt)
                        packetCount += 1
                        continue
                    }

                    // Once we have N keyframes, compute averaged offset
                    if bufferedVideoKeyframes.count >= videoDtsAveragingCount {
                        let avgDts = firstNVideoDtsAfterSeek.reduce(0, +) / Int64(videoDtsAveragingCount)

                        // Check if we have a valid previous video DTS (not AV_NOPTS)
                        if let lastVideoDts = lastWrittenDts[videoOutputIdx], lastVideoDts != AV_NOPTS {
                            // Global offset = continue monotonically from last video DTS
                            globalRebaseOffset = lastVideoDts + 1 - avgDts
                            TransmuxLog.remux("GLOBAL OFFSET from AVERAGE: lastVideoDts=\(lastVideoDts) avgDts=\(avgDts) samples=\(firstNVideoDtsAfterSeek) → offset=\(globalRebaseOffset)")
                        } else {
                            // First video ever OR previous DTS was invalid - no offset needed
                            globalRebaseOffset = 0
                            TransmuxLog.remux("GLOBAL OFFSET: first video or invalid previous DTS, avgDts=\(avgDts) → offset=0")
                        }

                        globalOffsetComputed = true
                        seekPending = false
                        lastSeekCompletionTime = Date()
                        TransmuxLog.remux("Seek #\(totalSeekCount) COMPLETE with averaged global offset=\(globalRebaseOffset)")

                        // Write buffered video keyframes with the computed offset
                        TransmuxLog.remux("Writing \(bufferedVideoKeyframes.count) buffered video keyframes with offset=\(globalRebaseOffset)")
                        for videoPkt in bufferedVideoKeyframes {
                            // Apply global rebase offset
                            if globalRebaseOffset != 0 {
                                mks_packet_adjust_ts(videoPkt, globalRebaseOffset)
                            }

                            let videoDts = mks_packet_get_dts(videoPkt)
                            ret = av_interleaved_write_frame(outCtx, videoPkt)
                            if ret < 0 {
                                TransmuxLog.remux("Buffered video write_frame ERROR (\(ret)) dts=\(videoDts)", level: .error)
                            } else if videoDts != AV_NOPTS {
                                lastWrittenDts[videoOutputIdx] = videoDts
                            }
                            packetCount += 1

                            var mutablePtr: UnsafeMutablePointer<AVPacket>? = videoPkt
                            av_packet_free(&mutablePtr)
                        }
                        bufferedVideoKeyframes.removeAll()
                        TransmuxLog.remux("Buffered video keyframes written")

                        // Process buffered audio packets now that global offset is known
                        if !pendingAudioPackets.isEmpty {
                            TransmuxLog.remux("Processing \(pendingAudioPackets.count) buffered audio packets with offset=\(globalRebaseOffset)")
                            for audioPkt in pendingAudioPackets {
                                let audioInStreamIdx = Int(audioPkt.pointee.stream_index)
                                guard audioInStreamIdx < streamCount, streamMapping[audioInStreamIdx] >= 0 else {
                                    freePacketFromBuffer(audioPkt)
                                    continue
                                }
                                let audioOutIdx = Int32(streamMapping[audioInStreamIdx])

                                // Apply AAC BSF if needed
                                if let bsf = aacBsfCtx, Int32(audioInStreamIdx) == audioInputStreamIndex {
                                    _ = mks_bsf_filter_packet(bsf, audioPkt)
                                }

                                // Rescale timestamps
                                audioPkt.pointee.stream_index = audioOutIdx
                                mks_packet_rescale_ts(audioPkt, inCtx, Int32(audioInStreamIdx), outCtx, audioOutIdx)
                                mks_packet_clear_pos(audioPkt)

                                // Apply global rebase offset
                                if globalRebaseOffset != 0 {
                                    mks_packet_adjust_ts(audioPkt, globalRebaseOffset)
                                }

                                let audioDts = mks_packet_get_dts(audioPkt)

                                // Write audio packet
                                ret = av_interleaved_write_frame(outCtx, audioPkt)
                                if ret < 0 {
                                    TransmuxLog.remux("Buffered audio write_frame ERROR (\(ret)) dts=\(audioDts)", level: .error)
                                } else if audioDts != AV_NOPTS {
                                    if let prevDts = lastWrittenDts[audioOutIdx], audioDts <= prevDts {
                                        let dtsDelta = audioDts - prevDts
                                        TransmuxLog.remux("NON-MONOTONIC DTS AUDIO: prev=\(prevDts) curr=\(audioDts) delta=\(dtsDelta)", level: .error)

                                        // Recovery for severe desync
                                        if dtsDelta < -2000 {
                                            let correctedDts = prevDts + 1
                                            TransmuxLog.remux("RECOVERING: forcing DTS=\(correctedDts)", level: .warn)
                                            mks_packet_adjust_ts(audioPkt, correctedDts - audioDts)
                                        }
                                    }
                                    lastWrittenDts[audioOutIdx] = mks_packet_get_dts(audioPkt)
                                }
                                packetCount += 1
                                freePacketFromBuffer(audioPkt)
                            }
                            pendingAudioPackets.removeAll()
                            TransmuxLog.remux("Buffered audio processing complete")
                        }

                        // Current packet (4th+ keyframe) needs to continue processing normally
                        // Fall through to normal packet write below
                    }
                }
            }

            // Apply global rebase offset to ALL streams (preserves A/V sync)
            if globalRebaseOffset != 0 {
                mks_packet_adjust_ts(pkt, globalRebaseOffset)
            }

            let rescaledDts = mks_packet_get_dts(pkt)
            let rescaledPts = mks_packet_get_pts(pkt)

            // Log first few packets after each seek for debugging A/V sync
            if totalSeekCount > 0 && packetCount < 10 {
                let streamLabel = isVideo ? "VIDEO" : "AUDIO"
                let kf = isVideo ? (mks_packet_is_keyframe(pkt) != 0 ? " KF" : "") : ""
                TransmuxLog.remux(
                    "POST-SEEK pkt[\(packetCount)] \(streamLabel)\(kf): rawDts=\(rawDtsBefore) rescaledPre=\(rescaledDtsBeforeRebase)/\(rescaledPtsBeforeRebase) final=\(rescaledDts)/\(rescaledPts) globalOffset=\(globalRebaseOffset)"
                )
            }

            ret = av_interleaved_write_frame(outCtx, pkt)
            if ret < 0 {
                TransmuxLog.remux("write_frame ERROR (\(ret)) at packet \(packetCount), stream=\(outStreamIdx) dts=\(rescaledDts)", level: .error)
            } else if rescaledDts != AV_NOPTS {
                // Detect non-monotonic DTS (critical for A/V sync)
                if let prevDts = lastWrittenDts[outStreamIdx], rescaledDts <= prevDts {
                    let streamLabel = isVideo ? "VIDEO" : "AUDIO"
                    let dtsDelta = rescaledDts - prevDts
                    TransmuxLog.remux("NON-MONOTONIC DTS \(streamLabel) stream[\(outStreamIdx)]: prev=\(prevDts) curr=\(rescaledDts) delta=\(dtsDelta)", level: .error)

                    // Recovery for severe desync (>2 seconds backward) on audio only
                    // Video non-monotonic DTS is a critical error - don't try to recover
                    if !isVideo && dtsDelta < -2000 {
                        let correctedDts = prevDts + 1
                        TransmuxLog.remux("RECOVERING: forcing monotonic DTS=\(correctedDts) (was \(rescaledDts))", level: .warn)
                        mks_packet_adjust_ts(pkt, correctedDts - rescaledDts)
                    }
                }
                lastWrittenDts[outStreamIdx] = mks_packet_get_dts(pkt)  // Use potentially corrected DTS
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

            if packetCount / 1000 > lastProgressLog {
                lastProgressLog = packetCount / 1000
                let currentSize = Self.fileSize(at: mp4Path)
                let dtsState = lastWrittenDts.sorted(by: { $0.key < $1.key }).map { "s\($0.key)=\($0.value)" }.joined(separator: " ")
                TransmuxLog.remux("Progress: \(packetCount) packets, \(currentSize / 1_048_576) MB, seeks=\(totalSeekCount), dts=[\(dtsState)]")
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
}
