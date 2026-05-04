import Foundation
import IPTVCore

/// String similarity utilities for metadata matching heuristics
enum StringSimilarity {

    /// Compute the Levenshtein edit distance between two strings
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Chars = Array(s1)
        let s2Chars = Array(s2)
        let m = s1Chars.count
        let n = s2Chars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0...n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = s1Chars[i - 1] == s2Chars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    /// Normalized Levenshtein similarity (0.0 = completely different, 1.0 = identical)
    static func normalizedLevenshtein(_ s1: String, _ s2: String) -> Double {
        let maxLen = max(s1.count, s2.count)
        guard maxLen > 0 else { return 1.0 }
        let distance = levenshteinDistance(s1, s2)
        return 1.0 - (Double(distance) / Double(maxLen))
    }

    /// Clean an IPTV title for comparison.
    ///
    /// Removes year suffixes, quality tags, codec info, brackets, and collapses whitespace.
    /// Example: `"Inception (2010) 1080p [Multi-Audio] BDRip"` → `"Inception"`
    static func cleanTitle(_ title: String) -> String {
        var cleaned = title

        // Remove year in parentheses: "Movie (2024)" -> "Movie"
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*\(\d{4}\)\s*"#, with: " ",
            options: .regularExpression
        )

        // Remove quality tags: "1080p", "720p", "4K", "HDR"
        cleaned = cleaned.replacingOccurrences(
            of: #"\b\d{3,4}[pPiI]\b"#, with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\b(4K|HDR|HDR10|DV|REMUX|BluRay|BDRip|WEB-DL|WEBRip|BRRip|HDTV|DVDRip|CAM|TS|TC|SCR|R5|PPVRip)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove codec/audio tags
        cleaned = cleaned.replacingOccurrences(
            of: #"\b(H\.?264|H\.?265|HEVC|x264|x265|AAC|AC3|DTS|FLAC|MP3|Atmos|TrueHD|DD5\.1|EAC3|dual|multi|subs?)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remove bracketed/parenthesized content: "[ESP]", "(Dual)", "[Multi-Audio]"
        cleaned = cleaned.replacingOccurrences(
            of: #"[\[\(][^\]\)]*[\]\)]"#, with: "",
            options: .regularExpression
        )

        // Remove trailing dots, hyphens, underscores used as separators
        cleaned = cleaned.replacingOccurrences(
            of: #"[._]"#, with: " ",
            options: .regularExpression
        )

        // Collapse whitespace and trim
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#, with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        return cleaned
    }

    /// Extract a 4-digit year from a title string, if present.
    /// Looks for patterns like "(2024)" or just "2024" at word boundaries.
    static func extractYear(from title: String) -> Int? {
        // Try parenthesized year first: "(2024)"
        if let match = title.firstMatch(of: /\((\d{4})\)/) {
            return Int(match.1)
        }
        // Fallback: standalone 4-digit year between 1900-2099
        if let match = title.firstMatch(of: /\b(19\d{2}|20\d{2})\b/) {
            return Int(match.1)
        }
        return nil
    }
}
