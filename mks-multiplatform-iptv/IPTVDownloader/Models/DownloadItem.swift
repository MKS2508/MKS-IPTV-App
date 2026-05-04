import Foundation
import IPTVCore

struct DownloadItem: Identifiable, Codable {
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
    var errorMessage: String? = nil
    var metadataStatus: MetadataTaggingStatus = .pending
    var metadataResult: MetadataResult?
    var metadataCandidates: [ScoredMetadataResult] = []
    var filePath: String?

    /// Output container format for the download
    var outputFormat: VideoDownloader.OutputFormat = .mp4

    /// Whether play-while-downloading is enabled
    var playWhileDownloading: Bool = false

    /// Whether to save the downloaded video to the Photos library (iOS only)
    var saveToPhotos: Bool = false

    /// Source file extension from the IPTV server (e.g. "mkv", "mp4")
    var sourceExtension: String?

    /// Date the download was started
    var dateStarted: Date = Date()

    /// Transmux session ID (nil for direct HTTP downloads)
    var transmuxSessionID: String?

    /// URL string for resuming downloads
    var sourceURLString: String?

    /// Download path for persistence
    var downloadPath: String?

    // MARK: - Backward Compat

    /// Computed error property for backward compatibility with code that uses Error?
    var error: Error? {
        get { errorMessage.map { NSError(domain: "DownloadItem", code: -1, userInfo: [NSLocalizedDescriptionKey: $0]) } }
        set { errorMessage = newValue?.localizedDescription }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, vodID, title, type, status
        case totalBytes, bytesDownloaded, progress, speed, eta
        case errorMessage, metadataStatus, metadataResult, metadataCandidates
        case filePath, outputFormat, playWhileDownloading, saveToPhotos
        case sourceExtension, dateStarted, transmuxSessionID
        case sourceURLString, downloadPath
    }
}

// MediaType enum is now defined in MediaProtocols.swift

enum DownloadStatus: String, Codable, Equatable {
    case notStarted
    case downloading
    case paused
    case downloaded   // Raw file download complete, may need conversion
    case converting   // Post-download transmux in progress
    case completed    // Fully done (download + optional conversion)
    case cancelled
    case failed
}

extension DownloadStatus: CustomStringConvertible {
    var description: String {
        switch self {
        case .cancelled: return "Cancelled"
        case .notStarted: return "Not Started"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .downloaded: return "Downloaded"
        case .converting: return "Converting"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}
