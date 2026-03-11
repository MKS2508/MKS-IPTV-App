import Foundation

// MARK: - LiveHLSProxy

/// Pure HLS proxy that maintains a **single upstream connection** to an IPTV live stream
/// and serves the content locally via rewritten m3u8 playlists and cached .ts segments.
///
/// ## Problem
/// IPTV servers enforce a single-connection-per-credential limit. When AVPlayer streams
/// a live channel directly and the user activates AirPlay, the Apple TV opens a second
/// connection to the same m3u8 URL, hitting the limit and breaking playback.
///
/// ## Solution
/// This proxy fetches the upstream m3u8 playlist periodically (live sliding window),
/// downloads .ts segments into an in-memory cache, and rewrites the playlist to point
/// to local URLs served by TransmuxServer. Both local AVPlayer and AirPlay/Cast devices
/// consume from the same TransmuxServer instance, maintaining a single upstream connection.
///
/// ## Connection Discipline
/// **ALL upstream HTTP requests are strictly serialized.** The IPTV server sees at most
/// one active TCP request at any time. A serial pipeline Task processes operations in order:
/// playlist refresh → segment download → segment download → ... → playlist refresh → ...
///
/// ## Architecture
/// ```
/// Upstream IPTV Server (m3u8 + .ts segments)
///     ↓  (MAX 1 concurrent HTTP request — strictly serialized)
/// LiveHLSProxy (polling + serial download pipeline + in-memory cache)
///     ↓
/// TransmuxServer (NWListener :8100-8199)
///     ↓          ↓
/// AVPlayer    AirPlay/Cast device
/// ```
public actor LiveHLSProxy {

    // MARK: - Constants

    /// Maximum concurrent upstream connections. IPTV servers enforce single-connection limits.
    private static let maxUpstreamConnections = 1

    // MARK: - Types

    /// Session info returned after proxy starts, used by TransmuxServer to configure serving.
    public struct LiveSession: Sendable {
        /// Unique session identifier.
        public let sessionID: String
        /// The original IPTV upstream URL being proxied.
        public let upstreamURL: URL
        /// Local playlist path for TransmuxServer routing (e.g., "live.m3u8").
        public let localPlaylistPath: String
    }

    /// Errors specific to the live proxy.
    public enum ProxyError: LocalizedError {
        case invalidPlaylist
        case upstreamUnreachable(statusCode: Int)
        case cancelled
        case noUpstreamURL

        public var errorDescription: String? {
            switch self {
            case .invalidPlaylist:
                return "Upstream returned invalid or unparseable HLS playlist"
            case .upstreamUnreachable(let code):
                return "Upstream returned HTTP \(code)"
            case .cancelled:
                return "Live proxy was cancelled"
            case .noUpstreamURL:
                return "No upstream URL configured"
            }
        }
    }

    /// A cached .ts segment with metadata for eviction ordering.
    struct SegmentEntry {
        let data: Data
        let sequenceNumber: Int
    }

    /// Represents a parsed segment reference from an m3u8 playlist.
    struct ParsedSegment {
        /// The original upstream URL for this segment.
        let upstreamURL: URL
        /// The local filename assigned by the proxy (e.g., "live_seg_42.ts").
        let localName: String
        /// The media sequence number from the upstream playlist.
        let sequenceNumber: Int
        /// Duration in seconds from #EXTINF.
        let duration: Double
    }

    /// Operations queued for the serial download pipeline.
    private enum PipelineOp {
        case refreshPlaylist
        case downloadSegment(name: String, url: URL)
    }

    // MARK: - Properties

    /// The upstream m3u8 URL being proxied.
    private var upstreamURL: URL?

    /// Unique session ID for logging.
    private var sessionID: String?

    /// Whether the proxy has been stopped.
    private var isStopped = false

    /// Cached .ts segments keyed by their local filename.
    private var segmentCache: [String: SegmentEntry] = [:]

    /// Mapping from local segment name to upstream URL for on-demand fetching.
    private var segmentURLMap: [String: URL] = [:]

    /// Known segment filenames in insertion order (for FIFO eviction).
    private var segmentOrder: [String] = []

    /// Maximum number of segments to cache in memory.
    /// At 2s/segment, 30 segments = ~60 seconds of content (~15-30MB RAM at 1080p).
    private let maxCachedSegments = 30

    /// The most recently fetched and rewritten m3u8 playlist content.
    private var currentPlaylist: String?

    /// The upstream #EXT-X-MEDIA-SEQUENCE value, tracked for stable segment naming.
    private var upstreamMediaSequence: Int = 0

    /// Set of upstream segment URLs already seen, to avoid re-downloading on playlist refresh.
    private var knownSegmentURLs: Set<String> = []

    /// Target duration from the upstream playlist (seconds), used to calculate refresh interval.
    private var targetDuration: Double = 6.0

    /// Playlist refresh interval — typically half the target duration.
    private var refreshInterval: TimeInterval {
        max(targetDuration / 2.0, 1.0)
    }

    /// The single background pipeline Task that serializes all upstream requests.
    private var pipelineTask: Task<Void, Never>?

    /// Continuation for feeding operations into the serial pipeline.
    private var pipelineContinuation: AsyncStream<PipelineOp>.Continuation?

    /// URLSession for upstream fetches. Uses ephemeral config with IPTV-compatible headers.
    /// httpMaximumConnectionsPerHost = 1 ensures the OS never opens parallel TCP connections.
    private var urlSession: URLSession?

    /// Counter for local segment naming, monotonically increasing.
    private var localSegmentCounter: Int = 0

    /// Number of consecutive playlist fetch failures (for backoff/alerting).
    private var consecutiveFailures: Int = 0

    /// Maximum consecutive failures before logging an error (vs warning).
    private let maxConsecutiveFailuresBeforeError = 10

    /// Segments currently being fetched on-demand by the pipeline.
    /// Maps local segment name to an array of continuations waiting for the result.
    private var pendingOnDemand: [String: [CheckedContinuation<Data?, Never>]] = [:]

    // MARK: - Public API

    public init() {}

    /// Start proxying a live HLS stream.
    ///
    /// Performs an initial fetch of the upstream m3u8, parses and rewrites it,
    /// sequentially pre-fetches the most recent segments, and starts the serial pipeline.
    ///
    /// - Parameter url: The upstream IPTV m3u8 URL
    /// - Returns: LiveSession with info needed by TransmuxServer
    /// - Throws: ProxyError if the initial playlist fetch fails
    public func start(url: URL) async throws -> LiveSession {
        // Clean up any previous session
        stopInternal()

        let id = UUID().uuidString.prefix(8)
        self.sessionID = String(id)
        self.upstreamURL = url
        self.isStopped = false
        self.consecutiveFailures = 0
        self.localSegmentCounter = 0
        self.knownSegmentURLs = []
        self.segmentCache = [:]
        self.segmentURLMap = [:]
        self.segmentOrder = []
        self.currentPlaylist = nil
        self.pendingOnDemand = [:]

        TransmuxLog.log("LIVE PROXY START session=\(id) url=\(url.absoluteString)", tag: "LiveProxy")

        // Create URLSession with IPTV-compatible headers and strict single-connection limit
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18",
            "Accept-Encoding": "identity",
            "Connection": "Keep-Alive"
        ]
        config.httpMaximumConnectionsPerHost = Self.maxUpstreamConnections
        config.timeoutIntervalForResource = 30
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)

        // Fetch initial playlist — this validates the upstream is reachable
        try await fetchAndParsePlaylist()

        // Sequentially pre-fetch the most recent segments (1 at a time, strict serial)
        let segmentsToPreFetch = Array(parsedSegmentNames().suffix(3))
        TransmuxLog.log("LIVE PRE-FETCH \(segmentsToPreFetch.count) segments (serial)", tag: "LiveProxy")
        for name in segmentsToPreFetch {
            if segmentCache[name] == nil, let segURL = segmentURLMap[name] {
                await downloadSegmentSerial(url: segURL, name: name)
            }
        }

        // Start the serial pipeline (playlist refresh + segment pre-fetching)
        startPipeline()

        let cachedCount = segmentCache.count
        TransmuxLog.log("LIVE PROXY READY session=\(id) cached=\(cachedCount) targetDuration=\(targetDuration)s refreshInterval=\(refreshInterval)s", tag: "LiveProxy")

        return LiveSession(
            sessionID: String(id),
            upstreamURL: url,
            localPlaylistPath: "live.m3u8"
        )
    }

    /// Stop the proxy and clean up all resources.
    public func stop() {
        stopInternal()
    }

    /// Get the current rewritten playlist content as Data for HTTP serving.
    /// Returns nil if no playlist has been fetched yet.
    public func getPlaylist() -> Data? {
        guard let playlist = currentPlaylist else { return nil }
        return Data(playlist.utf8)
    }

    /// Get a cached segment by local name.
    /// Returns nil if the segment is not in cache.
    public func getSegment(name: String) -> Data? {
        return segmentCache[name]?.data
    }

    /// Get a segment, downloading it on-demand if not cached.
    /// The download goes through the serial pipeline to respect the single-connection limit.
    /// If the pipeline is already downloading this segment, we wait for that download to finish
    /// rather than issuing a duplicate request.
    ///
    /// - Parameter name: The local segment filename (e.g., "live_seg_42.ts")
    /// - Returns: Segment data, or nil if unavailable
    public func getOrFetchSegment(name: String) async -> Data? {
        // Fast path: already cached
        if let cached = segmentCache[name] {
            return cached.data
        }

        // Check if we know this segment's upstream URL
        guard let url = segmentURLMap[name] else {
            TransmuxLog.log("LIVE 404 unknown segment: \(name)", tag: "LiveProxy", level: .warn)
            return nil
        }

        // Check if this segment is already being fetched (dedup requests)
        if pendingOnDemand[name] != nil {
            TransmuxLog.log("LIVE WAITING for in-flight: \(name)", tag: "LiveProxy", level: .debug)
            return await withCheckedContinuation { continuation in
                pendingOnDemand[name]?.append(continuation)
            }
        }

        // Enqueue the download and wait for it
        TransmuxLog.log("LIVE ON-DEMAND enqueue: \(name)", tag: "LiveProxy")
        pendingOnDemand[name] = []

        // Submit to the serial pipeline
        pipelineContinuation?.yield(.downloadSegment(name: name, url: url))

        // Wait for the pipeline to complete this download
        return await withCheckedContinuation { continuation in
            pendingOnDemand[name]?.append(continuation)
        }
    }

    /// Whether the proxy is currently active and polling.
    public var isActive: Bool {
        !isStopped && pipelineTask != nil
    }

    // MARK: - Internal Cleanup

    private func stopInternal() {
        let wasStopped = isStopped
        isStopped = true

        let sid = sessionID ?? "?"
        pipelineContinuation?.finish()
        pipelineContinuation = nil
        pipelineTask?.cancel()
        pipelineTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Resume any waiting on-demand continuations with nil
        for (_, continuations) in pendingOnDemand {
            for c in continuations {
                c.resume(returning: nil)
            }
        }
        pendingOnDemand.removeAll()

        segmentCache.removeAll()
        segmentURLMap.removeAll()
        segmentOrder.removeAll()
        knownSegmentURLs.removeAll()
        currentPlaylist = nil
        upstreamURL = nil
        sessionID = nil

        if !wasStopped {
            TransmuxLog.log("LIVE PROXY STOPPED session=\(sid)", tag: "LiveProxy")
        }
    }

    // MARK: - Serial Pipeline

    /// Start the serial pipeline — two cooperating tasks:
    ///
    /// 1. **Timer task**: Periodically injects `.refreshPlaylist` + pre-fetch ops into the stream.
    /// 2. **Consumer task**: Single consumer that processes ops from the stream one at a time.
    ///    This is the ONLY code that ever calls URLSession — guaranteeing max 1 upstream request.
    ///
    /// On-demand segment requests from `getOrFetchSegment` also feed into the same stream,
    /// so they're serialized with everything else.
    private func startPipeline() {
        let (stream, continuation) = AsyncStream<PipelineOp>.makeStream()
        self.pipelineContinuation = continuation

        // Consumer: the ONLY task that performs upstream HTTP requests.
        // Processes ops strictly one at a time from the stream.
        pipelineTask = Task { [weak self] in
            for await op in stream {
                guard !Task.isCancelled else { break }
                await self?.executePipelineOp(op)
            }
        }

        // Timer: periodically injects playlist refresh + segment pre-fetch ops.
        Task { [weak self] in
            while !Task.isCancelled {
                let interval = await self?.refreshInterval ?? 3.0
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))

                guard !Task.isCancelled else { break }
                guard let self = self, await !self.isStopped else { break }

                // Schedule a playlist refresh
                continuation.yield(.refreshPlaylist)

                // After a short delay (let the refresh complete first), schedule pre-fetches
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

                guard !Task.isCancelled else { break }
                let segNames = await self.newUncachedSegmentNames()
                for name in segNames {
                    guard !Task.isCancelled else { break }
                    if let url = await self.segmentURLMap[name] {
                        continuation.yield(.downloadSegment(name: name, url: url))
                    }
                }
            }
        }
    }

    /// Execute a single pipeline operation (on the serial pipeline Task).
    private func executePipelineOp(_ op: PipelineOp) async {
        switch op {
        case .refreshPlaylist:
            do {
                try await fetchAndParsePlaylist()
            } catch {
                let failures = consecutiveFailures
                if failures > 0 && failures.isMultiple(of: 5) {
                    TransmuxLog.log("LIVE PLAYLIST REFRESH FAILED \(failures)x consecutive", tag: "LiveProxy", level: .error)
                }
            }

        case .downloadSegment(let name, let url):
            let data = await downloadSegmentSerial(url: url, name: name)
            // Resume all on-demand continuations waiting for this segment
            if let continuations = pendingOnDemand.removeValue(forKey: name) {
                for c in continuations {
                    c.resume(returning: data)
                }
            }
        }
    }

    /// Return local segment names from the current segmentURLMap that aren't cached yet.
    /// Limited to the 2 newest to avoid fetching stale segments.
    private func newUncachedSegmentNames() -> [String] {
        let allNames = segmentURLMap.keys.sorted()
        return Array(allNames.filter { segmentCache[$0] == nil }.suffix(2))
    }

    /// Return all local segment names currently registered (for pre-fetch at startup).
    private func parsedSegmentNames() -> [String] {
        return segmentURLMap.keys.sorted()
    }

    // MARK: - Playlist Fetching & Parsing

    /// Fetch the upstream m3u8 playlist, parse it, rewrite segment URLs to local names,
    /// and update the current playlist and segment maps.
    /// Called from the serial pipeline — no concurrent upstream requests.
    private func fetchAndParsePlaylist() async throws {
        guard let url = upstreamURL, let session = urlSession, !isStopped else {
            throw ProxyError.cancelled
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            consecutiveFailures += 1
            let level: TransmuxLog.Level = consecutiveFailures >= maxConsecutiveFailuresBeforeError ? .error : .warn
            TransmuxLog.log("LIVE PLAYLIST FETCH FAILED (\(consecutiveFailures)x): \(error.localizedDescription)", tag: "LiveProxy", level: level)
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProxyError.upstreamUnreachable(statusCode: 0)
        }

        guard httpResponse.statusCode == 200 else {
            consecutiveFailures += 1
            throw ProxyError.upstreamUnreachable(statusCode: httpResponse.statusCode)
        }

        guard let playlistText = String(data: data, encoding: .utf8) else {
            throw ProxyError.invalidPlaylist
        }

        // Reset failure counter on success
        consecutiveFailures = 0

        // Log raw playlist on first fetch for debugging
        if segmentURLMap.isEmpty {
            TransmuxLog.log("LIVE PLAYLIST RAW:\n\(playlistText)", tag: "LiveProxy", level: .debug)
        }

        // Determine base URL for resolving relative segment paths
        let baseURL = url.deletingLastPathComponent()

        // Parse and rewrite the playlist
        let parsed = parseAndRewritePlaylist(playlistText, baseURL: baseURL)
        self.currentPlaylist = parsed.rewrittenPlaylist
        self.targetDuration = parsed.targetDuration

        // Register new segments
        let newSegments = parsed.segments.filter { !knownSegmentURLs.contains($0.upstreamURL.absoluteString) }
        for seg in newSegments {
            knownSegmentURLs.insert(seg.upstreamURL.absoluteString)
            segmentURLMap[seg.localName] = seg.upstreamURL
        }

        if !newSegments.isEmpty {
            let urls = newSegments.map { "\($0.localName) → \($0.upstreamURL.lastPathComponent)" }.joined(separator: ", ")
            TransmuxLog.log("LIVE PLAYLIST REFRESH: +\(newSegments.count) new [\(urls)]", tag: "LiveProxy", level: .debug)
        }
    }

    /// Parse result from playlist rewriting.
    struct PlaylistParseResult {
        let rewrittenPlaylist: String
        let segments: [ParsedSegment]
        let targetDuration: Double
        let mediaSequence: Int
    }

    /// Parse an HLS live playlist, rewrite segment URLs to local names,
    /// and return the rewritten text plus metadata.
    ///
    /// Handles both absolute and relative segment URLs in the upstream playlist.
    /// Preserves all HLS tags except segment URIs which are rewritten.
    private func parseAndRewritePlaylist(_ text: String, baseURL: URL) -> PlaylistParseResult {
        let lines = text.components(separatedBy: .newlines)
        var rewritten = ""
        var segments: [ParsedSegment] = []
        var parsedTargetDuration: Double = 6.0
        var mediaSequence: Int = 0
        var currentExtinf: String?
        var currentDuration: Double = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#EXT-X-TARGETDURATION:") {
                let value = trimmed.replacingOccurrences(of: "#EXT-X-TARGETDURATION:", with: "")
                parsedTargetDuration = Double(value.trimmingCharacters(in: .whitespaces)) ?? 6.0
                rewritten += trimmed + "\n"
            } else if trimmed.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                let value = trimmed.replacingOccurrences(of: "#EXT-X-MEDIA-SEQUENCE:", with: "")
                mediaSequence = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
                self.upstreamMediaSequence = mediaSequence
                // Rewrite media sequence to our local counter base
                let localBase = localSegmentCounter
                rewritten += "#EXT-X-MEDIA-SEQUENCE:\(localBase)\n"
            } else if trimmed.hasPrefix("#EXTINF:") {
                // Store the EXTINF line; the next non-comment line is the segment URL
                currentExtinf = trimmed
                // Parse duration
                let durationStr = trimmed
                    .replacingOccurrences(of: "#EXTINF:", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentDuration = Double(durationStr) ?? 0
                rewritten += trimmed + "\n"
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                // This is a segment URI line
                if currentExtinf != nil {
                    let segURL: URL
                    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                        segURL = URL(string: trimmed) ?? baseURL.appendingPathComponent(trimmed)
                    } else {
                        segURL = baseURL.appendingPathComponent(trimmed)
                    }

                    let localName = "live_seg_\(localSegmentCounter).ts"
                    let seqNum = mediaSequence + segments.count

                    segments.append(ParsedSegment(
                        upstreamURL: segURL,
                        localName: localName,
                        sequenceNumber: seqNum,
                        duration: currentDuration
                    ))

                    rewritten += localName + "\n"
                    localSegmentCounter += 1
                    currentExtinf = nil
                } else {
                    // Non-segment URI line (shouldn't happen in well-formed m3u8)
                    rewritten += trimmed + "\n"
                }
            } else {
                // Pass through all other HLS tags and comments
                rewritten += trimmed + "\n"
            }
        }

        return PlaylistParseResult(
            rewrittenPlaylist: rewritten,
            segments: segments,
            targetDuration: parsedTargetDuration,
            mediaSequence: mediaSequence
        )
    }

    // MARK: - Serial Segment Download

    /// Download a single .ts segment from upstream and cache it.
    /// This method is called from the serial pipeline — never concurrently.
    ///
    /// - Parameters:
    ///   - url: The upstream segment URL
    ///   - name: The local segment filename for caching
    /// - Returns: The segment data, or nil on failure
    @discardableResult
    private func downloadSegmentSerial(url: URL, name: String) async -> Data? {
        guard !isStopped, let session = urlSession else { return nil }

        // Double-check cache (may have been filled while waiting in queue)
        if let cached = segmentCache[name] {
            return cached.data
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            TransmuxLog.log("LIVE FETCH \(name) ← \(url.lastPathComponent)", tag: "LiveProxy", level: .debug)
            let (data, response) = try await session.data(for: request)

            guard let httpResp = response as? HTTPURLResponse,
                  httpResp.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                TransmuxLog.log("LIVE SEGMENT \(name) HTTP \(code) url=\(url.absoluteString)", tag: "LiveProxy", level: .warn)
                return nil
            }

            let entry = SegmentEntry(
                data: data,
                sequenceNumber: segmentOrder.count
            )
            segmentCache[name] = entry

            // Track insertion order for FIFO eviction (only if not already tracked)
            if !segmentOrder.contains(name) {
                segmentOrder.append(name)
            }

            // Evict old segments if over capacity
            evictOldSegments()

            TransmuxLog.log("LIVE CACHED \(name) \(data.count / 1024)KB (cache: \(segmentCache.count)/\(maxCachedSegments))", tag: "LiveProxy", level: .debug)
            return data
        } catch {
            if !isStopped {
                TransmuxLog.log("LIVE FETCH FAILED: \(name) - \(error.localizedDescription)", tag: "LiveProxy", level: .warn)
            }
            return nil
        }
    }

    // MARK: - Cache Management

    /// Evict the oldest cached segments when over capacity (FIFO).
    private func evictOldSegments() {
        while segmentOrder.count > maxCachedSegments {
            let oldest = segmentOrder.removeFirst()
            segmentCache.removeValue(forKey: oldest)
            segmentURLMap.removeValue(forKey: oldest)
        }
    }
}
