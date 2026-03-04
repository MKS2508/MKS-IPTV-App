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
    public var segmenter: HLSSegmenter?

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    /// The most recent seek target time (source seconds).
    /// Used by TransmuxServer to decide whether to wait for sequential data
    /// instead of triggering a new seek for nearby segments.
    public var lastSeekTarget: Double? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSeekTarget
    }

    public func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
        segmenter?.stop()
    }

    /// Request the remux loop to seek the INPUT to a new time (non-blocking).
    /// The output context stays the same, so all moof+mdat remain compatible.
    public func requestSeek(to timeSeconds: Double) {
        lock.lock()
        _seekRequest = timeSeconds
        _lastSeekTarget = timeSeconds
        lock.unlock()
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
