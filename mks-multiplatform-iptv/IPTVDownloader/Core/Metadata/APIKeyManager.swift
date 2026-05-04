import Foundation
import IPTVCore

/// Centralized storage for external API keys used by metadata providers.
///
/// Keys are bundled as app constants (read-only API keys, not user secrets).
/// TMDB v3 API keys are free-tier and intended for client-side usage.
enum APIKeys {
    /// TMDB API v3 read-only key.
    /// Register at https://www.themoviedb.org/settings/api to get your own.
    static let tmdb: String = "2825e3f7b4b9c3192e7e71b1d8043fed"

    /// TMDB API v4 Bearer token (for read access).
    static let tmdbAccessToken: String = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiIyODI1ZTNmN2I0YjljMzE5MmU3ZTcxYjFkODA0M2ZlZCIsIm5iZiI6MTc2Mzc3MzM0Ni43NTUsInN1YiI6IjY5MjEwYmEyN2Q5NGQwNWE5ZTMyOWYwNSIsInNjb3BlcyI6WyJhcGlfcmVhZCJdLCJ2ZXJzaW9uIjoxfQ.VTxJc9QetA1HxIAK6Xa604nN5mLnJhjQGxVk_YtoIx0"

    /// TheTVDB API v4 key.
    /// Register at https://thetvdb.com/api-information to get your own.
    static let tvdb: String = "22b2fbcc-82ec-4d7e-88d2-9b357f46aabf"

    /// iTunes Search API does not require an API key.
}
