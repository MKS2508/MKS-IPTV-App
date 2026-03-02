import Foundation

#if canImport(Libavformat)
import Libavformat
import Libavcodec
import Libavutil
#endif

// MARK: - Transmux Error

/// Errors that can occur during transmuxing operations
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

// MARK: - Progressive Transmux Session

/// Result returned immediately after the fMP4 header is written.
/// Playback can begin while the remux loop continues in the background.
struct ProgressiveTransmuxSession {
    let sessionID: String
    let outputPath: String
    let playlistPath: String
    let expectedSize: Int64
    let duration: Double
    let segmenter: HLSSegmenter
    let initSegmentSize: Int64
    let seekHandle: ActiveTransmux
}

// MARK: - Active Transmux Handle

/// Thread-safe cancellation and seek handle for an in-progress transmux.
/// The seek signal allows TransmuxServer to redirect the sequential transmux
/// to a new input position without creating a separate FFmpeg output context.
class ActiveTransmux {
    private let lock = NSLock()
    private var _cancelled = false
    private var _seekRequest: Double? = nil
    private var _lastSeekTarget: Double?
    var segmenter: HLSSegmenter?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    /// The most recent seek target time (source seconds).
    /// Used by TransmuxServer to decide whether to wait for sequential data
    /// instead of triggering a new seek for nearby segments.
    var lastSeekTarget: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSeekTarget
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
        segmenter?.stop()
    }

    /// Request the remux loop to seek the INPUT to a new time (non-blocking).
    /// The output context stays the same, so all moof+mdat remain compatible.
    func requestSeek(to timeSeconds: Double) {
        lock.lock()
        _seekRequest = timeSeconds
        _lastSeekTarget = timeSeconds
        lock.unlock()
        print("[ActiveTransmux] Seek requested to \(String(format: "%.1f", timeSeconds))s")
    }

    /// Consume a pending seek request (called by the remux loop).
    /// Returns the requested time in seconds, or nil if no seek is pending.
    func consumeSeekRequest() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let req = _seekRequest else { return nil }
        _seekRequest = nil
        return req
    }
}

// MARK: - Transmux Completion Notification

