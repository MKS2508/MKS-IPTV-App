import Foundation

#if canImport(Libavformat)
import Libavformat
import Libavcodec
import Libavutil
#endif

// MARK: - Transmux Result

/// Result of a transmuxing operation containing the local HLS playlist URL and segment directory
struct TransmuxResult {
    /// URL to the HLS .m3u8 playlist (local file URL or http://localhost)
    let playlistURL: URL
    /// Directory containing HLS segments
    let segmentDirectory: URL
    /// Session identifier for cleanup
    let sessionID: String
}

// MARK: - Transmuxing Service

/// Cross-platform transmuxing service using the FFmpeg C API bundled by KSPlayer.
/// Remuxes MKV (or other non-native containers) to fragmented MP4 / HLS
/// without re-encoding — copies video and audio streams as-is.
actor TransmuxingService {
    static let shared = TransmuxingService()

    private var activeSessions: [String: URL] = [:]

    private init() {
        #if canImport(Libavformat)
        // Register all muxers/demuxers once
        // av_register_all() is no longer needed in FFmpeg 4+; formats are auto-registered.
        #endif
    }

    // MARK: - Public API

    /// Transmux the source URL into fragmented MP4 / HLS segments.
    ///
    /// - Parameter sourceURL: Remote or local URL of the input file (e.g. MKV stream).
    /// - Returns: A `TransmuxResult` with paths to the generated playlist and segments.
    /// - Throws: `TransmuxError` on failure.
    func transmux(from sourceURL: URL) async throws -> TransmuxResult {
        #if canImport(Libavformat)
        let sessionID = UUID().uuidString
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mks-iptv-transmux-\(sessionID)")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        activeSessions[sessionID] = outputDir

        let playlistPath = outputDir.appendingPathComponent("stream.m3u8").path
        let inputPath = sourceURL.absoluteString

        print("[TransmuxingService] Starting transmux session \(sessionID)")
        print("[TransmuxingService] Input: \(inputPath)")
        print("[TransmuxingService] Output dir: \(outputDir.path)")

        // Run the actual FFmpeg C API work on a detached task to avoid actor re-entrancy issues
        let result: TransmuxResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Self.performTransmux(
                        inputPath: inputPath,
                        outputDir: outputDir,
                        playlistPath: playlistPath,
                        sessionID: sessionID
                    )
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return result
        #else
        throw TransmuxError.notAvailableOnPlatform
        #endif
    }

    /// Clean up a specific transmux session
    func cleanup(sessionID: String) {
        guard let dir = activeSessions.removeValue(forKey: sessionID) else { return }
        try? FileManager.default.removeItem(at: dir)
        print("[TransmuxingService] Cleaned up session \(sessionID)")
    }

    /// Clean up all transmux sessions
    func cleanupAll() {
        for (id, dir) in activeSessions {
            try? FileManager.default.removeItem(at: dir)
            print("[TransmuxingService] Cleaned up session \(id)")
        }
        activeSessions.removeAll()
    }

    // MARK: - FFmpeg C API Core

    #if canImport(Libavformat)
    /// Perform the actual transmux using FFmpeg C API. Runs on a background queue.
    private static func performTransmux(
        inputPath: String,
        outputDir: URL,
        playlistPath: String,
        sessionID: String
    ) throws -> TransmuxResult {
        var inputCtx: UnsafeMutablePointer<AVFormatContext>?
        var outputCtx: UnsafeMutablePointer<AVFormatContext>?

        // --- Open input ---
        var ret = avformat_open_input(&inputCtx, inputPath, nil, nil)
        guard ret >= 0, inputCtx != nil else {
            throw TransmuxError.processStartFailure(
                NSError(domain: "FFmpeg", code: Int(ret),
                        userInfo: [NSLocalizedDescriptionKey: "avformat_open_input failed (\(ret))"])
            )
        }
        defer { avformat_close_input(&inputCtx) }

        let inCtx = inputCtx!

        ret = avformat_find_stream_info(inCtx, nil)
        guard ret >= 0 else {
            throw TransmuxError.processFailure(status: Int(ret))
        }

        // --- Try HLS output first, fall back to fragmented MP4 ---
        let (outputPath, isHLS) = try allocateOutputContext(
            &outputCtx,
            playlistPath: playlistPath,
            outputDir: outputDir
        )
        guard let outCtx = outputCtx else {
            throw TransmuxError.processFailure(status: -1)
        }
        defer {
            if outCtx.pointee.pb != nil {
                avio_close(outCtx.pointee.pb)
            }
            avformat_free_context(outCtx)
        }

        // --- Map streams (copy all video + audio) ---
        let streamCount = Int(inCtx.pointee.nb_streams)
        var streamMapping = [Int](repeating: -1, count: streamCount)
        var outputStreamIndex: Int32 = 0

        for i in 0..<streamCount {
            let inStream = inCtx.pointee.streams[i]!
            let codecType = inStream.pointee.codecpar.pointee.codec_type

            // Only copy video and audio streams
            guard codecType == AVMEDIA_TYPE_VIDEO || codecType == AVMEDIA_TYPE_AUDIO else {
                continue
            }

            streamMapping[i] = Int(outputStreamIndex)
            outputStreamIndex += 1

            guard let outStream = avformat_new_stream(outCtx, nil) else {
                throw TransmuxError.processFailure(status: -1)
            }

            ret = avcodec_parameters_copy(outStream.pointee.codecpar, inStream.pointee.codecpar)
            guard ret >= 0 else {
                throw TransmuxError.processFailure(status: Int(ret))
            }
            // Mark codec tag as 0 so the muxer picks the right one
            outStream.pointee.codecpar.pointee.codec_tag = 0
        }

        // --- Set muxer options ---
        var options: OpaquePointer?
        if isHLS {
            av_dict_set(&options, "hls_segment_type", "fmp4", 0)
            av_dict_set(&options, "hls_time", "4", 0)
            av_dict_set(&options, "hls_flags", "independent_segments", 0)
            av_dict_set(&options, "hls_segment_filename",
                        outputDir.appendingPathComponent("segment_%03d.m4s").path, 0)
        }

        // --- Open output file ---
        if outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            ret = avio_open(&outCtx.pointee.pb, outputPath, AVIO_FLAG_WRITE)
            guard ret >= 0 else {
                av_dict_free(&options)
                throw TransmuxError.processFailure(status: Int(ret))
            }
        }

        // --- Write header ---
        ret = avformat_write_header(outCtx, &options)
        av_dict_free(&options)
        guard ret >= 0 else {
            throw TransmuxError.processFailure(status: Int(ret))
        }

        // --- Remux loop ---
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        defer { av_packet_free(&packet) }

        while true {
            ret = av_read_frame(inCtx, packet)
            if ret < 0 { break } // EOF or error

            let pkt = packet!
            let streamIndex = Int(pkt.pointee.stream_index)
            guard streamIndex < streamCount, streamMapping[streamIndex] >= 0 else {
                av_packet_unref(pkt)
                continue
            }

            let inStream = inCtx.pointee.streams[streamIndex]!
            let outStreamIdx = Int32(streamMapping[streamIndex])
            let outStream = outCtx.pointee.streams[Int(outStreamIdx)]!

            pkt.pointee.stream_index = outStreamIdx

            // Rescale timestamps
            av_packet_rescale_ts(pkt, inStream.pointee.time_base, outStream.pointee.time_base)
            pkt.pointee.pos = -1

            ret = av_interleaved_write_frame(outCtx, pkt)
            if ret < 0 {
                print("[TransmuxingService] Warning: write_frame error (\(ret)), continuing...")
            }
        }

        // --- Write trailer ---
        av_write_trailer(outCtx)

        print("[TransmuxingService] Transmux complete for session \(sessionID)")

        let playlistURL = URL(fileURLWithPath: outputPath)
        return TransmuxResult(
            playlistURL: playlistURL,
            segmentDirectory: outputDir,
            sessionID: sessionID
        )
    }

    /// Try to allocate an HLS output context; fall back to fragmented MP4 if HLS muxer unavailable.
    private static func allocateOutputContext(
        _ ctx: inout UnsafeMutablePointer<AVFormatContext>?,
        playlistPath: String,
        outputDir: URL
    ) throws -> (path: String, isHLS: Bool) {
        // Try HLS first
        var ret = avformat_alloc_output_context2(&ctx, nil, "hls", playlistPath)
        if ret >= 0, ctx != nil {
            return (playlistPath, true)
        }

        // HLS muxer not available — fall back to fragmented MP4
        print("[TransmuxingService] HLS muxer unavailable, falling back to fragmented MP4")
        let mp4Path = outputDir.appendingPathComponent("stream.mp4").path
        ret = avformat_alloc_output_context2(&ctx, nil, "mp4", mp4Path)
        guard ret >= 0, ctx != nil else {
            throw TransmuxError.processFailure(status: Int(ret))
        }

        // Set fMP4 movflags via the context's private options
        av_dict_set(&ctx!.pointee.metadata, "movflags",
                    "frag_keyframe+empty_moov+default_base_moof", 0)
        return (mp4Path, false)
    }
    #endif
}
