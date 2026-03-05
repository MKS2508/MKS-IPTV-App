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

// MARK: - Track Info

/// Metadata for an audio track mapped to the output fMP4.
public struct AudioTrackInfo: Sendable {
    public let inputStreamIndex: Int
    public let outputStreamIndex: Int
    public let language: String
    public let title: String
    public let codecName: String  // "AAC", "EAC3", "AC3", "OPUS", etc.
    public let codecId: Int32
    public let channels: Int
    public let sampleRate: Int
    public let isDefault: Bool
}

/// Metadata for a subtitle track extracted to WebVTT.
public struct SubtitleTrackInfo: Sendable {
    public let language: String
    public let title: String
    public let vttFileName: String
    public let isForced: Bool
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
    public let audioTracks: [AudioTrackInfo]
    public let subtitleTracks: [SubtitleTrackInfo]
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

        // Startup logging deferred until after stream info is parsed (consolidated below)

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
        // Use av_find_best_stream for video selection
        let bestVideo = av_find_best_stream(inCtx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        let bestAudio = av_find_best_stream(inCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)

        // Consolidated startup line 1: SESSION
        let brMbps = String(format: "%.1f", Double(bitrate) / 1_000_000)
        let estGB = String(format: "%.1f", Double(expectedSize) / 1_073_741_824)
        TransmuxLog.service("SESSION \(sessionID.prefix(8)) | in=\(inputPath) dur=\(String(format: "%.1f", durationSeconds))s br=\(brMbps)Mbps est=\(estGB)GB")

        // --- Enumerate ALL audio streams ---
        struct AudioStreamEntry {
            let inputIdx: Int32
            let language: String
            let title: String
            let codecId: Int32
            let channels: Int
            let sampleRate: Int
        }

        var audioStreams: [AudioStreamEntry] = []
        for i in 0..<Int32(streamCount) {
            let codecType = mks_stream_get_codec_type(inCtx, i)
            guard codecType == 1 else { continue }  // AVMEDIA_TYPE_AUDIO = 1

            var langBuf = [CChar](repeating: 0, count: 64)
            var titleBuf = [CChar](repeating: 0, count: 256)
            mks_stream_get_language(inCtx, i, &langBuf, 64)
            mks_stream_get_title(inCtx, i, &titleBuf, 256)

            let lang = String(cString: langBuf)
            let title = String(cString: titleBuf)

            audioStreams.append(AudioStreamEntry(
                inputIdx: i,
                language: lang.isEmpty ? "und" : lang,
                title: title,
                codecId: Int32(mks_stream_get_codec_id(inCtx, i)),
                channels: Int(mks_stream_get_channels(inCtx, i)),
                sampleRate: Int(mks_stream_get_sample_rate(inCtx, i))
            ))
        }

        // Sort: put bestAudio first (default), rest alphabetically by language
        audioStreams.sort { a, b in
            if a.inputIdx == bestAudio { return true }
            if b.inputIdx == bestAudio { return false }
            return a.language < b.language
        }

        // --- Enumerate subtitle streams ---
        struct SubtitleStreamEntry {
            let inputIdx: Int32
            let language: String
            let title: String
            let codecId: Int32
            let isForced: Bool
        }

        var subtitleStreams: [SubtitleStreamEntry] = []
        for i in 0..<Int32(streamCount) {
            let codecType = mks_stream_get_codec_type(inCtx, i)
            guard codecType == 3 else { continue }  // AVMEDIA_TYPE_SUBTITLE = 3

            let codecId = Int32(mks_stream_get_codec_id(inCtx, i))
            // Text subtitle codec IDs (from libavcodec/codec_id.h, base 0x17000 = 94208):
            //   TEXT=94210, SSA=94212, MOV_TEXT=94213, SRT=94216,
            //   SUBRIP=94225, WEBVTT=94226, ASS=94230
            // Bitmap (skip): DVD_SUBTITLE=94208, DVB_SUBTITLE=94209,
            //   XSUB=94211, HDMV_PGS=94214, DVB_TELETEXT=94215
            let textSubtitleCodecIds: Set<Int32> = [
                94210,  // AV_CODEC_ID_TEXT
                94212,  // AV_CODEC_ID_SSA
                94213,  // AV_CODEC_ID_MOV_TEXT
                94216,  // AV_CODEC_ID_SRT
                94225,  // AV_CODEC_ID_SUBRIP
                94226,  // AV_CODEC_ID_WEBVTT
                94230,  // AV_CODEC_ID_ASS
            ]
            guard textSubtitleCodecIds.contains(codecId) else {
                TransmuxLog.service("Skipping non-text subtitle stream \(i) (codecId=\(codecId))", level: .warn)
                continue
            }

            var langBuf = [CChar](repeating: 0, count: 64)
            var titleBuf = [CChar](repeating: 0, count: 256)
            mks_stream_get_language(inCtx, i, &langBuf, 64)
            mks_stream_get_title(inCtx, i, &titleBuf, 256)

            let lang = String(cString: langBuf)
            let title = String(cString: titleBuf)
            let disposition = mks_stream_get_disposition(inCtx, i)
            let isForced = (disposition & 0x40) != 0  // AV_DISPOSITION_FORCED

            subtitleStreams.append(SubtitleStreamEntry(
                inputIdx: i,
                language: lang.isEmpty ? "und" : lang,
                title: title,
                codecId: codecId,
                isForced: isForced
            ))
        }

        // --- Prepare subtitle track info (collector extracts during remux loop) ---
        // IPTV servers block concurrent connections, so we can't open a second
        // connection for subtitle extraction. Instead, we create a collector that
        // gets fed subtitle packets during the main av_read_frame loop.
        var subtitleTrackInfos: [SubtitleTrackInfo] = []
        let subtitleVttFileNames: [String] = subtitleStreams.enumerated().map { (idx, sub) in
            "sub_\(sub.language)_\(idx).vtt"
        }
        var subtitleCollector: OpaquePointer? = nil

        if !subtitleStreams.isEmpty {
            // Pre-populate SubtitleTrackInfo for the master playlist
            // (VTT files will grow during remux as subtitle packets arrive)
            for (idx, sub) in subtitleStreams.enumerated() {
                subtitleTrackInfos.append(SubtitleTrackInfo(
                    language: sub.language,
                    title: sub.title.isEmpty ? sub.language.uppercased() : sub.title,
                    vttFileName: subtitleVttFileNames[idx],
                    isForced: sub.isForced
                ))
            }

            // Create collector — sets up decoders + opens VTT output files
            let cStreamIndices = subtitleStreams.map { Int32($0.inputIdx) }
            let vttPaths = subtitleVttFileNames.map { outputDir.appendingPathComponent($0).path }

            var cPaths = vttPaths.map { $0.withCString { strdup($0)! } }
            defer { cPaths.forEach { free($0) } }

            cPaths.withUnsafeMutableBufferPointer { cPathsBuf in
                let cPathsRaw = UnsafePointer(cPathsBuf.baseAddress!)
                cPathsRaw.withMemoryRebound(to: UnsafePointer<CChar>.self, capacity: subtitleStreams.count) { pathsPtr in
                    cStreamIndices.withUnsafeBufferPointer { idxBuf in
                        subtitleCollector = mks_subtitle_collector_create(
                            inCtx,
                            Int32(subtitleStreams.count),
                            idxBuf.baseAddress!,
                            pathsPtr
                        )
                    }
                }
            }

            if subtitleCollector != nil {
                TransmuxLog.service("Subtitle collector created for \(subtitleStreams.count) streams")
            } else {
                TransmuxLog.service("Failed to create subtitle collector", level: .warn)
                subtitleTrackInfos.removeAll()
            }
        }

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

        // Map video stream
        if bestVideo >= 0 {
            streamMapping[Int(bestVideo)] = Int(outputStreamIndex)
            outputStreamIndex += 1

            guard let outStream = avformat_new_stream(outCtx, nil) else {
                avformat_close_input(&inputCtx)
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: -1))
                return
            }
            ret = mks_stream_copy_codecpar(outStream, inCtx, bestVideo)
            guard ret >= 0 else {
                avformat_close_input(&inputCtx)
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
                return
            }
        }

        // Map ALL audio streams (each gets its own output track)
        var audioTrackInfos: [AudioTrackInfo] = []
        for (idx, audio) in audioStreams.enumerated() {
            streamMapping[Int(audio.inputIdx)] = Int(outputStreamIndex)

            guard let outStream = avformat_new_stream(outCtx, nil) else {
                avformat_close_input(&inputCtx)
                if outCtx.pointee.pb != nil { avio_close(outCtx.pointee.pb) }
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: -1))
                return
            }

            ret = mks_stream_copy_codecpar(outStream, inCtx, audio.inputIdx)
            guard ret >= 0 else {
                avformat_close_input(&inputCtx)
                if outCtx.pointee.pb != nil { avio_close(outCtx.pointee.pb) }
                avformat_free_context(outCtx)
                continuation.resume(throwing: TransmuxError.processFailure(status: Int(ret)))
                return
            }

            let codecName: String
            switch audio.codecId {
            case 86018: codecName = "AAC"
            case 86019: codecName = "AC3"
            case 86056: codecName = "EAC3"
            case 86076: codecName = "OPUS"
            case 86028: codecName = "FLAC"
            case 86017: codecName = "MP3"
            default: codecName = "audio(\(audio.codecId))"
            }

            audioTrackInfos.append(AudioTrackInfo(
                inputStreamIndex: Int(audio.inputIdx),
                outputStreamIndex: Int(outputStreamIndex),
                language: audio.language,
                title: audio.title,
                codecName: codecName,
                codecId: audio.codecId,
                channels: audio.channels,
                sampleRate: audio.sampleRate,
                isDefault: idx == 0
            ))

            outputStreamIndex += 1
        }

        guard outputStreamIndex > 0 else {
            TransmuxLog.service("No video or audio streams found", level: .error)
            avformat_close_input(&inputCtx)
            avformat_free_context(outCtx)
            continuation.resume(throwing: TransmuxError.processFailure(status: -1))
            return
        }

        // Set the overall container duration for seeking support during progressive transmux.
        if durationSeconds > 0 && durationSeconds.isFinite {
            let containerDuration = Int64(durationSeconds * Double(AV_TIME_BASE))
            outCtx.pointee.duration = containerDuration
        }

        // --- Create aac_adtstoasc BSF for each AAC audio stream ---
        // MPEG-TS wraps AAC in ADTS format. The MP4 muxer requires raw AAC (ASC).
        var aacBsfContexts: [Int32: UnsafeMutableRawPointer] = [:]  // inputStreamIdx → BSF
        var hasAC3Audio = false

        for audio in audioStreams {
            if audio.codecId == 86018 {  // AAC
                if let bsf = mks_bsf_create_aac_adtstoasc(inCtx, audio.inputIdx) {
                    aacBsfContexts[audio.inputIdx] = bsf
                } else {
                    TransmuxLog.service("WARNING: Failed to create aac_adtstoasc BSF for stream \(audio.inputIdx)", level: .warn)
                }
            } else if audio.codecId == 86019 || audio.codecId == 86056 {
                hasAC3Audio = true
            }
        }

        // For AC3/EAC3: set frame_size=1536 on ALL such output streams.
        // AC3 frames are always 1536 samples. For pure AC3, this eliminates delay_moov.
        // For EAC3, delay_moov is still required but frame_size ensures trex gets
        // default_sample_duration=1536 (AVPlayer needs this for CMTimebase).
        var hasEAC3 = false
        for audio in audioStreams {
            let outIdx = Int32(streamMapping[Int(audio.inputIdx)])
            if audio.codecId == 86019 {
                // Pure AC3
                mks_stream_set_frame_size(outCtx, outIdx, 1536)
            } else if audio.codecId == 86056 {
                // EAC3
                mks_stream_set_frame_size(outCtx, outIdx, 1536)
                hasEAC3 = true
            }
        }
        // Only need delay_moov if there's EAC3 (pure AC3 with frame_size doesn't need it)
        hasAC3Audio = hasEAC3

        // --- Set fragmented MP4 muxer options ---
        var options: OpaquePointer?
        let movflags = hasAC3Audio
            ? "frag_keyframe+empty_moov+delay_moov+default_base_moof"
            : "frag_keyframe+empty_moov+default_base_moof"
        av_dict_set(&options, "movflags", movflags, 0)

        // Consolidated startup line 2: STREAMS
        let vMap = bestVideo >= 0 ? "\(bestVideo)\u{2192}\(streamMapping[Int(bestVideo)])" : "none"
        let audioMaps = audioStreams.map { a in
            let outIdx = streamMapping[Int(a.inputIdx)]
            let codecName = audioTrackInfos.first(where: { $0.inputStreamIndex == Int(a.inputIdx) })?.codecName ?? "?"
            return "\(a.inputIdx)\u{2192}\(outIdx)(\(codecName)/\(a.language))"
        }.joined(separator: " a:")
        let aMap = audioStreams.isEmpty ? "none" : audioMaps
        let subInfo = subtitleTrackInfos.isEmpty ? "" : " subs=\(subtitleTrackInfos.count)"
        TransmuxLog.service("STREAMS nb=\(streamCount) v:\(vMap) a:\(aMap)\(subInfo) | flags=\(movflags)")

        // --- Open output file ---
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
        // Consolidated startup line 3: INIT
        TransmuxLog.service("INIT moov=\(headerFileSize)B out=\(mp4Path)")

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
        // When subtitles exist, create a master playlist structure
        let playlistDir = outputDir
        let mediaPlaylistPath = playlistDir.appendingPathComponent("stream.m3u8").path
        let masterPlaylistPath = subtitleTrackInfos.isEmpty
            ? mediaPlaylistPath
            : playlistDir.appendingPathComponent("master.m3u8").path

        let segmenter = HLSSegmenter(
            fmp4Path: mp4Path,
            playlistPath: mediaPlaylistPath,
            initSegmentSize: headerFileSize,
            duration: durationSeconds,
            subtitleTracks: subtitleTrackInfos
        )
        segmenter.start()
        handle.segmenter = segmenter

        // Write master playlist if subtitles exist
        if !subtitleTrackInfos.isEmpty {
            segmenter.writeMasterPlaylist(to: masterPlaylistPath)
        }

        TransmuxLog.service("HLS segmenter started with VOD playlist, resuming caller for progressive playback")

        // Resume the continuation: caller gets the session and can start AVPlayer.
        // Pass the ActiveTransmux handle so TransmuxServer can request seek-redirects.
        // The entry playlist URL is master.m3u8 when subtitles exist, stream.m3u8 otherwise.
        let session = ProgressiveTransmuxSession(
            sessionID: sessionID,
            outputPath: mp4Path,
            playlistPath: subtitleTrackInfos.isEmpty ? mediaPlaylistPath : masterPlaylistPath,
            expectedSize: expectedSize,
            duration: durationSeconds,
            segmenter: segmenter,
            initSegmentSize: headerFileSize,
            seekHandle: handle,
            audioTracks: audioTrackInfos,
            subtitleTracks: subtitleTrackInfos
        )
        continuation.resume(returning: session)
        continuationResumed = true

        // --- Phase 2: Remux loop (continues on this background thread) ---
        TransmuxLog.remux("Starting remux loop (videoOut=\(bestVideo) audioTracks=\(audioTrackInfos.count) outputStreams=\(outputStreamIndex))")
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        var packetCount = 0
        var lastProgressLog = 0
        var totalSeekCount = 0

        // --- Per-stream timestamp rebasing after seek ---
        var streamRebaseOffsets: [Int32: Int64] = [:]

        // State for computing offsets after seek
        var bufferedVideoKeyframes: [UnsafeMutablePointer<AVPacket>] = []
        var firstNVideoDtsAfterSeek: [Int64] = []
        let videoDtsAveragingCount = 1
        var globalOffsetComputed = false

        var seekPending = false
        var videoKeyframeReceived = false
        var skippedPacketsAfterSeek = 0

        func freePacketFromBuffer(_ ptr: UnsafeMutablePointer<AVPacket>) {
            var mutablePtr: UnsafeMutablePointer<AVPacket>? = ptr
            av_packet_free(&mutablePtr)
        }
        var pendingAudioPackets: [UnsafeMutablePointer<AVPacket>] = []
        let maxPendingAudioPackets = 500

        // Map output stream indices
        let videoOutputIdx: Int32 = bestVideo >= 0 ? Int32(streamMapping[Int(bestVideo)]) : -1
        // Set of all audio output indices (for multi-audio seek rebasing)
        let audioOutputIndices: Set<Int32> = Set(audioTrackInfos.map { Int32($0.outputStreamIndex) })
        // First audio output index (for backward compat with single-audio DTS logging)
        let firstAudioOutputIdx: Int32 = audioTrackInfos.first.map { Int32($0.outputStreamIndex) } ?? -1

        // Seek cooldown: require minimum time between seeks to prevent cascading.
        // Uses adaptive cooldown from ActiveTransmux (starts at 0.8s, adjusts per seek).
        var lastSeekCompletionTime: Date? = nil

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
                // Check adaptive cooldown: prevent rapid seeks that overwhelm timestamp rebasing
                let seekCooldown = handle.cooldownSeconds
                if let lastCompletion = lastSeekCompletionTime {
                    let elapsed = Date().timeIntervalSince(lastCompletion)
                    if elapsed < seekCooldown {
                        TransmuxLog.remux("REJECTING seek, cooldown not met (elapsed=\(String(format: "%.1f", elapsed))s, required=\(String(format: "%.2f", seekCooldown))s)", level: .warn)
                        continue
                    }
                }
                totalSeekCount += 1
                // Consolidated seek line 1: start marker with pre-seek DTS
                var preVSec = "n/a"
                var preASec = "n/a"
                if let vd = lastWrittenDts[videoOutputIdx] {
                    var tbNum: Int32 = 0, tbDen: Int32 = 0
                    mks_stream_get_time_base(outCtx, videoOutputIdx, &tbNum, &tbDen)
                    if tbDen > 0 { preVSec = String(format: "%.3f", Double(vd) / Double(tbDen)) }
                }
                if firstAudioOutputIdx >= 0, let ad = lastWrittenDts[firstAudioOutputIdx] {
                    var tbNum: Int32 = 0, tbDen: Int32 = 0
                    mks_stream_get_time_base(outCtx, firstAudioOutputIdx, &tbNum, &tbDen)
                    if tbDen > 0 { preASec = String(format: "%.3f", Double(ad) / Double(tbDen)) }
                }
                TransmuxLog.remux("SEEK #\(totalSeekCount) \u{2192} \(String(format: "%.1f", seekTime))s | preV=\(preVSec)s preA=\(preASec)s")

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

                // 4. Flush ALL AAC BSF state (partial ADTS frames from before seek)
                for (_, bsf) in aacBsfContexts {
                    mks_bsf_flush(bsf)
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

            // Feed subtitle packets to the collector (before checking streamMapping,
            // since subtitle streams are NOT mapped to the output fMP4)
            if let collector = subtitleCollector {
                mks_subtitle_collector_feed(collector, pkt)
            }

            guard streamIndex < streamCount, streamMapping[streamIndex] >= 0 else {
                av_packet_unref(pkt)
                continue
            }

            let outStreamIdx = Int32(streamMapping[streamIndex])
            let isVideo = outStreamIdx == videoOutputIdx
            let rawDtsBefore = mks_packet_get_dts(pkt)
            let rawPtsBefore = mks_packet_get_pts(pkt)

            // Filter AAC audio packets through per-stream aac_adtstoasc BSF BEFORE rescaling.
            // The BSF expects packets in the input stream's time_base.
            if let bsf = aacBsfContexts[Int32(streamIndex)] {
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
                        mks_stream_get_time_base(outCtx, videoOutputIdx, &vTbNum, &vTbDen)

                        // For multi-audio: get timebase of each audio output stream
                        // We use the first audio stream's timebase for the cross-conversion
                        // with video (all audio streams typically share the same timebase).
                        var aTbDen: Int32 = 0
                        if let firstAudio = audioTrackInfos.first {
                            var aTbNum: Int32 = 0
                            mks_stream_get_time_base(outCtx, Int32(firstAudio.outputStreamIndex), &aTbNum, &aTbDen)
                        }

                        // Compute target output ticks using the same cross-timebase approach.
                        // For multi-audio, use the highest lastWrittenDts among all audio tracks
                        // to compute the target, ensuring all audio streams advance past their max.
                        let lastVTicks = lastWrittenDts[videoOutputIdx] ?? 0
                        var maxLastATicks: Int64 = 0
                        for aIdx in audioOutputIndices {
                            if let aDts = lastWrittenDts[aIdx], aDts != AV_NOPTS {
                                maxLastATicks = max(maxLastATicks, aDts)
                            }
                        }

                        let targetVideoTicks: Int64
                        let targetAudioTicks: Int64
                        if vTbDen > 0 && aTbDen > 0 && lastVTicks != AV_NOPTS && maxLastATicks != AV_NOPTS {
                            let lastAInVTicks = Int64(ceil(Double(maxLastATicks) / Double(aTbDen) * Double(vTbDen)))
                            let lastVInATicks = Int64(ceil(Double(lastVTicks) / Double(vTbDen) * Double(aTbDen)))
                            targetVideoTicks = max(lastVTicks, lastAInVTicks) + 1
                            targetAudioTicks = max(maxLastATicks, lastVInATicks) + 1
                        } else {
                            targetVideoTicks = lastVTicks + 1
                            targetAudioTicks = maxLastATicks + 1
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

                        globalOffsetComputed = true
                        seekPending = false
                        lastSeekCompletionTime = Date()
                        handle.adjustCooldown(seekWasClean: skippedPacketsAfterSeek < 20)
                        // Signal TransmuxServer that post-seek data is being produced
                        handle.signalSeekDataReady()

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

                        // Process buffered audio packets.
                        // TWO-PASS approach to eliminate A/V desync:
                        //
                        // After av_seek_frame, the demuxer outputs ~7 EAC3 audio packets
                        // before/alongside the video keyframe. If we compute the audio offset
                        // from the FIRST buffered packet, all 7 get written, pushing audio's
                        // lastWrittenDts 0.224s ahead of video. This desync persists forever.
                        //
                        // Fix: compute offset from the LAST buffered audio packet so it lands
                        // at targetAudioTicks. Earlier packets get DTS <= lastWrittenDts[audio]
                        // → naturally dropped by the monotonicity guard. Both streams end at
                        // the same output time after seek.
                        if !pendingAudioPackets.isEmpty {
                            // Pass 1: Rescale all buffered audio packets and find per-stream last valid DTS
                            var lastRescaledAudioDtsPerStream: [Int32: Int64] = [:]

                            for audioPkt in pendingAudioPackets {
                                let audioInStreamIdx = Int(audioPkt.pointee.stream_index)
                                guard audioInStreamIdx < streamCount, streamMapping[audioInStreamIdx] >= 0 else {
                                    continue
                                }
                                let audioOutIdx = Int32(streamMapping[audioInStreamIdx])

                                audioPkt.pointee.stream_index = audioOutIdx
                                mks_packet_rescale_ts(audioPkt, inCtx, Int32(audioInStreamIdx), outCtx, audioOutIdx)
                                mks_packet_clear_pos(audioPkt)

                                let dts = mks_packet_get_dts(audioPkt)
                                if dts != AV_NOPTS {
                                    lastRescaledAudioDtsPerStream[audioOutIdx] = dts
                                }
                            }

                            // Compute audio offset per-stream from the LAST packet → lands at targetAudioTicks
                            var audioOffset: Int64 = 0
                            for (audioOutIdx, lastDts) in lastRescaledAudioDtsPerStream {
                                if lastWrittenDts[audioOutIdx] != nil, aTbDen > 0 {
                                    let offset = targetAudioTicks - lastDts
                                    streamRebaseOffsets[audioOutIdx] = offset
                                    if audioOutIdx == firstAudioOutputIdx { audioOffset = offset }
                                } else {
                                    streamRebaseOffsets[audioOutIdx] = 0
                                }
                            }

                            // Pass 2: Apply offset and write (monotonicity guard drops early packets)
                            var audioWritten = 0
                            var audioDropped = 0
                            for audioPkt in pendingAudioPackets {
                                let audioOutIdx = audioPkt.pointee.stream_index

                                let audioOff = streamRebaseOffsets[audioOutIdx] ?? 0
                                if audioOff != 0 {
                                    mks_packet_adjust_ts(audioPkt, audioOff)
                                }

                                let audioTrackDts = mks_packet_get_dts(audioPkt)

                                // Monotonicity guard: drop packets with DTS <= last written
                                if audioTrackDts != AV_NOPTS {
                                    if let prevDts = lastWrittenDts[audioOutIdx], audioTrackDts <= prevDts {
                                        audioDropped += 1
                                        freePacketFromBuffer(audioPkt)
                                        packetCount += 1
                                        continue
                                    }
                                }

                                ret = av_interleaved_write_frame(outCtx, audioPkt)
                                if ret >= 0, audioTrackDts != AV_NOPTS {
                                    lastWrittenDts[audioOutIdx] = audioTrackDts
                                    audioWritten += 1
                                }
                                packetCount += 1
                                freePacketFromBuffer(audioPkt)
                            }
                            let audioBufCount = pendingAudioPackets.count
                            pendingAudioPackets.removeAll()

                            // Consolidated seek line 2: result with offsets + sync diagnostic
                            if videoOutputIdx >= 0 && firstAudioOutputIdx >= 0,
                               let vDts = lastWrittenDts[videoOutputIdx],
                               let aDts = lastWrittenDts[firstAudioOutputIdx],
                               vTbDen > 0, aTbDen > 0 {
                                let vSec = Double(vDts) / Double(vTbDen)
                                let aSec = Double(aDts) / Double(aTbDen)
                                TransmuxLog.remux("SEEK #\(totalSeekCount) OK vOff=\(videoOffset) aOff=\(audioOffset) | sync v=\(String(format: "%.3f", vSec))s a=\(String(format: "%.3f", aSec))s gap=\(String(format: "%.3f", aSec - vSec))s | audio w=\(audioWritten) d=\(audioDropped) buf=\(audioBufCount) tracks=\(lastRescaledAudioDtsPerStream.count)")
                            } else {
                                TransmuxLog.remux("SEEK #\(totalSeekCount) OK vOff=\(videoOffset) aOff=\(audioOffset) | no A/V sync data")
                            }
                        } else {
                            TransmuxLog.remux("SEEK #\(totalSeekCount) OK vOff=\(videoOffset) | no buffered audio")
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

            // BACKPRESSURE: Throttle when production is too far ahead of playback.
            // Check every 100 packets (not every packet — amortize overhead).
            // Never throttle during seeks, early playback, or shortly after a seek.
            if packetCount % 100 == 0 && !seekPending {
                let productionTime = segmenter.latestBufferedSourceTime()
                let consumerTime = handle.currentPlaybackPosition
                let lead = productionTime - consumerTime

                let inEarlyPlayback = consumerTime < 30.0
                let recentSeek = lastSeekCompletionTime.map { Date().timeIntervalSince($0) < 30.0 } ?? false

                if !inEarlyPlayback && !recentSeek && lead > 120.0 {
                    TransmuxLog.remux("THROTTLE pausing (lead=\(Int(lead))s, production=\(String(format: "%.0f", productionTime))s, playback=\(String(format: "%.0f", consumerTime))s)")
                    while !handle.isCancelled && !handle.hasSeekPending {
                        Thread.sleep(forTimeInterval: 0.5)
                        let currentLead = segmenter.latestBufferedSourceTime() - handle.currentPlaybackPosition
                        if currentLead < 60.0 { break }
                    }
                    TransmuxLog.remux("THROTTLE resumed")
                }
            }

            // Check if player layer requested aggressive flushing (e.g., buffer starvation).
            // Resetting packetCount re-activates the ultra-aggressive flush pattern below.
            if handle.aggressiveFlushRequested {
                packetCount = 0
                TransmuxLog.remux("AGGRESSIVE-FLUSH activated, resetting packetCount")
            }

            // Flush AVIO buffer to disk periodically for progressive playback.
            // Ultra-aggressive after seek (every 10 packets for first 100) to get the
            // target segment to disk ~3x faster. Then moderate (every 50 for next 400),
            // then infrequent (every 500) to reduce syscall overhead.
            // packetCount resets to 0 on each seek, so this pattern auto-activates.
            if packetCount < 100 {
                if packetCount % 10 == 0 {
                    avio_flush(outCtx.pointee.pb)
                }
            } else if packetCount < 500 {
                if packetCount % 50 == 0 {
                    avio_flush(outCtx.pointee.pb)
                }
            } else if packetCount % 500 == 0 {
                avio_flush(outCtx.pointee.pb)
            }

            if packetCount / 25000 > lastProgressLog {
                lastProgressLog = packetCount / 25000
                let currentSize = Self.fileSize(at: mp4Path)
                let mb = currentSize / 1_048_576
                var dtsInfo = ""
                if let vd = lastWrittenDts[videoOutputIdx] {
                    var tbNum: Int32 = 0, tbDen: Int32 = 0
                    mks_stream_get_time_base(outCtx, videoOutputIdx, &tbNum, &tbDen)
                    if tbDen > 0 { dtsInfo += " vDts=\(String(format: "%.1f", Double(vd)/Double(tbDen)))s" }
                }
                if firstAudioOutputIdx >= 0, let ad = lastWrittenDts[firstAudioOutputIdx] {
                    var tbNum: Int32 = 0, tbDen: Int32 = 0
                    mks_stream_get_time_base(outCtx, firstAudioOutputIdx, &tbNum, &tbDen)
                    if tbDen > 0 { dtsInfo += " aDts=\(String(format: "%.1f", Double(ad)/Double(tbDen)))s" }
                }
                TransmuxLog.remux("PROGRESS \(packetCount/1000)K/\(mb)MB\(dtsInfo) seeks=\(totalSeekCount)")
            }
        }

        av_packet_free(&packet)

        // --- Cleanup BSFs ---
        for (_, bsf) in aacBsfContexts {
            mks_bsf_free(bsf)
        }
        aacBsfContexts.removeAll()

        // --- Finalize ---
        let finalDtsState = lastWrittenDts.sorted(by: { $0.key < $1.key }).map { "s\($0.key)=\($0.value)" }.joined(separator: " ")
        if handle.isCancelled {
            TransmuxLog.remux("CANCELLED \(sessionID.prefix(8)) \(packetCount/1000)K packets \(totalSeekCount) seeks finalDts=[\(finalDtsState)]")
        } else {
            av_write_trailer(outCtx)
            TransmuxLog.remux("COMPLETE \(sessionID.prefix(8)) \(packetCount/1000)K packets \(totalSeekCount) seeks finalDts=[\(finalDtsState)]")
        }
        TransmuxLog.flush()

        // Finalize subtitle collector — closes VTT files
        if let collector = subtitleCollector {
            mks_subtitle_collector_finish(collector, nil)
            subtitleCollector = nil
            TransmuxLog.remux("Subtitle collector finalized")
        }

        // Finalize HLS segmenter — writes #EXT-X-ENDLIST
        segmenter.markComplete()

        // Mark handle as complete (live flag for polling loops in TransmuxServer)
        handle.markTransmuxComplete()

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
            guard let box = MP4BoxParser.readBoxHeader(handle: handle, at: offset) else { break }

            let boxSize: UInt64
            if box.size < 0 {
                // size==0 sentinel: box extends to EOF
                boxSize = UInt64(totalSize) - offset
            } else {
                boxSize = UInt64(box.size)
            }

            if boxSize < 8 { break }

            TransmuxLog.service("  box[\(box.type)] offset=\(offset) size=\(boxSize)")

            // First moof marks the end of the init segment
            if box.type == "moof" {
                return Int64(offset)
            }

            offset += boxSize
        }

        // No moof found — entire file is the init segment
        return totalSize
    }
}
