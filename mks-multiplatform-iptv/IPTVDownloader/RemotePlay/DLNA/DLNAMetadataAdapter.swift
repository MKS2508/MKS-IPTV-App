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
    /// - Returns: DIDL-Lite XML string
    static func buildDIDLLite(
        from metadata: MetadataResult?,
        contentURL: URL,
        duration: Double?
    ) -> String {
        let title = formatTitle(from: metadata)
        let durationStr = duration.map { formatDuration($0) } ?? ""

        // Build DIDL-Lite XML
        return """
        <DIDL-Lite xmlns="\(didlNamespace)" xmlns:dc="\(dcNamespace)" xmlns:upnp="\(upnpNamespace)">
          <item id="0" parentID="-1" restricted="1">
            <dc:title>\(xmlEscape(title))</dc:title>
            \(buildCreatorElements(from: metadata))
            \(buildResElement(contentURL: contentURL, duration: durationStr, metadata: metadata))
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
        return metadata.title ?? "Unknown"
    }

    // MARK: - Private Helpers

    /// Build res (resource) element with content info.
    private static func buildResElement(
        contentURL: URL,
        duration: String,
        metadata: MetadataResult?
    ) -> String {
        let durationAttr = duration.isEmpty ? "" : " duration=\"\(duration)\""
        let protocolInfo = "protocolInfo=\"http-get:*:video/mp4:*\""

        return "<res\(durationAttr) \(protocolInfo)>\(xmlEscape(contentURL.absoluteString))</res>"
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
