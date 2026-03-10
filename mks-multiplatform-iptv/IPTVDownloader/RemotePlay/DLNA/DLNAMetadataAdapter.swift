//
//  DLNAMetadataAdapter.swift
//  mks-multiplatform-iptv
//
//  Created for RemotePlay feature - Converts MetadataResult to DIDL-Lite XML for DLNA
//

import Foundation

/// Converts MetadataResult to DIDL-Lite XML for DLNA SetAVTransportURI.
/// Follows the same title-formatting logic as PlayerMetadataHelper.setNowPlayingInfo
/// for consistency across AirPlay and DLNA displays.
enum DLNAMetadataAdapter {

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
    ///   - metadata: Optional media metadata (title, poster, episode info, etc.)
    ///   - contentURL: The URL of the content being cast
    ///   - duration: Optional content duration in seconds
    ///   - streaming: When true, marks content as progressive/live (OP=00, no seeking).
    ///     Use for progressive transmux content that is still being written.
    /// - Returns: DIDL-Lite XML string
    static func buildDIDLLite(
        from metadata: MetadataResult?,
        contentURL: URL,
        duration: Double?,
        streaming: Bool = false
    ) -> String {
        let title = formatTitle(from: metadata)
        let durationStr = duration.map { formatDuration($0) } ?? ""

        // Build DIDL-Lite XML
        return """
        <DIDL-Lite xmlns="\(didlNamespace)" xmlns:dc="\(dcNamespace)" xmlns:upnp="\(upnpNamespace)">
          <item id="0" parentID="-1" restricted="1">
            <dc:title>\(xmlEscape(title))</dc:title>
            \(buildCreatorElements(from: metadata))
            \(buildResElement(contentURL: contentURL, duration: durationStr, metadata: metadata, streaming: streaming))
            \(buildAlbumArt(metadata: metadata))
          </item>
        </DIDL-Lite>
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Title Formatting

    /// Format display title following the same logic as PlayerMetadataHelper.setNowPlayingInfo.
    /// - Episode: "ShowTitle - S01E03 - EpisodeTitle"
    /// - Series: showTitle
    /// - Movie: title
    static func formatTitle(from metadata: MetadataResult?) -> String {
        guard let metadata else {
            return "Unknown"
        }

        // Episode with all info
        if let showTitle = metadata.showTitle,
           let season = metadata.seasonNumber,
           let episode = metadata.episodeNumber,
           let episodeTitle = metadata.episodeTitle,
           season > 0, episode > 0 {
            let seasonStr = String(format: "%02d", season)
            let episodeStr = String(format: "%02d", episode)
            return "\(showTitle) - S\(seasonStr)E\(episodeStr) - \(episodeTitle)"
        }

        // Episode with show title only
        if let showTitle = metadata.showTitle,
           let season = metadata.seasonNumber,
           let episode = metadata.episodeNumber,
           season > 0, episode > 0 {
            let seasonStr = String(format: "%02d", season)
            let episodeStr = String(format: "%02d", episode)
            return "\(showTitle) - S\(seasonStr)E\(episodeStr)"
        }

        // Series with show title
        if let showTitle = metadata.showTitle {
            return showTitle
        }

        // Movie title
        return metadata.title
    }

    // MARK: - Private Helpers

    /// Build res (resource) element with content info.
    private static func buildResElement(
        contentURL: URL,
        duration: String,
        metadata: MetadataResult?,
        streaming: Bool
    ) -> String {
        let durationAttr = duration.isEmpty ? "" : " duration=\"\(duration)\""
        let mimeType = mimeTypeForURL(contentURL)
        let dlnaFlags = dlnaProfileFlags(for: mimeType, streaming: streaming)
        let protocolInfo = "protocolInfo=\"http-get:*:\(mimeType):\(dlnaFlags)\""

        return "<res\(durationAttr) \(protocolInfo)>\(xmlEscape(contentURL.absoluteString))</res>"
    }

    /// Derive MIME type from URL extension for DLNA protocolInfo.
    private static func mimeTypeForURL(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
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
        default:
            return "video/*"
        }
    }

    /// Build creator elements (director, actor).
    private static func buildCreatorElements(from metadata: MetadataResult?) -> String {
        guard let metadata else { return "" }
        var elements = ""

        if let director = metadata.director, !director.isEmpty {
            elements += "<upnp:director>\(xmlEscape(director))</upnp:director>\n          "
        }

        let castMembers = metadata.cast
        if !castMembers.isEmpty {
            // Take first 3 cast members (cast is already [String])
            let topCast = castMembers.map { $0.trimmingCharacters(in: .whitespaces) }.prefix(3)
            for actor in topCast {
                elements += "<upnp:actor>\(xmlEscape(actor))</upnp:actor>\n          "
            }
        }

        return elements.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Build album art (poster) element.
    private static func buildAlbumArt(metadata: MetadataResult?) -> String {
        guard let metadata else { return "" }

        // posterURL is a String?, artworkURLs is [String]
        let posterString = metadata.posterURL ?? metadata.artworkURLs.first

        guard let posterString, !posterString.isEmpty else {
            return ""
        }

        // posterString is already a URL string, no need to call absoluteString
        return "<upnp:albumArtURI>\(xmlEscape(posterString))</upnp:albumArtURI>"
    }

    /// Format duration as HH:MM:SS for DIDL-Lite res@duration.
    static func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }

    /// Returns DLNA.ORG profile flags string for the given MIME type.
    /// Used in protocolInfo 4th field.
    /// - Parameters:
    ///   - mimeType: The content MIME type
    ///   - streaming: When true, disables byte-range seeking (OP=00) and marks
    ///     content as being converted (CI=1). Use for progressive/live streaming.
    /// - Returns: DLNA.ORG flags string, or "*" for unknown types
    static func dlnaProfileFlags(for mimeType: String, streaming: Bool = false) -> String {
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

    /// XML-escape a string for safe embedding in XML.
    static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
