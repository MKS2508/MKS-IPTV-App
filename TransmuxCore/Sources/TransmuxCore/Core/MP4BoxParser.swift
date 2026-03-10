import Foundation

// MARK: - MP4BoxParser

/// Stateless MP4 ISO base media file format box header parsing utilities.
///
/// Consolidates the box header reading logic that was previously duplicated
/// across HLSSegmenter (FileHandle-based), TransmuxServer (Data-based),
/// and TransmuxingService (inline FileHandle-based).
///
/// Supports three box size encodings per ISO 14496-12:
/// - **Normal (32-bit)**: `size32 >= 8` — size is the first 4 bytes, header is 8 bytes
/// - **Extended (64-bit)**: `size32 == 1` — real size is bytes [8..16], header is 16 bytes
/// - **To-EOF**: `size32 == 0` — box extends to end of container; returned as `size = -1`
public enum MP4BoxParser {

    /// A parsed MP4 box header.
    public struct BoxHeader {
        /// Total box size in bytes (including header). Returns `-1` when
        /// `size32 == 0` (box extends to end of file/container) — caller
        /// must substitute the actual remaining size.
        public let size: Int64

        /// Four-character box type code (e.g. "moof", "traf", "tfdt").
        public let type: String

        /// Size of the header itself: 8 bytes for normal boxes, 16 for extended size.
        /// Payload starts at `offset + headerSize`.
        public let headerSize: Int
    }

    // MARK: - FileHandle Variant

    /// Read a box header from a FileHandle at a given byte offset.
    ///
    /// Used by HLSSegmenter (moov parsing, segment scanning) and
    /// TransmuxingService (init segment boundary detection).
    ///
    /// - Parameters:
    ///   - handle: An open FileHandle (will seek to `offset`).
    ///   - offset: Absolute byte offset in the file.
    /// - Returns: A `BoxHeader` or `nil` if insufficient data or seek failure.
    public static func readBoxHeader(handle: FileHandle, at offset: UInt64) -> BoxHeader? {
        do { try handle.seek(toOffset: offset) } catch { return nil }
        let data = handle.readData(ofLength: 8)
        guard data.count == 8 else { return nil }

        let size32 = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.load(fromByteOffset: 0, as: UInt32.self).bigEndian
        }
        let typeBytes = data.subdata(in: 4..<8)
        let type = String(data: typeBytes, encoding: .ascii) ?? "????"

        if size32 == 1 {
            // Extended 64-bit size
            let extData = handle.readData(ofLength: 8)
            guard extData.count == 8 else { return nil }
            let size64 = extData.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            return BoxHeader(size: Int64(size64), type: type, headerSize: 16)
        }

        if size32 == 0 {
            // Box extends to end of file — caller must handle
            return BoxHeader(size: -1, type: type, headerSize: 8)
        }

        return BoxHeader(size: Int64(size32), type: type, headerSize: 8)
    }

    // MARK: - Data Variant

    /// Read a box header from a Data buffer at a given byte offset.
    ///
    /// Used by TransmuxServer for in-memory tfdt rewriting of moof+mdat chunks.
    ///
    /// - Parameters:
    ///   - data: The buffer to read from.
    ///   - offset: Byte offset within the buffer.
    /// - Returns: A `BoxHeader` or `nil` if insufficient data.
    public static func readBoxHeader(data: Data, at offset: Int) -> BoxHeader? {
        guard offset + 8 <= data.count else { return nil }

        let size32 = data.withUnsafeBytes { ptr -> UInt32 in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian
        }

        let typeStart = offset + 4
        let typeSlice = data[typeStart..<(typeStart + 4)]
        let type = String(data: typeSlice, encoding: .ascii) ?? "????"

        if size32 == 1 {
            // Extended 64-bit size
            guard offset + 16 <= data.count else { return nil }
            let size64 = data.withUnsafeBytes { ptr -> UInt64 in
                ptr.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self).bigEndian
            }
            return BoxHeader(size: Int64(size64), type: type, headerSize: 16)
        }

        if size32 == 0 {
            // Box extends to end of buffer
            return BoxHeader(size: Int64(data.count - offset), type: type, headerSize: 8)
        }

        return BoxHeader(size: Int64(size32), type: type, headerSize: 8)
    }
}
