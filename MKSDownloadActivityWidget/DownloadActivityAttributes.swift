#if os(iOS)
import ActivityKit
import Foundation

struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double       // 0-100
        var speed: Double          // MB/s
        var eta: TimeInterval
        var bytesDownloaded: Int64
        var totalBytes: Int64
        var status: String         // "Downloading", "Paused", "Converting", "Completed", "Failed"
    }

    var title: String
    var mediaType: String          // "Movie" or "Series"
    var downloadId: String         // UUID string for identification
}
#endif
