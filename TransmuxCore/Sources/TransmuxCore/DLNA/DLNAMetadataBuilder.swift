//
//  DLNAMetadataBuilder.swift
//  TransmuxCore
//
//  Builds DIDL-Lite XML metadata for DLNA SetAVTransportURI.
//  Simplified builder with plain parameters (no app-specific MetadataResult dependency).
//
//  Ported from mks-multiplatform-iptv RemotePlay/DLNA/DLNAMetadataAdapter.swift,
//  removing MetadataResult dependency for standalone TransmuxCore use.
//

import Foundation

/// Builds DIDL-Lite XML for DLNA SetAVTransportURI CurrentURIMetaData.
public enum DLNAMetadataBuilder {

    // MARK: - DIDL-Lite Constants

    /// DIDL-Lite XML namespace.
    private static let didlNamespace = "urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"

    /// DCMI namespace for item attributes.
    private static let dcNamespace = "http://purl.org/dc/elements/1.1/"

    /// UPnP namespace for UPnP-specific attributes.
    private static let upnpNamespace = "urn:schemas-upnp-org:metadata-1-0/upnp/"

    // MARK: - Public API

    /// Build DIDL-Lite XML document for SetAVTransportURI CurrentURIMetaData.
    /// - Parameters:
    ///   - title: Display title for the content
    ///   - contentURL: The URL of the content being served
    ///   - duration: Optional content duration in seconds
    ///   - mimeType: Optional MIME type override (auto-detected from URL extension if nil)
    ///   - dlnaFlags: Optional DLNA.ORG profile flags for protocolInfo 4th field (auto-detected if nil)
    ///   - streaming: When true, marks content as progressive/live (OP=00, no seeking)
    /// - Returns: DIDL-Lite XML string
    public static func buildDIDLLite(
        title: String,
        contentURL: URL,
        duration: Double? = nil,
        mimeType: String? = nil,
        dlnaFlags: String? = nil,
        streaming: Bool = false
    ) -> String {
        let durationStr = duration.map { formatDuration($0) } ?? ""
        let durationAttr = durationStr.isEmpty ? "" : " duration=\"\(durationStr)\""
        let resolvedMime = mimeType ?? mimeTypeForExtension(contentURL.pathExtension)
        let resolvedFlags = dlnaFlags ?? dlnaProfileFlags(for: resolvedMime, streaming: streaming)
        let protocolInfo = "http-get:*:\(resolvedMime):\(resolvedFlags)"

        return """
        <DIDL-Lite xmlns="\(didlNamespace)" xmlns:dc="\(dcNamespace)" xmlns:upnp="\(upnpNamespace)">
          <item id="0" parentID="-1" restricted="1">
            <dc:title>\(DLNASOAPClient.xmlEscape(title))</dc:title>
            <upnp:class>object.item.videoItem</upnp:class>
            <res\(durationAttr) protocolInfo="\(protocolInfo)">\(DLNASOAPClient.xmlEscape(contentURL.absoluteString))</res>
          </item>
        </DIDL-Lite>
        """
    }

    // MARK: - DLNA Profile Flags

    /// Returns DLNA.ORG profile flags string for the given MIME type.
    /// Used in protocolInfo 4th field and contentFeatures.dlna.org HTTP header.
    /// - Parameters:
    ///   - mimeType: The content MIME type
    ///   - streaming: When true, disables byte-range seeking (OP=00) and marks
    ///     content as being converted (CI=1). Use for progressive/live streaming.
    /// - Returns: DLNA.ORG flags string, or "*" for unknown types
    public static func dlnaProfileFlags(for mimeType: String, streaming: Bool = false) -> String {
        // OP=01: byte-range seek supported (complete files)
        // OP=00: no seeking (progressive/live streaming)
        // CI=0: not converted, CI=1: content being transcoded/converted
        // FLAGS bit 21 (0x200000): DLNA_V15 — bit 24 (0x1000000): Streaming mode
        let op = streaming ? "00" : "01"
        let ci = streaming ? "1" : "0"
        let flags = streaming
            ? "21700000000000000000000000000000"  // streaming + sender-paced
            : "01700000000000000000000000000000"  // background + interactive + streaming
        switch mimeType {
        case "video/mpeg", "video/mp2t":
            return "DLNA.ORG_PN=MPEG_TS_HD_NA;DLNA.ORG_OP=\(op);DLNA.ORG_CI=\(ci);DLNA.ORG_FLAGS=\(flags)"
        case "video/mp4":
            return "DLNA.ORG_PN=AVC_MP4_HD_60_AC3;DLNA.ORG_OP=\(op);DLNA.ORG_CI=\(ci);DLNA.ORG_FLAGS=\(flags)"
        default:
            return "*"
        }
    }

    // MARK: - Helpers

    /// Derive MIME type from file extension.
    public static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp4", "m4v":
            return "video/mp4"
        case "mkv":
            return "video/x-matroska"
        case "avi":
            return "video/x-msvideo"
        case "ts", "m2ts":
            // DLNA renderers (e.g. TELEFUNKEN) expect "video/mpeg" for MPEG-TS,
            // not the IANA-standard "video/mp2t" which triggers SOAP fault 714.
            return "video/mpeg"
        case "mov":
            return "video/quicktime"
        case "wmv":
            return "video/x-ms-wmv"
        case "flv":
            return "video/x-flv"
        case "webm":
            return "video/webm"
        case "m3u8":
            return "application/x-mpegURL"
        case "mp3":
            return "audio/mpeg"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        default:
            return "video/*"
        }
    }

    /// Format duration as HH:MM:SS for DIDL-Lite res@duration.
    public static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Parse a DLNA duration string (HH:MM:SS or H:MM:SS.fff) to seconds.
    public static func parseDuration(_ string: String) -> Double {
        // Handle "NOT_IMPLEMENTED" or empty strings
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("NOT_") else { return 0 }

        let parts = trimmed.split(separator: ":")
        guard parts.count >= 3 else { return 0 }

        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0

        return hours * 3600 + minutes * 60 + seconds
    }
}
