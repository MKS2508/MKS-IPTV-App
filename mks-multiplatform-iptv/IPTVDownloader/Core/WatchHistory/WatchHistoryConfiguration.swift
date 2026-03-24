import Foundation
import SwiftData

/// Creates and configures the SwiftData ModelContainer for watch history persistence.
///
/// When iCloud sync is available, uses `cloudKitDatabase: .automatic` so SwiftData
/// transparently mirrors the local store to the user's private CloudKit database.
/// Falls back to local-only storage if CloudKit migration fails (e.g. schema conflicts
/// on first upgrade from a non-CloudKit store).
enum WatchHistoryConfiguration {

    /// Creates a ModelContainer for `WatchHistoryEntry` and `RecentChannelEntry`.
    ///
    /// Attempts CloudKit-backed storage first (`cloudKitDatabase: .automatic`).
    /// If the migration to a CloudKit-compatible store fails, falls back to
    /// local-only storage so the app never crashes on launch.
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
            WatchHistoryEntry.self,
            RecentChannelEntry.self
        ])

        // Try CloudKit-backed store first
        do {
            let cloudConfig = ModelConfiguration(
                "WatchHistory",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            MKSLog.app.warning("[WatchHistory] CloudKit store failed, falling back to local: \(error)")
            let localConfig = ModelConfiguration(
                "WatchHistory",
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [localConfig])
        }
    }
}
