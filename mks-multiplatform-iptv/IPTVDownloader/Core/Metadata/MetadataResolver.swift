import Foundation
import IPTVCore

/// Heuristic scoring engine that queries multiple ``MetadataProvider``s in parallel
/// and selects the best matching result.
///
/// Scoring factors (weighted):
/// 1. Exact TMDB ID match (50) — highest signal
/// 2. Title similarity via Levenshtein (25)
/// 3. Year match (10)
/// 4. Genre overlap (8)
/// 5. Runtime proximity (7)
actor MetadataResolver {
    private let providers: [any MetadataProvider]

    init(providers: [any MetadataProvider]) {
        self.providers = providers
    }

    /// Resolve the best metadata for a given query by querying all available
    /// providers in parallel and scoring the results.
    ///
    /// - Parameter query: Search parameters including title, year, tmdbId, etc.
    /// - Returns: The highest-scoring ``MetadataResult``, or `nil` if no results found.
    func resolve(query: MetadataSearchQuery) async -> MetadataResult? {
        let scored = await resolveAll(query: query)
        return scored.first?.result
    }

    /// Resolve all metadata candidates from all providers, scored and sorted.
    ///
    /// Returns every result from every available provider, each paired with its
    /// heuristic match score, sorted best-first. The UI can present these as
    /// selectable options for the user.
    ///
    /// - Parameter query: Search parameters
    /// - Returns: Array of scored results, sorted by score descending.
    func resolveAll(query: MetadataSearchQuery) async -> [ScoredMetadataResult] {
        let allResults = await withTaskGroup(
            of: [MetadataResult].self,
            returning: [MetadataResult].self
        ) { group in
            for provider in providers {
                group.addTask {
                    guard provider.isAvailable() else { return [] }
                    return (try? await provider.search(query: query)) ?? []
                }
            }

            var collected: [MetadataResult] = []
            for await results in group {
                collected.append(contentsOf: results)
            }
            return collected
        }

        guard !allResults.isEmpty else { return [] }

        return allResults.map { result in
            let score = computeScore(result: result, query: query)
            return ScoredMetadataResult(result: result, score: score)
        }
        .sorted { $0.score > $1.score }
    }

    // MARK: - Heuristic Scoring

    /// Compute a normalized score (0.0–1.0) for how well a result matches the query.
    ///
    /// Only factors with available query data contribute to the denominator,
    /// so missing fields don't penalize results.
    private func computeScore(result: MetadataResult, query: MetadataSearchQuery) -> Double {
        var score: Double = 0.0
        var maxScore: Double = 0.0

        // Factor 1: Exact TMDB ID match (weight: 50)
        maxScore += 50.0
        if let queryTmdbId = query.tmdbId,
           let resultTmdbId = result.tmdbId,
           queryTmdbId == resultTmdbId {
            score += 50.0
        }

        // Factor 2: Title similarity (weight: 25)
        maxScore += 25.0
        let cleanedQuery = StringSimilarity.cleanTitle(query.title).lowercased()
        let cleanedResult = StringSimilarity.cleanTitle(result.title).lowercased()
        let similarity = StringSimilarity.normalizedLevenshtein(cleanedQuery, cleanedResult)
        score += similarity * 25.0

        // Factor 3: Year match (weight: 10)
        if let queryYear = query.year ?? StringSimilarity.extractYear(from: query.title) {
            maxScore += 10.0
            if let resultYear = result.year {
                if queryYear == resultYear {
                    score += 10.0
                } else if abs(queryYear - resultYear) == 1 {
                    // Off by one year is common for international releases
                    score += 5.0
                }
            }
        }

        // Factor 4: Genre overlap (weight: 8)
        if let queryGenre = query.genre, !queryGenre.isEmpty {
            maxScore += 8.0
            let queryGenres = Set(
                queryGenre.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            )
            let resultGenres = Set(result.genre.map { $0.lowercased() })
            let overlap = queryGenres.intersection(resultGenres)
            if !queryGenres.isEmpty {
                let genreScore = Double(overlap.count) / Double(queryGenres.count)
                score += genreScore * 8.0
            }
        }

        // Factor 5: Runtime match within tolerance (weight: 7)
        if let queryRuntime = query.runtimeMinutes, queryRuntime > 0 {
            maxScore += 7.0
            if let resultRuntime = result.runtimeMinutes, resultRuntime > 0 {
                let diff = abs(queryRuntime - resultRuntime)
                if diff <= 2 {
                    score += 7.0
                } else if diff <= 5 {
                    score += 5.0
                } else if diff <= 15 {
                    score += 2.0
                }
            }
        }

        return maxScore > 0 ? score / maxScore : 0.0
    }
}
