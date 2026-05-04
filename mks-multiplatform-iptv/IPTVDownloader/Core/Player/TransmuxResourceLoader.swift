import Foundation
import AVFoundation
import IPTVCore

// MARK: - TransmuxResourceLoader

/// AVAssetResourceLoaderDelegate that serves a growing fMP4 file directly
/// to AVPlayer, bypassing HTTP entirely.
///
/// This eliminates the parallel chunk download problem: AVPlayer's HTTP
/// resource loader opens dozens of parallel Range connections for static
/// files, which breaks on growing files (broken pipe storm). By using a
/// custom URL scheme + resource loader delegate, we control data delivery
/// completely.
///
/// Key design: `isByteRangeAccessSupported = false` tells AVPlayer to
/// download sequentially from byte 0. No parallel requests, no Range
/// headers, no Content-Range validation.
///
/// Architecture:
/// ```
/// FFmpeg C API writes fMP4 → /tmp/.../stream.mp4 (growing file)
///                                 ↑ reads on demand
/// TransmuxResourceLoader (AVAssetResourceLoaderDelegate)
///                                 ↑ data requests
/// AVPlayer (mkstransmux://localhost/stream.mp4)
/// ```
class TransmuxResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

    static let customScheme = "mkstransmux"

    let filePath: String
    let expectedSize: Int64
    let duration: Double
    private(set) var isComplete = false

    private let delegateQueue = DispatchQueue(
        label: "TransmuxResourceLoader.delegate",
        qos: .userInitiated
    )
    private var pendingRequests: [AVAssetResourceLoadingRequest] = []
    private var pollingTimer: DispatchSourceTimer?

    init(filePath: String, expectedSize: Int64, duration: Double = 0) {
        self.filePath = filePath
        self.duration = duration
        // Ensure we always report a non-zero size to AVPlayer.
        // Zero contentLength causes AVPlayer to skip loading entirely.
        if expectedSize > 0 {
            self.expectedSize = expectedSize
        } else {
            // Fallback: 2 GB — enough for AVPlayer to start; the actual
            // EOF is handled by isComplete + finishLoading().
            self.expectedSize = 2_147_483_648
            MKSLog.transmux.warning("expectedSize was 0, using 2GB fallback")
        }
        super.init()
        startPolling()
        MKSLog.transmux.info("Created for \(filePath), expectedSize=\(self.expectedSize), duration=\(duration)s")
    }

    deinit {
        // Cancel timer directly — do NOT call stop() or dispatch async here.
        // Creating [weak self] closures during deinit crashes with
        // "Cannot form weak reference to instance in the process of deallocation".
        pollingTimer?.cancel()
        pollingTimer = nil
        MKSLog.transmux.debug("deinit")
    }

    // MARK: - Public API

    /// Create an AVURLAsset with the custom URL scheme and this delegate.
    func makeAsset() -> AVURLAsset {
        let url = URL(string: "\(Self.customScheme)://localhost/stream.mp4")!
        MKSLog.transmux.debug("Creating asset with URL: \(url)")
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
        MKSLog.transmux.debug("Delegate set on asset.resourceLoader, preloading playable key...")
        return asset
    }

    /// Mark the transmux as complete. Pending requests waiting for data
    /// at EOF will be finalized.
    func markComplete() {
        delegateQueue.async { [weak self] in
            guard let self else { return }
            self.isComplete = true
            MKSLog.transmux.info("Transmux marked complete")
            self.processPendingRequests()
        }
    }

    /// Stop and cancel all pending requests.
    /// Safe to call from any thread — does NOT dispatch async (which would
    /// crash with "Cannot form weak reference" if called during deallocation).
    func stop() {
        pollingTimer?.cancel()
        pollingTimer = nil
        // pendingRequests are discarded with the object — no finishLoading(with:)
        // because AVPlayer may already be deallocated (causes abort).
        MKSLog.transmux.info("Stopped")
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let hasContentInfo = loadingRequest.contentInformationRequest != nil
        let hasData = loadingRequest.dataRequest != nil
        MKSLog.transmux.debug("shouldWaitForLoadingOfRequestedResource called — contentInfo=\(hasContentInfo) dataRequest=\(hasData)")

        // Fill content information if requested
        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.contentType = AVFileType.mp4.rawValue
            contentRequest.contentLength = expectedSize
            // Must be true for on-demand fMP4 — false tells AVPlayer this is a
            // non-seekable live stream, which uses much more conservative buffering
            // and may never reach .readyToPlay for large files.
            contentRequest.isByteRangeAccessSupported = true
            MKSLog.transmux.debug("Filled contentInfo: type=\(contentRequest.contentType ?? "nil"), length=\(contentRequest.contentLength), byteRange=\(contentRequest.isByteRangeAccessSupported)")
        }

        // Handle data request
        if let dataReq = loadingRequest.dataRequest {
            MKSLog.transmux.debug("DataRequest: offset=\(dataReq.requestedOffset), length=\(dataReq.requestedLength), currentOffset=\(dataReq.currentOffset)")
            pendingRequests.append(loadingRequest)
            processPendingRequests()
        } else {
            // Content-info-only request
            MKSLog.transmux.debug("Content-info-only request, finishing immediately")
            loadingRequest.finishLoading()
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        MKSLog.transmux.debug("didCancel called")
        pendingRequests.removeAll { $0 === loadingRequest }
    }

    // MARK: - Data Processing

    private func processPendingRequests() {
        var completed: [AVAssetResourceLoadingRequest] = []

        for request in pendingRequests {
            if request.isFinished || request.isCancelled {
                completed.append(request)
                continue
            }

            guard let dataRequest = request.dataRequest else {
                request.finishLoading()
                completed.append(request)
                continue
            }

            if fillDataRequest(dataRequest, request: request) {
                completed.append(request)
            }
        }

        pendingRequests.removeAll { req in completed.contains { $0 === req } }
    }

    /// Provide available data for a loading request.
    /// Returns true if the request is fully satisfied or should be terminated.
    private func fillDataRequest(
        _ dataRequest: AVAssetResourceLoadingDataRequest,
        request: AVAssetResourceLoadingRequest
    ) -> Bool {
        let requestedOffset = dataRequest.currentOffset
        let bytesRemaining = Int64(dataRequest.requestedLength) - (dataRequest.currentOffset - dataRequest.requestedOffset)

        guard bytesRemaining > 0 else {
            MKSLog.transmux.debug("fillData: 0 bytes remaining, finishing")
            request.finishLoading()
            return true
        }

        let fileSize = Self.currentFileSize(filePath)

        // Data not available yet
        if requestedOffset >= fileSize {
            if isComplete {
                MKSLog.transmux.debug("fillData: offset \(requestedOffset) >= fileSize \(fileSize), transmux complete — finishing")
                request.finishLoading()
                return true
            }

            // Guard against AVPlayer probing the END of the file (e.g., looking for
            // the mfra box near expectedSize). If the requested offset is far beyond
            // current file size (>50MB ahead), finish the request immediately instead
            // of polling forever. AVPlayer will work with the data it already has.
            let gap = requestedOffset - fileSize
            if gap > 50_000_000 {
                MKSLog.transmux.debug("fillData: offset \(requestedOffset) is \(gap / 1_048_576)MB beyond fileSize \(fileSize) — finishing to unblock AVPlayer")
                request.finishLoading()
                return true
            }

            return false // Will retry on next poll
        }

        // Read available data from file
        guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            MKSLog.transmux.error("fillData: Cannot open file at \(filePath)")
            request.finishLoading(with: NSError(
                domain: "TransmuxResourceLoader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot open \(filePath)"]
            ))
            return true
        }
        defer { try? fileHandle.close() }

        do {
            try fileHandle.seek(toOffset: UInt64(requestedOffset))
        } catch {
            MKSLog.transmux.error("fillData: seek failed: \(error)")
            request.finishLoading(with: error)
            return true
        }

        let availableBytes = min(bytesRemaining, fileSize - requestedOffset)
        // Read up to 4MB per pass — enough to deliver data fast to AVPlayer
        let readSize = min(availableBytes, 4_194_304)
        let data = fileHandle.readData(ofLength: Int(readSize))

        if !data.isEmpty {
            dataRequest.respond(with: data)
            // Log first few data deliveries
            if dataRequest.currentOffset < 2_000_000 {
                MKSLog.transmux.debug("fillData: served \(data.count) bytes at offset \(requestedOffset), fileSize=\(fileSize)")
            }
        }

        // Check if request is fully satisfied
        let newOffset = dataRequest.currentOffset
        let endOffset = dataRequest.requestedOffset + Int64(dataRequest.requestedLength)

        if newOffset >= endOffset {
            MKSLog.transmux.debug("fillData: request fully satisfied (offset \(newOffset) >= end \(endOffset))")
            request.finishLoading()
            return true
        }

        // Transmux done and we've served all available data
        if isComplete && newOffset >= fileSize {
            MKSLog.transmux.debug("fillData: transmux complete, all data served")
            request.finishLoading()
            return true
        }

        return false // More data needed on next poll
    }

    // MARK: - Polling

    /// Poll every 100ms for new data to fulfill pending requests.
    /// Also detects transmux completion via the sentinel file.
    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: delegateQueue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            // Detect completion via sentinel file
            if !self.isComplete {
                let sentinelPath = (self.filePath as NSString)
                    .deletingLastPathComponent + "/.transmux_complete"
                if FileManager.default.fileExists(atPath: sentinelPath) {
                    self.isComplete = true
                    MKSLog.transmux.info("Detected transmux completion via sentinel")
                }
            }

            if !self.pendingRequests.isEmpty {
                self.processPendingRequests()
            }
        }
        timer.resume()
        pollingTimer = timer
    }

    // MARK: - Helpers

    private static func currentFileSize(_ path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
}
