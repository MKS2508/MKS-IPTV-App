import Foundation
struct DownloadItem: Identifiable {
    let id: UUID
    let vodID: String
    let title: String
    let type: MediaType
    var status: DownloadStatus
    var totalBytes: Int64 = 0
    var bytesDownloaded: Int64 = 0
    var progress: Double = 0
    var speed: Double = 0
    var eta: TimeInterval = 0
    var error: Error? = nil
    var metadataStatus: MetadataTaggingStatus = .pending
    var metadataResult: MetadataResult?
    var metadataCandidates: [ScoredMetadataResult] = []
    var filePath: String?
}

// MediaType enum is now defined in MediaProtocols.swift

enum DownloadStatus: Equatable {
    case notStarted
    case downloading
    case paused
    case completed
    case cancelled
    case failed // Remove associated Error value here
    
    static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.notStarted, .notStarted):
            return true
        case (.downloading, .downloading):
            return true
        case (.paused, .paused):
            return true
        case (.completed, .completed):
            return true
        case (.failed, .failed): // Adjust comparison for new failed case
            return true
        case (.cancelled, .cancelled):
            return true
        default:
            return false
        }
    }
}

extension DownloadStatus: CustomStringConvertible {
    var description: String {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .notStarted:
            return "Not Started"
        case .downloading:
            return "Downloading"
        case .paused:
            return "Paused"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
}
