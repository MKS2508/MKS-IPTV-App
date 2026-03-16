import Foundation

// MARK: - Active Live Transmux Handle

/// Thread-safe handle for a live MPEG-TS transmux session.
///
/// Simpler than `ActiveTransmux` — no seek support (live streams don't seek).
/// Designed for future extension with timeshift seek when DVR is implemented.
///
/// Provides:
/// - **Cancellation**: Stops the remux loop and releases the upstream connection.
/// - **Health monitoring**: Tracks last segment write time to detect stalls.
/// - **Reconnect tracking**: Counts consecutive reconnect attempts for escalation.
///
/// All properties use NSLock for thread-safe access from the remux loop
/// (DispatchQueue.global), TransmuxServer (actor), and the UI layer.
public class ActiveLiveTransmux: @unchecked Sendable {

    private let lock = NSLock()
    private var _cancelled = false
    private var _isComplete = false
    private var _reconnectCount: Int = 0
    private var _totalReconnects: Int = 0
    private var _lastSegmentTime: Date?
    private var _totalSegments: Int = 0
    private var _error: Error?

    /// Reference to the segmenter for cleanup on cancel.
    public var segmenter: LiveSegmenter?

    /// Health timeout: if no segment arrives within this interval, `isHealthy` returns false.
    public let healthTimeout: TimeInterval = 15.0

    public init() {}

    // MARK: - Cancellation

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    /// Cancel the live transmux. Stops the remux loop and marks the segmenter as ended.
    public func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
        segmenter?.markEnded()
    }

    // MARK: - Completion

    /// Whether the remux loop has exited (clean EOF, error, or cancellation).
    public var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isComplete
    }

    /// Mark the live transmux as complete. Called by TransmuxingService
    /// when the remux loop exits (EOF, unrecoverable error, or cancellation).
    public func markComplete() {
        lock.lock()
        _isComplete = true
        lock.unlock()
        segmenter?.markEnded()
    }

    // MARK: - Error

    /// The error that caused the session to fail, if any.
    public var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return _error
    }

    /// Record a fatal error. Called by the remux loop before marking complete.
    public func recordError(_ error: Error) {
        lock.lock()
        _error = error
        lock.unlock()
    }

    // MARK: - Reconnect Tracking

    /// Number of consecutive reconnect attempts since the last successful segment.
    /// Reset to 0 on each successful segment write.
    public var reconnectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _reconnectCount
    }

    /// Total reconnects across the entire session lifetime.
    public var totalReconnects: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalReconnects
    }

    /// Record a reconnect attempt. Increments consecutive and total counters.
    public func recordReconnect() {
        lock.lock()
        _reconnectCount += 1
        _totalReconnects += 1
        lock.unlock()
    }

    /// Reset the consecutive reconnect counter (called on successful segment write).
    public func resetReconnectCount() {
        lock.lock()
        _reconnectCount = 0
        lock.unlock()
    }

    // MARK: - Segment Tracking

    /// Timestamp of the last successful segment write.
    public var lastSegmentTime: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastSegmentTime
    }

    /// Total segments produced in this session.
    public var totalSegments: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalSegments
    }

    /// Record a successful segment write. Resets reconnect counter and updates health timestamp.
    public func recordSegment() {
        lock.lock()
        _lastSegmentTime = Date()
        _totalSegments += 1
        _reconnectCount = 0
        lock.unlock()
    }

    // MARK: - Health

    /// Health status: `true` if a segment was written within `healthTimeout` seconds,
    /// or if no segments have been expected yet (session just started).
    public var isHealthy: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastTime = _lastSegmentTime else {
            // No segments yet — healthy if we haven't been running too long
            return true
        }
        return Date().timeIntervalSince(lastTime) < healthTimeout
    }
}
