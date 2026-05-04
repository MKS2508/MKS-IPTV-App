import Foundation
import UserNotifications
import os
import IPTVCore

final class DownloadNotificationService {
    static let shared = DownloadNotificationService()

    private let logger = Logger(subsystem: "com.mks.iptv", category: "DownloadNotifications")
    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission: \(granted ? "granted" : "denied")")
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error)")
            return false
        }
    }

    // MARK: - Download Progress (Updating Notification)

    /// Update (or create) a progress notification for a download.
    /// Uses the download ID as the notification identifier so repeated calls replace the previous notification.
    func updateProgress(
        downloadId: UUID,
        title: String,
        progress: Double,
        speed: Double,
        eta: TimeInterval,
        bytesDownloaded: Int64,
        totalBytes: Int64
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Downloading"
        content.categoryIdentifier = "DOWNLOAD_PROGRESS"

        // Format the progress body
        let progressPercent = String(format: "%.0f%%", progress)
        let speedText = speed > 0 ? String(format: "%.1f MB/s", speed) : ""
        let etaText = formatETA(eta)

        let sizeText: String
        if totalBytes > 0 {
            sizeText = "\(formatBytes(bytesDownloaded)) / \(formatBytes(totalBytes))"
        } else if bytesDownloaded > 0 {
            sizeText = formatBytes(bytesDownloaded)
        } else {
            sizeText = ""
        }

        var parts = [title, progressPercent]
        if !sizeText.isEmpty { parts.append(sizeText) }
        if !speedText.isEmpty { parts.append(speedText) }
        if !etaText.isEmpty { parts.append(etaText) }

        content.body = parts.joined(separator: " — ")
        content.sound = nil // Silent updates

        // Thread identifier groups all download notifications
        content.threadIdentifier = "downloads"

        let request = UNNotificationRequest(
            identifier: "download-\(downloadId.uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to update progress notification: \(error)")
            }
        }
    }

    // MARK: - Download Complete

    func notifyDownloadComplete(downloadId: UUID, title: String, fileSize: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = "\(title) — \(formatBytes(fileSize))"
        content.sound = .default
        content.categoryIdentifier = "DOWNLOAD_COMPLETE"
        content.threadIdentifier = "downloads"

        let request = UNNotificationRequest(
            identifier: "download-\(downloadId.uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send completion notification: \(error)")
            }
        }
    }

    // MARK: - Download Failed

    func notifyDownloadFailed(downloadId: UUID, title: String, errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Failed"
        content.body = "\(title) — \(errorMessage)"
        content.sound = .default
        content.categoryIdentifier = "DOWNLOAD_FAILED"
        content.threadIdentifier = "downloads"

        let request = UNNotificationRequest(
            identifier: "download-\(downloadId.uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send failure notification: \(error)")
            }
        }
    }

    // MARK: - Remove Notification

    func removeNotification(downloadId: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: ["download-\(downloadId.uuidString)"])
        center.removePendingNotificationRequests(withIdentifiers: ["download-\(downloadId.uuidString)"])
    }

    // MARK: - Formatters

    private func formatETA(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
