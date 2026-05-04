import Foundation
import AVFoundation
import Combine
import IPTVCore

/// Identity of the content being tracked — everything needed to persist a watch history entry.
struct ContentIdentity {
    let profileId: UUID
    let contentType: String          // "movie" or "episode"
    let contentId: String            // String(movie.streamId) or episode.id
    let displayTitle: String
    let posterURL: String?
    let backdropURL: String?
    let seriesId: Int?
    let showTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeTitle: String?
    let containerExtension: String?
}

/// Information about the next episode to auto-play.
struct NextEpisodeInfo {
    let episode: SerieDetail.Episode
    let seriesId: Int
    let showTitle: String
    let posterURL: String?
}

/// Bridges `VideoPlayerProtocol` to `WatchHistoryManager`, persisting playback
/// position at regular intervals (~12s) and on lifecycle events.
///
/// Also detects episode completion for auto-play-next-episode.
@MainActor @Observable
final class PlaybackTracker {

    // MARK: - State

    /// Set when the current episode completes and a next episode is available.
    var nextEpisodeReady: NextEpisodeInfo?

    private(set) var isTracking = false

    // MARK: - Private

    private var content: ContentIdentity?
    private var cancellables = Set<AnyCancellable>()
    private var saveTimer: Task<Void, Never>?
    private var lastSavedPosition: Double = 0
    private weak var trackedPlayer: (any VideoPlayerProtocol)?
    private var hasCompletionFired = false

    /// Series detail for next-episode lookup (set externally for episode playback)
    var seriesDetail: SerieDetail?

    /// Minimum position change (seconds) to trigger a save
    private let minPositionDelta: Double = 2

    // MARK: - Tracking Lifecycle

    /// Begin tracking playback position for the given content.
    ///
    /// Subscribes to the player's `progressPublisher` and saves position
    /// to `WatchHistoryManager` every ~12 seconds (first save after 3s).
    func startTracking(player: any VideoPlayerProtocol, content: ContentIdentity) {
        stopTracking()

        self.content = content
        self.trackedPlayer = player
        self.isTracking = true
        self.nextEpisodeReady = nil
        self.lastSavedPosition = 0
        self.hasCompletionFired = false

        // Subscribe to progress updates for completion detection.
        // NOTE: progressPublisher emits currentTime in SECONDS, not a 0-1 ratio.
        player.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTimeSeconds in
                self?.handleProgressUpdate(currentTimeSeconds)
            }
            .store(in: &cancellables)

