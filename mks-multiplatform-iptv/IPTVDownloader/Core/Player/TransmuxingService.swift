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
}

// MARK: - Active Transmux Handle

/// Thread-safe cancellation handle for an in-progress transmux.
private class ActiveTransmux {
    private let lock = NSLock()
    private var _cancelled = false
    var segmenter: HLSSegmenter?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
        segmenter?.stop()
    }
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

        // Create HLS segmenter to generate byte-range m3u8 from the growing fMP4
        let playlistPath = outputDir.appendingPathComponent("stream.m3u8").path
        let segmenter = HLSSegmenter(
            fmp4Path: mp4Path,
            playlistPath: playlistPath,
            initSegmentSize: headerFileSize
        )
        segmenter.start()
        handle.segmenter = segmenter

        print("[TransmuxingService] HLS segmenter started, resuming caller for progressive playback")

        // Resume the continuation: caller gets the session and can start AVPlayer
        let session = ProgressiveTransmuxSession(
            sessionID: sessionID,
            outputPath: mp4Path,
            playlistPath: playlistPath,
            expectedSize: expectedSize,
            duration: durationSeconds
        )
        continuation.resume(returning: session)
        continuationResumed = true

        // --- Phase 2: Remux loop (continues on this background thread) ---
        print("[TransmuxingService] Starting remux loop...")
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        var packetCount = 0
        var lastProgressLog = 0

        while !handle.isCancelled {
            ret = av_read_frame(inCtx, packet)
            if ret < 0 {
                print("[TransmuxingService] av_read_frame ended: ret=\(ret) (EOF or error)")
                break
            }

            guard let pkt = packet else {
                print("[TransmuxingService] Warning: packet became nil, ending remux loop")
                break
            }
            let streamIndex = Int(pkt.pointee.stream_index)
            guard streamIndex < streamCount, streamMapping[streamIndex] >= 0 else {
                av_packet_unref(pkt)
                continue
            }

            let outStreamIdx = Int32(streamMapping[streamIndex])

            // Filter AAC audio packets through aac_adtstoasc BSF BEFORE rescaling.
            // The BSF expects packets in the input stream's time_base.
            if let bsf = aacBsfCtx, Int32(streamIndex) == audioInputStreamIndex {
                let bsfRet = mks_bsf_filter_packet(bsf, pkt)
                if bsfRet < 0 {
                    av_packet_unref(pkt)
                    packetCount += 1
                    continue
                }
            }

            pkt.pointee.stream_index = outStreamIdx
            mks_packet_rescale_ts(pkt, inCtx, Int32(streamIndex), outCtx, outStreamIdx)
            mks_packet_clear_pos(pkt)

            ret = av_interleaved_write_frame(outCtx, pkt)
            if ret < 0 {
                print("[TransmuxingService] Warning: write_frame error (\(ret)) at packet \(packetCount)")
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
                print("[TransmuxingService] Progress: \(packetCount) packets, \(currentSize / 1_048_576) MB on disk")
            }
        }

        av_packet_free(&packet)

        // --- Cleanup BSF ---
        if aacBsfCtx != nil {
            mks_bsf_free(aacBsfCtx)
            aacBsfCtx = nil
        }

        // --- Finalize ---
        if handle.isCancelled {
            print("[TransmuxingService] Transmux cancelled for session \(sessionID) after \(packetCount) packets")
        } else {
            print("[TransmuxingService] Writing trailer...")
            av_write_trailer(outCtx)
            print("[TransmuxingService] Transmux complete for session \(sessionID), \(packetCount) packets written")
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

        // Self-cleanup: remove temp files now that the loop has exited
        // and all FFmpeg contexts are freed. This is safe because nothing
        // is reading/writing the output file anymore.
        Task {
            await TransmuxingService.shared.cleanup(sessionID: sessionID)
        }
    }

    /// Quick file size check for logging.
    private static func fileSize(at path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    #endif
}
