//
//  DownloadModels.swift
//  mksiptv-server
//
//  Download management models for API requests and responses.
//

import Vapor
import IPTVCore

// NOTE: DownloadStatus and MediaType are already defined in WSModels.swift
// Reusing those definitions to avoid conflicts

// MARK: - Download Response

/// Full download item response with all metadata
public struct DownloadResponse: Content {
    public let id: UUID
    public let contentType: MediaType
    public let contentId: Int
    public let title: String
    public let status: DownloadStatus
    public let progress: Double
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let speed: Double?
    public let eta: TimeInterval?
    public let outputFormat: String
    public let filePath: String?
    public let error: String?
    public let startedAt: Date
    public let completedAt: Date?

    public init(
        id: UUID,
        contentType: MediaType,
        contentId: Int,
        title: String,
        status: DownloadStatus,
        progress: Double,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        speed: Double?,
        eta: TimeInterval?,
        outputFormat: String,
        filePath: String?,
        error: String?,
        startedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.contentType = contentType
        self.contentId = contentId
        self.title = title
        self.status = status
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.speed = speed
        self.eta = eta
        self.outputFormat = outputFormat
        self.filePath = filePath
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

// MARK: - Initiate Download Request

/// Request body to initiate a new download
public struct InitiateDownloadRequest: Content {
    /// Type of content to download
    public let contentType: MediaType

    /// ID of the content (movie ID or episode ID)
    public let contentId: Int

    /// Optional output format (default: "mp4")
    public let outputFormat: String?

    public init(contentType: MediaType, contentId: Int, outputFormat: String? = nil) {
        self.contentType = contentType
        self.contentId = contentId
        self.outputFormat = outputFormat
    }
}

// MARK: - Download Progress Response

/// Detailed progress information for a download
public struct DownloadProgressResponse: Content {
    public let id: UUID
    public let status: DownloadStatus
    public let progress: Double
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let speed: Double
    public let eta: TimeInterval
    public let phase: String

    public init(
        id: UUID,
        status: DownloadStatus,
        progress: Double,
        bytesDownloaded: Int64,
        totalBytes: Int64,
        speed: Double,
        eta: TimeInterval,
        phase: String
    ) {
        self.id = id
        self.status = status
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.speed = speed
        self.eta = eta
        self.phase = phase
    }
}

// MARK: - Download Error Response

/// Standard error response for download operations
public struct DownloadErrorResponse: Content {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - Download Item (Internal)

/// Internal download item managed by ServerDownloadManager
public struct DownloadItem: Sendable {
    public let id: UUID
    public let contentType: MediaType
    public let contentId: Int
    public let title: String
    public var status: DownloadStatus
    public var progress: Double
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public var speed: Double?
    public var eta: TimeInterval?
    public let outputFormat: String
    public var filePath: String?
    public var error: String?
    public let startedAt: Date
    public var completedAt: Date?
    public var phase: String

    public init(
        id: UUID = UUID(),
        contentType: MediaType,
        contentId: Int,
        title: String,
        status: DownloadStatus = .queued,
        progress: Double = 0.0,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        speed: Double? = nil,
        eta: TimeInterval? = nil,
        outputFormat: String = "mp4",
        filePath: String? = nil,
        error: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        phase: String = "queued"
    ) {
        self.id = id
        self.contentType = contentType
        self.contentId = contentId
        self.title = title
        self.status = status
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.speed = speed
        self.eta = eta
        self.outputFormat = outputFormat
        self.filePath = filePath
        self.error = error
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.phase = phase
    }

    /// Convert to API response
    public func toResponse() -> DownloadResponse {
        DownloadResponse(
            id: id,
            contentType: contentType,
            contentId: contentId,
            title: title,
            status: status,
            progress: progress,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            speed: speed,
            eta: eta,
            outputFormat: outputFormat,
            filePath: filePath,
            error: error,
            startedAt: startedAt,
            completedAt: completedAt
        )
    }

    /// Convert to progress response
    public func toProgressResponse() -> DownloadProgressResponse {
        DownloadProgressResponse(
            id: id,
            status: status,
            progress: progress,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            speed: speed ?? 0.0,
            eta: eta ?? 0.0,
            phase: phase
        )
    }
}
