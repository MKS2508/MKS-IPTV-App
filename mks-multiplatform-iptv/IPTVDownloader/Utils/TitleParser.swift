//
//  TitleParser.swift
//  mks-multiplatform-iptv
//
//  Extracts metadata from IPTV content titles (movies, series)
//  Parses: year, quality/resolution, codec, source, audio format
//

import Foundation

struct TitleMetadata: Sendable {
    let cleanTitle: String
    let year: String?
    let quality: String?
    let codec: String?
    let source: String?
    let audio: String?
    let isHDR: Bool
    let is3D: Bool
    
    var displayQuality: String? {
        if let quality = quality {
            return quality
        }
        return nil
    }
    
    var allBadges: [String] {
        var badges: [String] = []
        if let year = year { badges.append(year) }
        if let quality = quality { badges.append(quality) }
        if let codec = codec { badges.append(codec) }
        if isHDR { badges.append("HDR") }
        if is3D { badges.append("3D") }
        return badges
    }
}

enum TitleParser {
    
    private static let yearPattern = #"\b((?:19|20)\d{2})\b"#
    
    private static let qualityPatterns: [(pattern: String, normalized: String)] = [
        (#"(?i)\b4K\s*UHD\b"#, "4K UHD"),
        (#"(?i)\bUHD\b"#, "4K UHD"),
        (#"(?i)\b4K\b"#, "4K"),
        (#"(?i)\b2160[pP]\b"#, "4K"),
        (#"(?i)\b1080[pP]\b"#, "1080p"),
        (#"(?i)\b720[pP]\b"#, "720p"),
        (#"(?i)\b480[pP]\b"#, "480p"),
        (#"(?i)\b360[pP]\b"#, "360p"),
        (#"(?i)\bSD\b"#, "SD"),
        (#"(?i)\bHD\b"#, "HD"),
        (#"(?i)\bFHD\b"#, "FHD"),
        (#"(?i)\bFullHD\b"#, "FHD")
    ]
    
    private static let codecPatterns: [(pattern: String, normalized: String)] = [
        (#"(?i)\bx265\b"#, "x265"),
        (#"(?i)\bh265\b"#, "H.265"),
        (#"(?i)\bhevc\b"#, "HEVC"),
        (#"(?i)\bx264\b"#, "x264"),
        (#"(?i)\bh264\b"#, "H.264"),
        (#"(?i)\bavc\b"#, "AVC"),
        (#"(?i)\bav1\b"#, "AV1"),
        (#"(?i)\bxvid\b"#, "XviD"),
        (#"(?i)\bdivx\b"#, "DivX")
    ]
    
    private static let sourcePatterns: [(pattern: String, normalized: String)] = [
        (#"(?i)\bBluRay\b"#, "BluRay"),
        (#"(?i)\bBDRip\b"#, "BDRip"),
        (#"(?i)\bBRRip\b"#, "BRRip"),
        (#"(?i)\bWEB-DL\b"#, "WEB-DL"),
        (#"(?i)\bWEBDL\b"#, "WEB-DL"),
        (#"(?i)\bWEBRip\b"#, "WEBRip"),
        (#"(?i)\bHDTV\b"#, "HDTV"),
        (#"(?i)\bDVDRip\b"#, "DVDRip"),
        (#"(?i)\bDVDScr\b"#, "DVDScr"),
        (#"(?i)\bTS\b"#, "TS"),
        (#"(?i)\bCAM\b"#, "CAM"),
        (#"(?i)\bHC\b"#, "HC"),
        (#"(?i)\bHDRip\b"#, "HDRip")
    ]
    
    private static let audioPatterns: [(pattern: String, normalized: String)] = [
        (#"(?i)\bAtmos\b"#, "Atmos"),
        (#"(?i)\bTrueHD\b"#, "TrueHD"),
        (#"(?i)\bDTS-HD\b"#, "DTS-HD"),
        (#"(?i)\bDTS\b"#, "DTS"),
        (#"(?i)\bDD\+?\b"#, "DD+"),
        (#"(?i)\bDD5\.?1\b"#, "DD5.1"),
        (#"(?i)\bAC3\b"#, "AC3"),
        (#"(?i)\bAAC\b"#, "AAC"),
        (#"(?i)\b5\.1\b"#, "5.1"),
        (#"(?i)\b7\.1\b"#, "7.1"),
        (#"(?i)\bDual\s*Audio\b"#, "Dual Audio")
    ]
    
    private static let hdrPattern = #"(?i)\bHDR(?:10\+?|10|Dolby)?\b"#
    private static let threeDPattern = #"(?i)\b3D\b"#
    
    static func parse(_ title: String) -> TitleMetadata {
        var workingTitle = title
        
        let year = extractYear(from: workingTitle)
        workingTitle = removeFromTitle(workingTitle, pattern: yearPattern)
        
        let quality = extractQuality(from: title)
        workingTitle = removeFromTitle(workingTitle, patterns: qualityPatterns.map { $0.pattern })
        
        let codec = extractCodec(from: title)
        workingTitle = removeFromTitle(workingTitle, patterns: codecPatterns.map { $0.pattern })
        
        let source = extractSource(from: title)
        workingTitle = removeFromTitle(workingTitle, patterns: sourcePatterns.map { $0.pattern })
        
        let audio = extractAudio(from: title)
        workingTitle = removeFromTitle(workingTitle, patterns: audioPatterns.map { $0.pattern })
        
        let isHDR = checkHDR(from: title)
        workingTitle = removeFromTitle(workingTitle, pattern: hdrPattern)
        
        let is3D = check3D(from: title)
        workingTitle = removeFromTitle(workingTitle, pattern: threeDPattern)
        
        workingTitle = removeParenthesesContent(from: workingTitle)
        workingTitle = cleanTitle(workingTitle)
        
        return TitleMetadata(
            cleanTitle: workingTitle,
            year: year,
            quality: quality,
            codec: codec,
            source: source,
            audio: audio,
            isHDR: isHDR,
            is3D: is3D
        )
    }
    
    private static func extractYear(from title: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: yearPattern) else { return nil }
        let range = NSRange(title.startIndex..., in: title)
        let matches = regex.matches(in: title, range: range)
        
        guard let match = matches.first else { return nil }
        if let yearRange = Range(match.range(at: 1), in: title) {
            let year = String(title[yearRange])
            if let yearInt = Int(year), yearInt >= 1900, yearInt <= Calendar.current.component(.year, from: Date()) + 1 {
                return year
            }
        }
        return nil
    }
    
    private static func extractQuality(from title: String) -> String? {
        for (pattern, normalized) in qualityPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                return normalized
            }
        }
        return nil
    }
    
    private static func extractCodec(from title: String) -> String? {
        for (pattern, normalized) in codecPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                return normalized
            }
        }
        return nil
    }
    
    private static func extractSource(from title: String) -> String? {
        for (pattern, normalized) in sourcePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                return normalized
            }
        }
        return nil
    }
    
    private static func extractAudio(from title: String) -> String? {
        for (pattern, normalized) in audioPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                return normalized
            }
        }
        return nil
    }
    
    private static func checkHDR(from title: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: hdrPattern) else { return false }
        return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }
    
    private static func check3D(from title: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: threeDPattern) else { return false }
        return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }
    
    private static func removeFromTitle(_ title: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return title }
        let range = NSRange(title.startIndex..., in: title)
        return regex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
    }
    
    private static func removeFromTitle(_ title: String, patterns: [String]) -> String {
        var result = title
        for pattern in patterns {
            result = removeFromTitle(result, pattern: pattern)
        }
        return result
    }
    
    private static func removeParenthesesContent(from title: String) -> String {
        var result = title
        let parenthesesPattern = #"\s*\([^)]*\)\s*"#
        if let regex = try? NSRegularExpression(pattern: parenthesesPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        
        let bracketsPattern = #"\s*\[[^\]]*\]\s*"#
        if let regex = try? NSRegularExpression(pattern: bracketsPattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: " ")
        }
        
        return result
    }
    
    private static func cleanTitle(_ title: String) -> String {
        var result = title
        
        result = result.replacingOccurrences(of: "_", with: " ")
        result = result.replacingOccurrences(of: ".", with: " ")
        result = result.replacingOccurrences(of: "-", with: " ")
        
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result
    }
}

extension TitleMetadata {
    var primaryBadge: String? {
        if let quality = quality { return quality }
        if let source = source { return source }
        return nil
    }
    
    var secondaryBadge: String? {
        if let codec = codec { return codec }
        if let source = source, quality != nil { return source }
        return nil
    }
    
    var qualityColor: String {
        guard let quality = quality?.lowercased() else { return "gray" }
        if quality.contains("4k") || quality.contains("2160") { return "purple" }
        if quality.contains("1080") { return "blue" }
        if quality.contains("720") { return "green" }
        return "gray"
    }
}