        // Periodic save timer: first save after 3s, then every 12s
        saveTimer = Task { [weak self] in
            // Early first save so short sessions still persist
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.saveCurrentPosition()

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard !Task.isCancelled else { break }
                await self?.saveCurrentPosition()
            }
        }

        // Listen for playback-did-finish notification (AVPlayer)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackFinished()
            }
            .store(in: &cancellables)

        MKSLog.player.debug("[PlaybackTracker] Started tracking: \(content.displayTitle)")
    }

    /// Stop tracking and save final position.
    func stopTracking() {
        guard isTracking else { return }

        saveTimer?.cancel()
        saveTimer = nil
        cancellables.removeAll()

        // Capture player state BEFORE clearing references.
        // The weak trackedPlayer is still alive here because the caller
        // (MediaDetailSheet.onChange) hasn't nil'd activePlayer yet.
        let capturedContent = content
        let capturedPosition = trackedPlayer?.currentTime ?? 0
        let capturedDuration = trackedPlayer?.duration ?? 0

        isTracking = false
        trackedPlayer = nil
        content = nil
        seriesDetail = nil
        nextEpisodeReady = nil

        MKSLog.player.debug("[PlaybackTracker] Stopped tracking (captured pos: \(String(format: "%.1f", capturedPosition))s)")

        // Save final position with captured values
        guard let content = capturedContent, capturedPosition > 1, capturedDuration > 0 else {
            if capturedPosition > 1 && capturedDuration <= 0 {
                MKSLog.player.debug("[PlaybackTracker] Skipping final save — duration unavailable")
            }
            return
        }
        let duration = capturedDuration
        Task {
            guard let manager = WatchHistoryManager.shared else { return }
            do {
                try await manager.savePosition(
                    profileId: content.profileId,
                    contentType: content.contentType,
                    contentId: content.contentId,
                    position: capturedPosition,
                    duration: duration,
                    displayTitle: content.displayTitle,
                    posterURL: content.posterURL,
                    backdropURL: content.backdropURL,
                    seriesId: content.seriesId,
                    showTitle: content.showTitle,
                    seasonNumber: content.seasonNumber,
                    episodeNumber: content.episodeNumber,
                    episodeTitle: content.episodeTitle,
                    containerExtension: content.containerExtension
                )
                MKSLog.player.debug("[PlaybackTracker] Final position saved: \(String(format: "%.1f", capturedPosition))s / \(String(format: "%.1f", duration))s")
            } catch {
                MKSLog.player.error("[PlaybackTracker] Final save failed: \(error)")
            }
        }
    }

    /// Immediate save — call on pause.
    func saveOnPause() {
        Task { await saveCurrentPosition() }
    }

    /// Immediate save — call when app enters background.
    func saveOnBackground() {
        Task { await saveCurrentPosition() }
    }

    // MARK: - Private: Progress Handling

    /// Called with currentTime in seconds from `progressPublisher`.
    private func handleProgressUpdate(_ currentTimeSeconds: Double) {
        guard !hasCompletionFired else { return }
        guard let player = trackedPlayer else { return }

        let duration = player.duration
        guard duration > 10 else { return } // Skip until duration is known and reasonable

        let progressRatio = currentTimeSeconds / duration
        if progressRatio > 0.95 {
            hasCompletionFired = true
            handlePlaybackFinished()
        }
    }

    private func handlePlaybackFinished() {
        guard let content, !content.contentId.isEmpty else { return }

        // Mark as completed
        Task {
            guard let manager = WatchHistoryManager.shared else { return }
            try? await manager.markCompleted(
                profileId: content.profileId,
                contentType: content.contentType,
                contentId: content.contentId
            )
        }

        // Check for next episode
        if content.contentType == "episode",
           let seriesId = content.seriesId,
           let detail = seriesDetail {
            if let nextEp = findNextEpisode(
                currentSeason: content.seasonNumber ?? 1,
                currentEpisode: content.episodeNumber ?? 1,
                serieDetail: detail
            ) {
                let posterURL = nextEp.info.movieImage.isEmpty ? content.posterURL : nextEp.info.movieImage
                nextEpisodeReady = NextEpisodeInfo(
                    episode: nextEp,
                    seriesId: seriesId,
                    showTitle: content.showTitle ?? content.displayTitle,
                    posterURL: posterURL
                )
                MKSLog.player.debug("[PlaybackTracker] Next episode ready: S\(nextEp.season)E\(nextEp.episodeNum) — \(nextEp.title)")
            }
        }
    }

    // MARK: - Private: Save Position

    private func saveCurrentPosition() async {
        guard let content, let player = trackedPlayer else { return }

        let position = player.currentTime
        let duration = player.duration

        // Skip if position hasn't changed significantly
        guard abs(position - lastSavedPosition) >= minPositionDelta else { return }
        // Skip if no meaningful playback yet
        guard position > 1 else { return }
        // Require real duration — transmux content may report 0 briefly during startup.
        // Saving with duration=0 would create entries with progress=1.0 (broken).
        guard duration > 0 else {
            MKSLog.player.debug("[PlaybackTracker] Skipping save — duration not yet available (pos: \(String(format: "%.1f", position))s)")
            return
        }

        lastSavedPosition = position

        guard let manager = WatchHistoryManager.shared else { return }
        do {
            try await manager.savePosition(
                profileId: content.profileId,
                contentType: content.contentType,
                contentId: content.contentId,
                position: position,
                duration: duration,
                displayTitle: content.displayTitle,
                posterURL: content.posterURL,
                backdropURL: content.backdropURL,
                seriesId: content.seriesId,
                showTitle: content.showTitle,
                seasonNumber: content.seasonNumber,
                episodeNumber: content.episodeNumber,
                episodeTitle: content.episodeTitle,
                containerExtension: content.containerExtension
            )
            let savedProgress = duration > 0 ? position / duration : 0
            MKSLog.player.debug("[PlaybackTracker] Saved position: \(String(format: "%.1f", position))s / \(String(format: "%.1f", duration))s (progress: \(String(format: "%.4f", savedProgress)))")
        } catch {
            MKSLog.player.error("[PlaybackTracker] Save failed: \(error)")
        }
    }

    // MARK: - Private: Next Episode Lookup

    private func findNextEpisode(
        currentSeason: Int,
        currentEpisode: Int,
        serieDetail: SerieDetail
    ) -> SerieDetail.Episode? {
        let seasonKey = String(currentSeason)

        // Try next episode in same season
        if let episodes = serieDetail.episodes[seasonKey] {
            let sorted = episodes.sorted { $0.episodeNum < $1.episodeNum }
            if let currentIdx = sorted.firstIndex(where: { $0.episodeNum == currentEpisode }),
               currentIdx + 1 < sorted.count {
                return sorted[currentIdx + 1]
            }
        }

        // Try first episode of next season
        let nextSeasonKey = String(currentSeason + 1)
        if let nextSeasonEpisodes = serieDetail.episodes[nextSeasonKey],
           let firstEpisode = nextSeasonEpisodes.sorted(by: { $0.episodeNum < $1.episodeNum }).first {
            return firstEpisode
        }

        return nil
    }
}
