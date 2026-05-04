import Foundation
import SwiftData
import IPTVCore

/// Creates and configures the SwiftData ModelContainer for watch history persistence.
///
/// Uses local-only storage (`cloudKitDatabase: .none`).
///
/// CloudKit sync (`cloudKitDatabase: .automatic`) was previously enabled but caused
/// sustained 90-100% CPU usage: `NSCloudKitMirroringDelegate remoteStoreDidChange:`
/// triggered a continuous import storm (`PFCloudKitImportRecordsWorkItem`) that
/// saturated background GCD queues. Instruments Time Profiler confirmed 100% of CPU
/// samples were in CoreData/CloudKit plumbing with zero app code visible.
///
/// Watch history is per-device data (resume positions, recently watched) and does not
/// require cross-device sync. Local storage is sufficient and eliminates the CPU issue.
enum WatchHistoryConfiguration {

    /// Creates a ModelContainer for `WatchHistoryEntry` and `RecentChannelEntry`.
    ///
    /// Uses local-only storage to avoid CloudKit sync CPU overhead.
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
            WatchHistoryEntry.self,
            RecentChannelEntry.self
        ])

        let localConfig = ModelConfiguration(
            "WatchHistory",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [localConfig])
    }
}
