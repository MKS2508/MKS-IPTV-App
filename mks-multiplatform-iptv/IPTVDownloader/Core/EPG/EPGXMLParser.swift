//
//  EPGXMLParser.swift
//  mks-multiplatform-iptv
//
//  SAX-style streaming XML parser for XMLTV EPG data
//  Handles large files (~10MB+) incrementally without loading full DOM
//

import Foundation

/// Streaming XMLTV parser using XMLParser (SAX) for memory-efficient parsing
final class EPGXMLParser: NSObject, XMLParserDelegate {

    // MARK: - Parsed Results

    private(set) var channels: [EPGChannel] = []
    private(set) var programmes: [EPGProgramme] = []

    // MARK: - Parser State

    private var currentElement = ""
    private var currentText = ""

    // Channel parsing state
    private var currentChannelId: String?
    private var currentDisplayNames: [String] = []
    private var currentIconURL: String?

    // Programme parsing state
    private var currentProgrammeChannelId: String?
    private var currentProgrammeStart: Date?
    private var currentProgrammeStop: Date?
    private var currentProgrammeTitle: String?
    private var currentProgrammeDesc: String?
    private var currentProgrammeCategory: String?

    // Parsing context
    private var isInChannel = false
    private var isInProgramme = false

    // MARK: - Time Window Filter

    /// If set, programmes ending before this date are skipped during parse
    var timeWindowStart: Date?

    /// If set, programmes starting after this date are skipped during parse
    var timeWindowEnd: Date?

    // MARK: - Date Parsing

    /// XMLTV date format: "YYYYMMDDHHmmss +HHMM"
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Alternative date format without timezone offset
    private static let dateFormatterNoTZ: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    // MARK: - Public API

    /// Parse EPG XML data and return structured EPG data
    func parse(data: Data) throws -> EPGData {
        channels = []
        programmes = []

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        let success = parser.parse()

        if !success, let error = parser.parserError {
            throw EPGError.parseFailed(error.localizedDescription)
        }

        return EPGData(
            channels: channels,
            programmes: programmes,
            fetchedAt: Date()
        )
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "channel":
            isInChannel = true
            currentChannelId = attributeDict["id"]
            currentDisplayNames = []
            currentIconURL = nil

        case "programme":
            isInProgramme = true
            currentProgrammeChannelId = attributeDict["channel"]
            currentProgrammeStart = parseDate(attributeDict["start"])
            currentProgrammeStop = parseDate(attributeDict["stop"])
            currentProgrammeTitle = nil
            currentProgrammeDesc = nil
            currentProgrammeCategory = nil

        case "icon":
            if isInChannel {
                currentIconURL = attributeDict["src"]
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "channel":
            if let id = currentChannelId, !currentDisplayNames.isEmpty {
                let channel = EPGChannel(
                    id: id,
                    displayNames: currentDisplayNames,
                    iconURL: currentIconURL
                )
                channels.append(channel)
            }
            isInChannel = false

        case "programme":
            if let channelId = currentProgrammeChannelId,
               let start = currentProgrammeStart,
               let stop = currentProgrammeStop,
               let title = currentProgrammeTitle, !title.isEmpty {

                // Time-window filter: skip programmes entirely outside the window
                let dominated: Bool = {
                    if let windowStart = timeWindowStart, stop < windowStart { return true }
                    if let windowEnd = timeWindowEnd, start > windowEnd { return true }
                    return false
                }()

                if !dominated {
                    // Parse dobleM description format: "Category | Year | Rating\n- Description"
                    let (desc, year, rating, category) = parseDoubleMDescription(
                        currentProgrammeDesc,
                        fallbackCategory: currentProgrammeCategory
                    )

                    let programme = EPGProgramme(
                        channelId: channelId,
                        start: start,
                        stop: stop,
                        title: title,
                        description: desc,
                        category: category,
                        year: year,
                        rating: rating
                    )
                    programmes.append(programme)
                }
            }
            isInProgramme = false

        case "display-name":
            if isInChannel && !trimmed.isEmpty {
                currentDisplayNames.append(trimmed)
            }

        case "title":
            if isInProgramme {
                currentProgrammeTitle = trimmed
            }

        case "desc":
            if isInProgramme {
                currentProgrammeDesc = trimmed
            }

        case "category":
            if isInProgramme && currentProgrammeCategory == nil {
                currentProgrammeCategory = trimmed
            }

        default:
            break
        }
    }

    // MARK: - Private Helpers

    private func parseDate(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        if let date = Self.dateFormatter.date(from: string) {
            return date
        }
        // Try without timezone
        let cleaned = string.trimmingCharacters(in: .whitespaces)
        let dateOnly = String(cleaned.prefix(14))
        return Self.dateFormatterNoTZ.date(from: dateOnly)
    }

    /// Parse dobleM EPG description format
    /// Format: "Category | Year | Rating\n- Plot text"
    private func parseDoubleMDescription(
        _ rawDesc: String?,
        fallbackCategory: String?
    ) -> (description: String?, year: String?, rating: String?, category: String?) {
        guard let rawDesc = rawDesc, !rawDesc.isEmpty else {
            return (nil, nil, nil, fallbackCategory)
        }

        // Split on newline to separate metadata line from description
        let lines = rawDesc.components(separatedBy: "\n")

        var metadataLine: String?
        var descriptionText: String?

        if lines.count >= 2 {
            metadataLine = lines[0]
            // Join remaining lines, removing leading bullet/dot
            let descLines = lines.dropFirst().map { line in
                var cleaned = line
                if cleaned.hasPrefix("\u{00B7} ") || cleaned.hasPrefix("- ") {
                    cleaned = String(cleaned.dropFirst(2))
                }
                return cleaned
            }
            descriptionText = descLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Single line — check if it contains pipe separators
            if rawDesc.contains("|") {
                metadataLine = rawDesc
            } else {
                descriptionText = rawDesc
            }
        }

        var parsedCategory = fallbackCategory
        var parsedYear: String?
        var parsedRating: String?

        // Parse metadata line: "Category | Year | Rating"
        if let meta = metadataLine {
            let parts = meta.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }

            for part in parts {
                if part.isEmpty { continue }

                // Year detection (4-digit number between 1900-2099)
                if let _ = part.range(of: #"^(19|20)\d{2}$"#, options: .regularExpression) {
                    parsedYear = part
                }
                // Rating detection (number with optional decimal)
                else if let _ = part.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) {
                    parsedRating = part
                }
                // Otherwise treat as category
                else if parsedCategory == nil || parsedCategory?.isEmpty == true {
                    parsedCategory = part
                }
            }
        }

        let finalDesc = (descriptionText?.isEmpty == true) ? nil : descriptionText

        return (finalDesc, parsedYear, parsedRating, parsedCategory)
    }
}
