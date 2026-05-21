//
//  ServerDownloadManager.swift
//  mksiptv-server
//
//  Actor-based download manager with transmuxing support.
//

import Foundation
import Vapor
import IPTVCore
import TransmuxCore

// MARK: - Download Manager

/// Actor that manages active download operations with thread-safe access
public actor ServerDownloadManager {
    // MARK: - Properties

    /// Active downloads indexed by UUID
    private var downloads: [UUID: DownloadItem] = [:]

    /// Event bus for publishing download events
    private let eventBus: EventBus

    /// Download directory path
    private let downloadDirectory: URL

    /// Transmuxing service integration
    private let transmuxingService: TransmuxingService

    // MARK: - Initialization

    public init(eventBus: EventBus, downloadPath: String? = nil) {
        self.eventBus = eventBus

        // Use configured download path or default
        if let path = downloadPath {
            self.downloadDirectory = URL(fileURLWithPath: path)
        } else {
            // Default to ~/Downloads/MKSIPTV
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            self.downloadDirectory = downloadsDir.appendingPathComponent("MKSIPTV")
        }

        // Create download directory if needed
        try? FileManager.default.createDirectory(at: self.downloadDirectory, withIntermediateDirectories: true)

        // Initialize transmuxing service
        self.transmuxingService = TransmuxingService.shared

        MKSLog.server.info("ServerDownloadManager initialized with download directory: \(self.downloadDirectory.path)")
    }

    // MARK: - Public API

    /// List all downloads
    public func listDownloads() -> [DownloadItem] {
        return Array(downloads.values)
    }

    /// Get a specific download by ID
    public func getDownload(id: UUID) -> DownloadItem? {
        return downloads[id]
    }

    /// Initiate a new download
    public func initiateDownload(
        contentType: MediaType,
        contentId: Int,
        title: String,
        streamURL: URL,
        outputFormat: String = "mp4"
    ) async throws -> DownloadItem {
        // Check if content is already being downloaded
        if downloads.values.contains(where: { $0.contentId == contentId && $0.contentType == contentType && [.queued, .downloading, .transmuxing].contains($0.status) }) {
            throw Abort(.conflict, reason: "Content is already being downloaded")
        }

        // Create new download item
        let item = DownloadItem(
            contentType: contentType,
            contentId: contentId,
            title: title,
            status: .queued,
            outputFormat: outputFormat,
            phase: "queued"
        )

        downloads[item.id] = item

        MKSLog.server.info("Download initiated: \(title) (\(contentType.rawValue) \(contentId))")

        // Publish event
        await publishDownloadEvent(item)

        // Start download in background
        Task.detached {
            await self.startDownload(item: item, streamURL: streamURL)
        }

        return item
    }

    /// Cancel a download
    public func cancelDownload(id: UUID) async throws {
        guard var item = downloads[id] else {
            throw Abort(.notFound, reason: "Download not found")
        }

        guard [.queued, .downloading, .transmuxing].contains(item.status) else {
            throw Abort(.badRequest, reason: "Cannot cancel download in status \(item.status.rawValue)")
        }

        item.status = .cancelled
        item.completedAt = Date()
        downloads[id] = item

        MKSLog.server.info("Download cancelled: \(item.title)")

        // Publish event
        await publishDownloadEvent(item)

        // Cleanup partial files
        if let filePath = item.filePath {
            try? FileManager.default.removeItem(atPath: filePath)
        }
    }

    /// Pause a download
    public func pauseDownload(id: UUID) async throws -> DownloadItem {
        guard var item = downloads[id] else {
            throw Abort(.notFound, reason: "Download not found")
        }

        guard item.status == .downloading else {
            throw Abort(.badRequest, reason: "Cannot pause download in status \(item.status.rawValue)")
        }

        item.status = .paused
        downloads[id] = item

        MKSLog.server.info("Download paused: \(item.title)")

        await publishDownloadEvent(item)

        return item
    }

    /// Resume a paused download
    public func resumeDownload(id: UUID) async throws -> DownloadItem {
        guard var item = downloads[id] else {
            throw Abort(.notFound, reason: "Download not found")
        }

        guard item.status == .paused else {
            throw Abort(.badRequest, reason: "Cannot resume download in status \(item.status.rawValue)")
        }

        item.status = .queued
        item.phase = "queued"
        downloads[id] = item

        MKSLog.server.info("Download resumed: \(item.title)")

        await publishDownloadEvent(item)

        // Resume download in background (would need stream URL, simplified here)
        Task.detached {
            // In a real implementation, we'd need to track the original stream URL
            // and resume from the last byte downloaded
        }

        return item
    }

    // MARK: - Private Methods

    /// Start the actual download process
    private func startDownload(item: DownloadItem, streamURL: URL) async {
        // Update status to downloading
        var mutableItem = item
        mutableItem.status = .downloading
        mutableItem.phase = "downloading"
        downloads[item.id] = mutableItem

        await publishDownloadEvent(mutableItem)

        do {
            // Get stream URL and start transmuxing
            // This is a simplified version - in production we'd use RawHTTPClient
            // to download the stream and TransmuxingService to convert it

            let session = try await transmuxingService.startTransmux(from: streamURL)

            mutableItem.phase = "transmuxing"
            mutableItem.status = .transmuxing
            downloads[item.id] = mutableItem

            await publishDownloadEvent(mutableItem)

            // Monitor progress (simplified - real implementation would track bytes)
            mutableItem.progress = 1.0
            mutableItem.bytesDownloaded = 100_000_000 // Placeholder
            mutableItem.totalBytes = 100_000_000

            // Wait for completion (transmuxing runs in background)
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds placeholder

            mutableItem.status = .completed
            mutableItem.completedAt = Date()
            mutableItem.filePath = session.outputPath
            downloads[item.id] = mutableItem

            MKSLog.server.info("Download completed: \(mutableItem.title)")

            await publishDownloadEvent(mutableItem)

        } catch {
            mutableItem.status = .failed
            mutableItem.error = error.localizedDescription
            mutableItem.completedAt = Date()
            downloads[item.id] = mutableItem

            MKSLog.server.error("Download failed: \(mutableItem.title) - \(error.localizedDescription)")

            await publishDownloadEvent(mutableItem)
        }
    }

    /// Publish download event to WebSocket clients
    private func publishDownloadEvent(_ item: DownloadItem) async {
        let eventData: [String: Any] = [
            "type": "download",
            "action": "status_change",
            "data": [
                "id": item.id.uuidString,
                "status": item.status.rawValue,
                "progress": item.progress,
                "contentType": item.contentType.rawValue,
                "contentId": item.contentId,
                "title": item.title
            ]
        ]

        let anyCodable = AnyCodable(eventData)
        await eventBus.publish(channel: .downloads, data: anyCodable)
        MKSLog.server.debug("Download event published: \(item.id.uuidString) - \(item.status.rawValue)")
    }
}
