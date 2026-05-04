//
//  EPGMatchingService.swift
//  mks-multiplatform-iptv
//
//  Matches EPG channels to LiveChannels using exact ID match
//  and fuzzy name matching via StringSimilarity.
//
//  NOTE: Multiple LiveChannels can map to the same EPG channel,
//  as mirrors (different quality/language/backup) are common in IPTV.
//

import Foundation
import IPTVCore

/// Actor that matches EPG channels to LiveChannels
/// Pass 1: Exact epgChannelId match
/// Pass 2: Normalized name matching with Levenshtein similarity
actor EPGMatchingService {

    // MARK: - Match Table

    /// Maps LiveChannel.streamId → EPGChannel.id
    /// Multiple LiveChannel IDs may point to the same EPG channel ID (mirrors/backups)
    private(set) var matchTable: [Int: String] = [:]

    /// Minimum similarity threshold for fuzzy name matching
    private let similarityThreshold: Double = 0.85

    // MARK: - Public API

    /// Build the match table between LiveChannels and EPG channels.
    /// Multiple LiveChannels (mirrors, different quality/language/backup streams)
    /// can map to the same EPG channel — this is intentional.
    ///
    /// Matching passes (in order, cheapest first):
    ///   Pass 1: Exact `epgChannelId` field match — O(1) per channel
    ///   Pass 2a: Exact normalized name match — O(n) per channel via Dictionary
    ///   Pass 2b: Fuzzy Levenshtein — only for channels that still have no match,
    ///            skips pairs whose length ratio would make similarity < threshold
    func buildMatchTable(liveChannels: [LiveChannel], epgChannels: [EPGChannel]) {
        matchTable = [:]

        // Build lookup: EPGChannel.id → EPGChannel (keep first on duplicate IDs)
        let epgById = Dictionary(epgChannels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Build lookup: normalized display name → EPGChannel.id as Dictionary for O(1) exact lookup
        var normalizedNameToEPGId: [String: String] = [:]
        // Also keep an array for fuzzy pass (dictionary has no ordering, but we need all pairs)
        var normalizedNamesForFuzzy: [(normalized: String, epgId: String)] = []

        for channel in epgChannels {
            for displayName in channel.displayNames {
                let normalized = normalizeChannelName(displayName)
                if normalizedNameToEPGId[normalized] == nil {
                    normalizedNameToEPGId[normalized] = channel.id
                }
                normalizedNamesForFuzzy.append((normalized, channel.id))
            }
        }

        // Channels that didn't match in pass 1 or 2a — these need expensive fuzzy matching
        var needsFuzzy: [(streamId: Int, normalizedName: String)] = []

        for liveChannel in liveChannels {
            // Pass 1: Exact epgChannelId match — O(1)
            if let epgId = liveChannel.epgChannelId, !epgId.isEmpty, epgById[epgId] != nil {
                matchTable[liveChannel.streamId] = epgId
                continue
            }

            // Pass 2a: Exact normalized name match — O(1) via Dictionary
            let normalizedLiveName = normalizeChannelName(liveChannel.name)
            if let epgId = normalizedNameToEPGId[normalizedLiveName] {
                matchTable[liveChannel.streamId] = epgId
                continue
            }

            // Defer to fuzzy pass
            needsFuzzy.append((liveChannel.streamId, normalizedLiveName))
        }

        // Pass 2b: Fuzzy Levenshtein — only for unmatched channels
        // Skip pairs where the length ratio makes similarity < threshold (fast pre-filter)
        if !needsFuzzy.isEmpty {
            for (streamId, normalizedLiveName) in needsFuzzy {
                var bestMatch: (epgId: String, similarity: Double)?
                let liveLen = normalizedLiveName.count
                guard liveLen > 0 else { continue }

                for (normalizedName, epgId) in normalizedNamesForFuzzy {
                    let epgLen = normalizedName.count
                    guard epgLen > 0 else { continue }

                    // Length ratio pre-filter: if ratio < threshold, Levenshtein can't reach it
                    let ratio = Double(min(liveLen, epgLen)) / Double(max(liveLen, epgLen))
                    guard ratio >= similarityThreshold else { continue }

                    let similarity = StringSimilarity.normalizedLevenshtein(normalizedLiveName, normalizedName)
                    if similarity >= similarityThreshold {
                        if bestMatch == nil || similarity > bestMatch!.similarity {
                            bestMatch = (epgId, similarity)
                            if similarity == 1.0 { break } // Perfect match — no need to continue
                        }
                    }
                }

                if let match = bestMatch {
                    matchTable[streamId] = match.epgId
                }
            }
        }

        MKSLog.live.debug("[EPGMatchingService] Matched \(matchTable.count)/\(liveChannels.count) channels to EPG data")
        let uniqueEPG = Set(matchTable.values)
        MKSLog.live.debug("[EPGMatchingService] Unique EPG channels matched: \(uniqueEPG.count)/\(epgChannels.count)")
    }

    /// Load a pre-built match table from cache without recomputing
    func loadCachedTable(_ table: [Int: String]) {
        matchTable = table
        MKSLog.live.debug("[EPGMatchingService] Loaded cached match table: \(table.count) entries")
    }

    /// Get the EPG channel ID for a live channel
    func epgChannelId(for liveChannelId: Int) -> String? {
        matchTable[liveChannelId]
    }

    // MARK: - Name Normalization

    /// Normalize a channel name for comparison.
    /// Removes HD/SD/FHD/UHD/720/1080/4K suffixes, brackets content, IPTV prefixes,
    /// and collapses whitespace.
    private func normalizeChannelName(_ name: String) -> String {
        var cleaned = name.lowercased()

        // Remove quality suffixes at end
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*(hd|sd|fhd|uhd|720|1080|4k)\s*$"#,
            with: "",
            options: .regularExpression
        )

        // Remove quality tags in the middle
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+(hd|sd|fhd|uhd|720p?|1080[pi]?|4k)\b"#,
            with: "",
            options: .regularExpression
        )

        // Remove bracketed content: [ESP], (Multi), [H.265], etc.
        cleaned = cleaned.replacingOccurrences(
            of: #"[\[\(][^\]\)]*[\]\)]"#,
            with: "",
            options: .regularExpression
        )

        // Remove common IPTV prefixes like "ES: ", "ES| ", country codes
        cleaned = cleaned.replacingOccurrences(
            of: #"^[a-z]{2}[\s:|\-]+\s*"#,
            with: "",
            options: .regularExpression
        )

        // Remove backup/mirror suffixes: "Backup", "BK", "S2", "FHD2"
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*(backup|bk|s\d+|fhd\d+|hd\d+)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Collapse whitespace and trim
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)

        return cleaned
    }
}
