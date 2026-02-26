import Foundation

#if canImport(Libavformat)
import Libavformat
import Libavcodec
import Libavutil
#endif

// MARK: - Metadata Write Error

/// Errors that can occur during FFmpeg metadata writing
enum MetadataWriteError: LocalizedError {
    case ffmpegNotAvailable
    case fileNotFound(String)
    case openInputFailed(Int32)
    case openOutputFailed(Int32)
    case writeHeaderFailed(Int32)
    case writeTrailerFailed(Int32)
    case remuxFailed(Int32)
    case replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotAvailable:
            return "FFmpeg C API (Libavformat) not available"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .openInputFailed(let code):
            return "avformat_open_input failed (\(code))"
        case .openOutputFailed(let code):
            return "avformat_alloc_output_context2 failed (\(code))"
        case .writeHeaderFailed(let code):
            return "avformat_write_header failed (\(code))"
        case .writeTrailerFailed(let code):
            return "av_write_trailer failed (\(code))"
        case .remuxFailed(let code):
            return "Remux loop failed (\(code))"
        case .replaceFailed(let reason):
            return "Atomic file replace failed: \(reason)"
        }
    }
}

// MARK: - FFmpeg Metadata Writer

/// Actor-based service for writing metadata tags to downloaded media files
/// using the FFmpeg C API bundled by KSPlayer.
///
/// **Strategy**: FFmpeg cannot write metadata in-place. The approach is:
/// 1. Open the input file for reading
/// 2. Create a temporary output file with the same container format
/// 3. Set metadata dictionary on the output context
/// 4. Copy all streams (remux) from input to output — no re-encoding
/// 5. Optionally embed cover art as an attached picture stream
/// 6. Write trailer, close both, then atomically replace input with output
actor FFmpegMetadataWriter {
    static let shared = FFmpegMetadataWriter()

    private init() {}

    /// Write metadata to a media file.
    ///
    /// - Parameters:
    ///   - fileURL: Local URL of the downloaded file (MP4, MKV, etc.)
    ///   - metadata: The resolved metadata to embed
    ///   - artworkData: Optional JPEG/PNG data for cover art embedding
    func writeMetadata(
        to fileURL: URL,
        metadata: MetadataResult,
        artworkData: Data?
    ) async throws {
        #if canImport(Libavformat)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MetadataWriteError.fileNotFound(fileURL.path)
        }

        let inputPath = fileURL.path
        let tempPath = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)_metadata_temp.\(fileURL.pathExtension)")
            .path

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.performMetadataWrite(
                        inputPath: inputPath,
                        tempPath: tempPath,
                        metadata: metadata,
                        artworkData: artworkData
                    )

                    // Atomic replace: move temp over original
                    let fm = FileManager.default
                    let backupPath = inputPath + ".bak"
                    try? fm.removeItem(atPath: backupPath)
                    try fm.moveItem(atPath: inputPath, toPath: backupPath)
                    do {
                        try fm.moveItem(atPath: tempPath, toPath: inputPath)
                        try? fm.removeItem(atPath: backupPath)
                    } catch {
                        // Restore backup if rename failed
                        try? fm.moveItem(atPath: backupPath, toPath: inputPath)
                        throw MetadataWriteError.replaceFailed(error.localizedDescription)
                    }

                    continuation.resume()
                } catch {
                    try? FileManager.default.removeItem(atPath: tempPath)
                    continuation.resume(throwing: error)
                }
            }
        }
        #else
        throw MetadataWriteError.ffmpegNotAvailable
        #endif
    }

    // MARK: - Core FFmpeg Implementation

    #if canImport(Libavformat)
    private static func performMetadataWrite(
        inputPath: String,
        tempPath: String,
        metadata: MetadataResult,
        artworkData: Data?
    ) throws {
        var inputCtx: UnsafeMutablePointer<AVFormatContext>?
        var outputCtx: UnsafeMutablePointer<AVFormatContext>?

        // --- 1. Open input ---
        var ret = avformat_open_input(&inputCtx, inputPath, nil, nil)
        guard ret >= 0, let inCtx = inputCtx else {
            throw MetadataWriteError.openInputFailed(ret)
        }
        defer { avformat_close_input(&inputCtx) }

        ret = avformat_find_stream_info(inCtx, nil)
        guard ret >= 0 else {
            throw MetadataWriteError.openInputFailed(ret)
        }

        // --- 2. Allocate output context (auto-detect format from extension) ---
        ret = avformat_alloc_output_context2(&outputCtx, nil, nil, tempPath)
        guard ret >= 0, let outCtx = outputCtx else {
            throw MetadataWriteError.openOutputFailed(ret)
        }
        defer {
            if outCtx.pointee.pb != nil {
                avio_close(outCtx.pointee.pb)
            }
            avformat_free_context(outCtx)
        }

        // --- 3. Map all existing streams (copy all: video, audio, subtitles) ---
        let streamCount = Int(inCtx.pointee.nb_streams)
        var streamMapping = [Int](repeating: -1, count: streamCount)
        var outputStreamIndex: Int32 = 0

        for i in 0..<streamCount {
            guard let inStream = inCtx.pointee.streams[i],
                  let codecPar = inStream.pointee.codecpar else { continue }

            // Skip existing attached pictures — we'll add our own if artwork is provided
            if codecPar.pointee.codec_type == AVMEDIA_TYPE_VIDEO
                && inStream.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC != 0
                && artworkData != nil {
                continue
            }

            streamMapping[i] = Int(outputStreamIndex)
            outputStreamIndex += 1

            guard let outStream = avformat_new_stream(outCtx, nil) else {
                throw MetadataWriteError.openOutputFailed(-1)
            }

            ret = avcodec_parameters_copy(outStream.pointee.codecpar, codecPar)
            guard ret >= 0 else {
                throw MetadataWriteError.openOutputFailed(ret)
            }
            outStream.pointee.codecpar.pointee.codec_tag = 0

            // Copy stream disposition and time_base
            outStream.pointee.disposition = inStream.pointee.disposition
        }

        // --- 4. Set metadata on output context ---
        setMetadataDictionary(on: outCtx, metadata: metadata)

        // --- 5. Add cover art stream if artwork is provided ---
        if let artworkData = artworkData {
            addCoverArtStream(to: outCtx, imageData: artworkData)
        }

        // --- 6. Open output file and write header ---
        if outCtx.pointee.oformat.pointee.flags & AVFMT_NOFILE == 0 {
            ret = avio_open(&outCtx.pointee.pb, tempPath, AVIO_FLAG_WRITE)
            guard ret >= 0 else {
                throw MetadataWriteError.openOutputFailed(ret)
            }
        }

        ret = avformat_write_header(outCtx, nil)
        guard ret >= 0 else {
            throw MetadataWriteError.writeHeaderFailed(ret)
        }

        // --- 7. Remux all packets ---
        var packet = av_packet_alloc()
        defer { av_packet_free(&packet) }

        while true {
            ret = av_read_frame(inCtx, packet)
            if ret < 0 { break }

            guard let pkt = packet else { break }
            let si = Int(pkt.pointee.stream_index)
            guard si < streamCount, streamMapping[si] >= 0 else {
                av_packet_unref(pkt)
                continue
            }

            guard let inStream = inCtx.pointee.streams[si] else {
                av_packet_unref(pkt)
                continue
            }
            let outSI = Int32(streamMapping[si])
            guard let outStream = outCtx.pointee.streams[Int(outSI)] else {
                av_packet_unref(pkt)
                continue
            }

            pkt.pointee.stream_index = outSI
            av_packet_rescale_ts(pkt, inStream.pointee.time_base, outStream.pointee.time_base)
            pkt.pointee.pos = -1

            ret = av_interleaved_write_frame(outCtx, pkt)
            // Continue even on non-fatal write errors
        }

        // --- 8. Write trailer ---
        ret = av_write_trailer(outCtx)
        guard ret >= 0 else {
            throw MetadataWriteError.writeTrailerFailed(ret)
        }
    }

    // MARK: - Metadata Dictionary

    /// Set metadata key-value pairs on the output format context.
    ///
    /// FFmpeg's muxers automatically map generic keys to the correct container atoms:
    /// - **MP4**: `title` → `©nam`, `artist` → `©ART`, `genre` → `©gen`, `date` → `©day`, etc.
    /// - **MKV**: `title` → `TITLE`, `DESCRIPTION` → `DESCRIPTION`, etc.
    private static func setMetadataDictionary(
        on ctx: UnsafeMutablePointer<AVFormatContext>,
        metadata: MetadataResult
    ) {
        let formatName: String
        if let oformat = ctx.pointee.oformat, let name = oformat.pointee.name {
            formatName = String(cString: name).lowercased()
        } else {
            formatName = ""
        }

        let isMKV = formatName.contains("matroska") || formatName.contains("webm")

        // Title
        av_dict_set(&ctx.pointee.metadata, "title", metadata.title, 0)

        // Plot / Description
        if let plot = metadata.plot, !plot.isEmpty {
            av_dict_set(&ctx.pointee.metadata, "description", plot, 0)
            av_dict_set(&ctx.pointee.metadata, "comment", plot, 0)
            if isMKV {
                av_dict_set(&ctx.pointee.metadata, "SYNOPSIS", plot, 0)
            }
        }

        // Genre
        if !metadata.genre.isEmpty {
            let genreString = metadata.genre.joined(separator: ", ")
            av_dict_set(&ctx.pointee.metadata, "genre", genreString, 0)
        }

        // Date / Year
        if let releaseDate = metadata.releaseDate, !releaseDate.isEmpty {
            av_dict_set(&ctx.pointee.metadata, "date", releaseDate, 0)
            if isMKV {
                av_dict_set(&ctx.pointee.metadata, "DATE_RELEASED", releaseDate, 0)
            }
        } else if let year = metadata.year {
            av_dict_set(&ctx.pointee.metadata, "date", String(year), 0)
        }

        // Director
        if let director = metadata.director, !director.isEmpty {
            av_dict_set(&ctx.pointee.metadata, "artist", director, 0)
            if isMKV {
                av_dict_set(&ctx.pointee.metadata, "DIRECTOR", director, 0)
            }
        }

        // Cast
        if !metadata.cast.isEmpty {
            let castString = metadata.cast.prefix(10).joined(separator: ", ")
            av_dict_set(&ctx.pointee.metadata, "album_artist", castString, 0)
            if isMKV {
                av_dict_set(&ctx.pointee.metadata, "ACTOR", castString, 0)
            }
        }

        // Rating
        if let rating = metadata.rating {
            av_dict_set(&ctx.pointee.metadata, "rating", String(format: "%.1f", rating), 0)
        }

        // Content advisory rating
        if let advisory = metadata.contentAdvisoryRating, !advisory.isEmpty {
            av_dict_set(&ctx.pointee.metadata, "content_rating", advisory, 0)
        }

        // Show name (for episodes/series)
        if let showTitle = metadata.showTitle, !showTitle.isEmpty {
            av_dict_set(&ctx.pointee.metadata, "show", showTitle, 0)
            av_dict_set(&ctx.pointee.metadata, "album", showTitle, 0)
        }

        // Season / Episode numbers
        if let season = metadata.seasonNumber {
            av_dict_set(&ctx.pointee.metadata, "season_number", String(season), 0)
        }
        if let episode = metadata.episodeNumber {
            av_dict_set(&ctx.pointee.metadata, "episode_sort", String(episode), 0)
        }
    }

    // MARK: - Cover Art

    /// Add a cover art stream as an attached picture.
    ///
    /// For MP4: becomes an iTunes cover art atom.
    /// For MKV: becomes a Matroska attachment with mimetype.
    private static func addCoverArtStream(
        to ctx: UnsafeMutablePointer<AVFormatContext>,
        imageData: Data
    ) {
        guard let outStream = avformat_new_stream(ctx, nil) else { return }

        // Detect JPEG vs PNG from magic bytes
        let isJPEG = imageData.count > 2 && imageData[0] == 0xFF && imageData[1] == 0xD8
        let codecId: AVCodecID = isJPEG ? AV_CODEC_ID_MJPEG : AV_CODEC_ID_PNG

        outStream.pointee.codecpar.pointee.codec_type = AVMEDIA_TYPE_VIDEO
        outStream.pointee.codecpar.pointee.codec_id = codecId
        outStream.pointee.codecpar.pointee.width = 600
        outStream.pointee.codecpar.pointee.height = 600
        outStream.pointee.disposition = AV_DISPOSITION_ATTACHED_PIC

        // Attachment metadata for MKV
        av_dict_set(&outStream.pointee.metadata, "filename",
                    isJPEG ? "cover.jpg" : "cover.png", 0)
        av_dict_set(&outStream.pointee.metadata, "mimetype",
                    isJPEG ? "image/jpeg" : "image/png", 0)

        // Place image data in extradata for the muxer to pick up
        let size = imageData.count
        if let buffer = av_malloc(size) {
            imageData.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    memcpy(buffer, baseAddress, size)
                }
            }
            outStream.pointee.codecpar.pointee.extradata =
                buffer.assumingMemoryBound(to: UInt8.self)
            outStream.pointee.codecpar.pointee.extradata_size = Int32(size)
        }
    }
    #endif
}