extension Notification.Name {
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
actor TransmuxingService {
    static let shared = TransmuxingService()

    private var activeSessions: [String: URL] = [:]
    private var activeTransmuxes: [String: ActiveTransmux] = [:]

    private init() {
        #if canImport(Libavformat)
        // av_register_all() is no longer needed in FFmpeg 4+; formats are auto-registered.
        #endif
    }

    // MARK: - Public API

    /// Start transmuxing and return immediately after the fMP4 header is written.
    /// The remux loop continues in the background. Use `cancelTransmux(sessionID:)`
    /// to stop it early.
    func startTransmux(from sourceURL: URL) async throws -> ProgressiveTransmuxSession {
        #if canImport(Libavformat)
        let sessionID = UUID().uuidString
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mks-iptv-transmux-\(sessionID)")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        activeSessions[sessionID] = outputDir

        let handle = ActiveTransmux()
        activeTransmuxes[sessionID] = handle

        // FFmpeg's bundled build lacks HTTPS protocol support.
        // Route HTTPS URLs through StreamProxy (URLSession -> http://localhost)
        var proxySessionID: Int?
        let inputPath: String
        if sourceURL.scheme?.lowercased() == "https" {
            let proxySession = try await StreamProxy.shared.startProxy(for: sourceURL)
            proxySessionID = proxySession.id
            inputPath = proxySession.localURL.absoluteString
            print("[TransmuxingService] Proxied HTTPS -> \(inputPath)")
        } else {
            inputPath = sourceURL.absoluteString
        }

        print("[TransmuxingService] Starting progressive transmux session \(sessionID)")
        print("[TransmuxingService] Input: \(inputPath)")
        print("[TransmuxingService] Output dir: \(outputDir.path)")

        do {
            let session = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProgressiveTransmuxSession, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.performProgressiveTransmux(
                        inputPath: inputPath,
                        outputDir: outputDir,
                        sessionID: sessionID,
                        handle: handle,
                        proxySessionID: proxySessionID,
                        continuation: continuation
                    )
                }
            }
            return session
        } catch {
            // Stop proxy on failure
            if let pid = proxySessionID {
                await StreamProxy.shared.stop(sessionID: pid)
            }
            activeTransmuxes.removeValue(forKey: sessionID)
            throw error
        }
        #else
        throw TransmuxError.notAvailableOnPlatform
        #endif
    }

    /// Cancel an active transmux session.
    func cancelTransmux(sessionID: String) {
        guard let handle = activeTransmuxes[sessionID] else { return }
        handle.cancel()
        print("[TransmuxingService] Cancellation requested for session \(sessionID)")
    }

    /// Clean up a specific transmux session's temp files.
    func cleanup(sessionID: String) {
        activeTransmuxes.removeValue(forKey: sessionID)
        guard let dir = activeSessions.removeValue(forKey: sessionID) else { return }
        try? FileManager.default.removeItem(at: dir)
        print("[TransmuxingService] Cleaned up session \(sessionID)")
    }

    /// Clean up all transmux sessions.
    func cleanupAll() {
        for handle in activeTransmuxes.values {
            handle.cancel()
        }
        activeTransmuxes.removeAll()
        for (id, dir) in activeSessions {
            try? FileManager.default.removeItem(at: dir)
            print("[TransmuxingService] Cleaned up session \(id)")
        }
        activeSessions.removeAll()
    }

    // MARK: - FFmpeg C API Core (Progressive)

    #if canImport(Libavformat)

    /// Two-phase transmux: resumes the continuation after the header is written,
    /// then continues the remux loop on the same background thread.
    private static func performProgressiveTransmux(
        inputPath: String,
        outputDir: URL,
        sessionID: String,
        handle: ActiveTransmux,
        proxySessionID: Int?,
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
        print("[TransmuxingService] avformat_open_input OK, nb_streams=\(streamCount)")

        ret = avformat_find_stream_info(inCtx, nil)
        guard ret >= 0 else {
            print("[TransmuxingService] avformat_find_stream_info FAILED: \(ret)")
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
        print("[TransmuxingService] Duration: \(String(format: "%.1f", durationSeconds))s, bitrate: \(bitrate)bps, expectedSize: \(expectedSize)")

        // Use av_find_best_stream for stream selection
        let bestVideo = av_find_best_stream(inCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        let bestAudio = av_find_best_stream(inCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        print("[TransmuxingService] Best streams: video=\(bestVideo) audio=\(bestAudio)")

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

            print("[TransmuxingService] Mapped \(label) stream[\(streamIdx)] -> output[\(outputStreamIndex - 1)]")
        }

        guard outputStreamIndex > 0 else {
            print("[TransmuxingService] No video or audio streams found")
            avformat_close_input(&inputCtx)
            avformat_free_context(outCtx)
            continuation.resume(throwing: TransmuxError.processFailure(status: -1))
            return
        }
        print("[TransmuxingService] Mapped \(outputStreamIndex) output stream(s)")

        // Set the overall container duration for seeking support during progressive transmux.
        // This allows AVPlayer to know the duration immediately, enabling seeking.
        // Note: We set container duration only - stream durations will be derived from it.
        if durationSeconds > 0 && durationSeconds.isFinite {
            let containerDuration = Int64(durationSeconds * Double(AV_TIME_BASE))
            outCtx.pointee.duration = containerDuration
            print("[TransmuxingService] Set container duration: \(containerDuration) (\(durationSeconds)s)")
        }

        // --- Create aac_adtstoasc BSF for AAC audio from MPEG-TS ---
        // MPEG-TS wraps AAC in ADTS format. The MP4 muxer requires raw AAC (ASC).
        // The aac_adtstoasc BSF strips ADTS headers, fixing "Malformed AAC bitstream".
        var aacBsfCtx: UnsafeMutableRawPointer?
        let audioInputStreamIndex: Int32 = bestAudio  // -1 if no audio
        if bestAudio >= 0 {
            let audioCodecId = mks_stream_get_codec_id(inCtx, bestAudio)
            // AV_CODEC_ID_AAC = 86018
            if audioCodecId == 86018 {
                aacBsfCtx = mks_bsf_create_aac_adtstoasc(inCtx, bestAudio)
                if aacBsfCtx != nil {
                    print("[TransmuxingService] aac_adtstoasc BSF enabled for audio stream \(bestAudio)")
                } else {
                    print("[TransmuxingService] WARNING: Failed to create aac_adtstoasc BSF, audio may fail")
                }
            }
        }

        // --- Set fragmented MP4 muxer options ---
        // Must use empty_moov for progressive streaming - allows writing header before
        // knowing final sample positions. Without it, FFmpeg can't write a valid moov.
        var options: OpaquePointer?
        av_dict_set(&options, "movflags", "frag_keyframe+empty_moov+default_base_moof", 0)

        // --- Open output file ---
        print("[TransmuxingService] Opening output: \(mp4Path)")
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
        print("[TransmuxingService] Calling avformat_write_header...")
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
        avio_flush(outCtx.pointee.pb)

        let headerFileSize = Self.fileSize(at: mp4Path)
        print("[TransmuxingService] Header written and flushed to disk (\(headerFileSize) bytes on disk)")

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

        print("[TransmuxingService] HLS segmenter started with VOD playlist, resuming caller for progressive playback")

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

        // --- Timestamp rebasing state ---
        // After each seek, an offset is added to all packet DTS/PTS to maintain
        // monotonically increasing output timestamps.
        var dtsRebaseOffset: [Int32: Int64] = [:]
        var lastWrittenDts: [Int32: Int64] = [:]
        let AV_NOPTS = Int64(bitPattern: UInt64(0x8000000000000000))

        // After a seek: skip packets until first video keyframe, then compute rebase offsets.
        var seekPending = false
        var videoKeyframeReceived = false
        var streamsNeedingRebase: Set<Int32> = []
        var skippedPacketsAfterSeek = 0

        // Map output stream index to whether it's the video stream
        let videoOutputIdx: Int32 = bestVideo >= 0 ? Int32(streamMapping[Int(bestVideo)]) : -1

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
                totalSeekCount += 1
                let preSeekDts = lastWrittenDts.map { "stream\($0.key)=\($0.value)" }.joined(separator: ", ")
                TransmuxLog.remux("===== SEEK #\(totalSeekCount) to \(String(format: "%.1f", seekTime))s =====")
                TransmuxLog.remux("Pre-seek state: packetCount=\(packetCount) lastWrittenDts=[\(preSeekDts)]")
                TransmuxLog.remux("Pre-seek rebaseOffsets=\(dtsRebaseOffset)")

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

                // 5. Set seek-pending: skip until video keyframe, then compute rebase offsets
                seekPending = true
                videoKeyframeReceived = false
                skippedPacketsAfterSeek = 0
                streamsNeedingRebase = Set(lastWrittenDts.keys)
                // Also include streams that haven't had any packets yet
                for i in 0..<Int(outputStreamIndex) {
                    streamsNeedingRebase.insert(Int32(i))
                }

                // 6. Notify segmenter with source time for virtual-to-real mapping
                segmenter.notifySeekDiscontinuity(seekTargetTime: seekTime)

                packetCount = 0  // reset for aggressive flushing after seek
                TransmuxLog.remux("Seek #\(totalSeekCount) prepared: awaiting keyframe, rebase for \(streamsNeedingRebase.sorted()) streams")
                continue
            }

            // Safety valve: if seekPending for too many packets, force-clear to prevent lockout.
            // This can happen if a stream has no packets after seek (e.g., video-only source).
            if seekPending && packetCount > 500 {
                TransmuxLog.remux("WARNING: force-clearing seekPending after \(packetCount) packets (streams still pending: \(streamsNeedingRebase.sorted()))", level: .warn)
                seekPending = false
                streamsNeedingRebase.removeAll()
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

            // --- Keyframe skipping after seek ---
            // Skip all packets until the first video keyframe arrives.
            // Also skip audio before video keyframe to prevent A/V desync.
            if seekPending && !videoKeyframeReceived {
                skippedPacketsAfterSeek += 1
                if outStreamIdx == videoOutputIdx {
                    if mks_packet_is_keyframe(pkt) == 0 {
                        av_packet_unref(pkt)
                        packetCount += 1
                        continue
                    }
                    videoKeyframeReceived = true
                    TransmuxLog.remux("First video KEYFRAME after seek #\(totalSeekCount) at packet \(packetCount), skipped \(skippedPacketsAfterSeek) packets, rawDts=\(rawDtsBefore) rawPts=\(rawPtsBefore)")
                } else {
                    // Skip audio until video keyframe is received
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

            // --- Timestamp rebasing after seek ---
            // Compute rebase offset on first packet per stream after seek.
            if streamsNeedingRebase.contains(outStreamIdx) {
                let newDts = mks_packet_get_dts(pkt)
                if newDts != AV_NOPTS {
                    let streamLabel = isVideo ? "VIDEO" : "AUDIO"
                    if let lastDts = lastWrittenDts[outStreamIdx] {
                        // Make this packet continue monotonically after the last written DTS
                        let offset = lastDts + 1 - newDts
                        dtsRebaseOffset[outStreamIdx] = offset
                        TransmuxLog.remux("REBASE \(streamLabel) stream[\(outStreamIdx)]: lastWrittenDts=\(lastDts) newDts=\(newDts) offset=\(offset) (gap=\(newDts - lastDts))")
                    } else {
                        // First packet ever for this stream — no rebase needed
                        dtsRebaseOffset[outStreamIdx] = 0
                        TransmuxLog.remux("REBASE \(streamLabel) stream[\(outStreamIdx)]: first packet ever, no rebase (dts=\(newDts))")
                    }
                    streamsNeedingRebase.remove(outStreamIdx)
                    if streamsNeedingRebase.isEmpty {
                        seekPending = false
                        TransmuxLog.remux("All streams rebased after seek #\(totalSeekCount), seek handling COMPLETE. offsets=\(dtsRebaseOffset)")
                    } else {
                        TransmuxLog.remux("Still waiting for rebase on streams: \(streamsNeedingRebase.sorted())")
                    }
                }
            }

            // Apply rebase offset (persists for all packets after a seek)
            if let offset = dtsRebaseOffset[outStreamIdx], offset != 0 {
                mks_packet_adjust_ts(pkt, offset)
            }

            let rescaledDts = mks_packet_get_dts(pkt)
            let rescaledPts = mks_packet_get_pts(pkt)

            // Log first few packets after each seek for debugging A/V sync
            if totalSeekCount > 0 && packetCount < 10 {
                let streamLabel = isVideo ? "VIDEO" : "AUDIO"
                let kf = isVideo ? (mks_packet_is_keyframe(pkt) != 0 ? " KF" : "") : ""
                TransmuxLog.remux(
                    "POST-SEEK pkt[\(packetCount)] \(streamLabel)\(kf): rawDts=\(rawDtsBefore) rescaledPre=\(rescaledDtsBeforeRebase)/\(rescaledPtsBeforeRebase) final=\(rescaledDts)/\(rescaledPts) offset=\(dtsRebaseOffset[outStreamIdx] ?? 0)"
                )
            }

            ret = av_interleaved_write_frame(outCtx, pkt)
            if ret < 0 {
                TransmuxLog.remux("write_frame ERROR (\(ret)) at packet \(packetCount), stream=\(outStreamIdx) dts=\(rescaledDts)", level: .error)
            } else if rescaledDts != AV_NOPTS {
                // Detect non-monotonic DTS (critical for A/V sync)
                if let prevDts = lastWrittenDts[outStreamIdx], rescaledDts <= prevDts {
                    let streamLabel = isVideo ? "VIDEO" : "AUDIO"
                    TransmuxLog.remux("NON-MONOTONIC DTS \(streamLabel) stream[\(outStreamIdx)]: prev=\(prevDts) curr=\(rescaledDts) delta=\(rescaledDts - prevDts)", level: .error)
                }
                lastWrittenDts[outStreamIdx] = rescaledDts
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
        if let pid = proxySessionID {
            Task {
                await StreamProxy.shared.stop(sessionID: pid)
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

    #endif
}
