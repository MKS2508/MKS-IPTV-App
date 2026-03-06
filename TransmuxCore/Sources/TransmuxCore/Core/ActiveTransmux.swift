import Foundation

// MARK: - Active Transmux Handle

/// Thread-safe cancellation and seek handle for an in-progress transmux.
/// The seek signal allows TransmuxServer to redirect the sequential transmux
/// to a new input position without creating a separate FFmpeg output context.
public class ActiveTransmux {
    private let lock = NSLock()
    private var _cancelled = false
    private var _seekRequest: Double? = nil
    private var _lastSeekTarget: Double?
    private var _seekGeneration: UInt64 = 0
    private var _isTransmuxComplete = false
    private var _cooldownSeconds: TimeInterval = 0.8
    private let _seekDataSemaphore = DispatchSemaphore(value: 0)
    private var _aggressiveFlushRequested = false
    private var _playbackPosition: Double = 0
    public var segmenter: HLSSegmenter?

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    /// Whether the remux loop has finished (EOF or error).
    /// Checked by TransmuxServer polling loop to detect completion during wait.
    public var isTransmuxComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isTransmuxComplete
    }

    /// Mark the transmux as complete. Called by TransmuxingService after the
    /// remux loop ends. This is a live flag (unlike the snapshot `isComplete`
    /// captured at dispatch time in TransmuxServer).
    public func markTransmuxComplete() {
        lock.lock()
        _isTransmuxComplete = true
        lock.unlock()
    }

    /// Monotonic seek generation counter. Incremented on every requestSeek().
    /// Used by TransmuxServer polling loops to detect stale requests: if
    /// seekGeneration has advanced past the snapshot taken at dispatch time,
    /// the segment request belongs to an old seek and should be aborted (404).
    public var seekGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return _seekGeneration
    }

    /// The most recent seek target time (source seconds).
    /// Used by TransmuxServer to decide whether to wait for sequential data
    /// instead of triggering a new seek for nearby segments.
    public var lastSeekTarget: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSeekTarget
    }

    /// Adaptive seek cooldown in seconds. Starts at 0.8s (was fixed 2.0s).
    /// Adjusted after each seek based on how clean it was — clean seeks
    /// lower the cooldown (faster seeking), messy seeks raise it (stability).
    public var cooldownSeconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return _cooldownSeconds
    }

    /// Adjust the seek cooldown based on seek quality.
    /// - Parameter seekWasClean: true if the seek completed with < 20 skipped packets.
    public func adjustCooldown(seekWasClean: Bool) {
        lock.lock()
        if seekWasClean {
            _cooldownSeconds = max(0.3, _cooldownSeconds * 0.8)
        } else {
            _cooldownSeconds = min(2.0, _cooldownSeconds * 1.5)
        }
        let current = _cooldownSeconds
        lock.unlock()
        TransmuxLog.log("COOLDOWN adjusted to \(String(format: "%.2f", current))s (clean=\(seekWasClean))", tag: "Seek")
    }

    // MARK: - Aggressive Flush

    /// Whether an aggressive flush has been requested by the player layer.
    /// Auto-resets on read so the remux loop only acts once per request.
    public var aggressiveFlushRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        let val = _aggressiveFlushRequested
        _aggressiveFlushRequested = false
        return val
    }

    /// Request the remux loop to switch to aggressive AVIO flushing.
    /// Called by the GlitchDetector feedback loop on buffer starvation.
    public func requestAggressiveFlush() {
        lock.lock()
        _aggressiveFlushRequested = true
        lock.unlock()
        TransmuxLog.log("AGGRESSIVE-FLUSH requested by player", tag: "Feedback")
    }

    // MARK: - Seek Data Ready Signaling

    /// Signal that post-seek data is available for serving.
    /// Called by the remux loop after seekPending=false and first post-seek
    /// packets are written. Wakes up TransmuxServer's polling loop immediately
    /// instead of waiting for the next Thread.sleep interval.
    public func signalSeekDataReady() {
        _seekDataSemaphore.signal()
    }

    /// Wait for post-seek data with timeout.
    /// Returns true if signaled (data ready), false if timed out.
    public func waitForSeekData(timeout: TimeInterval) -> Bool {
        _seekDataSemaphore.wait(timeout: .now() + timeout) == .success
    }

    /// Drain any stale signals from previous seeks.
    private func resetSeekSignal() {
        while _seekDataSemaphore.wait(timeout: .now()) == .success {}
    }

    // MARK: - Backpressure

    /// Current playback position (source time in seconds).
    /// Updated by FFmpegPlayerImplementation from its $currentTime publisher.
    /// Used by the remux loop to throttle production when too far ahead.
    public var currentPlaybackPosition: Double {
        lock.lock()
        defer { lock.unlock() }
        return _playbackPosition
    }

    /// Update the playback position. Called by the player layer every ~2 seconds.
    public func updatePlaybackPosition(_ time: Double) {
        lock.lock()
        _playbackPosition = time
        lock.unlock()
    }

    /// Check if a seek request is pending without consuming it.
    /// Used by backpressure throttle to wake without losing the request.
    public var hasSeekPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _seekRequest != nil
    }

    public func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
        // Wake any waiting polling loops so they can exit
        _seekDataSemaphore.signal()
        segmenter?.stop()
    }

    /// Request the remux loop to seek the INPUT to a new time (non-blocking).
    /// The output context stays the same, so all moof+mdat remain compatible.
    public func requestSeek(to timeSeconds: Double) {
        lock.lock()
        _seekGeneration += 1
        _seekRequest = timeSeconds
        _lastSeekTarget = timeSeconds
        lock.unlock()
        resetSeekSignal()  // Clear stale signals from previous seek
        TransmuxLog.log("SEEK-REQUEST \u{2192} \(String(format: "%.1f", timeSeconds))s", tag: "Server")
    }

    /// Consume a pending seek request (called by the remux loop).
    /// Returns the requested time in seconds, or nil if no seek is pending.
    public func consumeSeekRequest() -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let req = _seekRequest else { return nil }
        _seekRequest = nil
        return req
    }
}
