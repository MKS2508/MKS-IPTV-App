import IPTVCore
//
//  DownloadLiveActivityManager.swift
//  mks-multiplatform-iptv
//
//  Manages Live Activities for iOS Dynamic Island downloads.
//

#if os(iOS)
import ActivityKit
import Foundation
import IPTVCore

/// Manages Live Activities for iOS Dynamic Island downloads.
/// Uses ActivityKit framework for tracking download progress.
@available(iOS 16.2, *)
final class DownloadLiveActivityManager: Observable {

    // MARK: - Singleton

    static let shared = DownloadLiveActivityManager()

    // MARK: - Private Properties

    private var activities: [String: Activity<DownloadActivityAttributes>] = [:]

    // MARK: - Lifecycle

    private init() {}

    // MARK: - Start Live Activity

    /// Start a new Live Activity for a download.
    func startActivity(
                downloadId: String,
                title: String,
                mediaType: String,
                progress: Double = 0,
                speed: Double = 0,
                eta: TimeInterval = 0,
                bytesDownloaded: Int64 = 0,
                totalBytes: Int64 = 0,
                status: String = "Downloading"
    ) {
        let attributes = DownloadActivityAttributes(
            title: title,
            mediaType: mediaType,
            downloadId: downloadId
        )

        let initialState = DownloadActivityAttributes.ContentState(
            progress: progress,
            speed: speed,
            eta: eta,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            status: status
        )

        do {
            let activity = try Activity<DownloadActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            activities[downloadId] = activity
        } catch {
            // Failed to start activity
        }
    }

    // MARK: - Update Live Activity

    /// Update an existing Live Activity with new progress.
    func updateActivity(
                for downloadId: String,
                progress: Double,
                speed: Double,
                eta: TimeInterval,
                bytesDownloaded: Int64,
                totalBytes: Int64,
                status: String
    ) {
        guard let activity = activities[downloadId] else { return }

        let updatedState = DownloadActivityAttributes.ContentState(
            progress: progress,
            speed: speed,
            eta: eta,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            status: status
        )

        Task {
            await activity.update(using: updatedState)
        }
    }

    // MARK: - End Live Activity

    /// End a Live Activity when download completes or is cancelled.
    func endActivity(for downloadId: String, status: String = "Completed") {
        guard let activity = activities[downloadId] else { return }

        let finalState = DownloadActivityAttributes.ContentState(
            progress: 100.0,
            speed: 0,
            eta: 0,
            bytesDownloaded: 0,
            totalBytes: 0,
            status: status
        )

        Task {
            await activity.end(using: finalState, dismissalPolicy: .default)
        }

        activities.removeValue(forKey: downloadId)
    }
}

#endif
