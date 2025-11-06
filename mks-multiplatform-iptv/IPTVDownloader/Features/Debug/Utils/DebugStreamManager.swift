import Foundation
import AVKit

// Extended StreamManager for Debug purposes with performance metrics
class DebugStreamManager: NSObject {
    
    struct PerformanceMetrics {
        var urlResolutionStartTime: Date?
        var urlResolutionEndTime: Date?
        var playerInitStartTime: Date?
        var playerInitEndTime: Date?
        var redirectCount: Int = 0
        var httpStatusCode: Int?
        var error: StreamError?
        
        var urlResolutionTime: TimeInterval? {
            guard let start = urlResolutionStartTime,
                  let end = urlResolutionEndTime else { return nil }
            return end.timeIntervalSince(start)
        }
        
        var playerInitTime: TimeInterval? {
            guard let start = playerInitStartTime,
                  let end = playerInitEndTime else { return nil }
            return end.timeIntervalSince(start)
        }
        
        var totalLatency: TimeInterval? {
            guard let resolutionTime = urlResolutionTime,
                  let initTime = playerInitTime else { return nil }
            return resolutionTime + initTime
        }
    }
    
    private var metrics = PerformanceMetrics()
    private var onMetricsUpdate: ((PerformanceMetrics) -> Void)?
    
    func setMetricsCallback(_ callback: @escaping (PerformanceMetrics) -> Void) {
        self.onMetricsUpdate = callback
    }
    
    func resolveStreamURLWithMetrics(from originalUrl: URL, completion: @escaping (URL?, PerformanceMetrics) -> Void) {
        metrics = PerformanceMetrics()
        metrics.urlResolutionStartTime = Date()
        
        LiveLogger.debug("Starting URL resolution with metrics for: \(originalUrl)")
        
        // Log if this is a live channel URL
        if originalUrl.absoluteString.contains("/live/") {
            LiveLogger.debug("🔴 LIVE CHANNEL detected - URL contains /live/")
            LiveLogger.debug("📺 Full Live URL: \(originalUrl.absoluteString)")
        }
        
        var request = URLRequest(url: originalUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0  // Add timeout
        
        // For live streams, don't use range header
        if !originalUrl.absoluteString.contains("/live/") {
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        } else {
            LiveLogger.debug("🔴 Skipping Range header for live stream")
        }
        
        // Add custom headers
        for (key, value) in IPTVConfiguration.defaultRequestHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
            LiveLogger.debug("  Header: \(key) = \(value)")
        }
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10.0
        configuration.timeoutIntervalForResource = 30.0
        let session = URLSession(configuration: configuration, delegate: nil, delegateQueue: nil)
        
        LiveLogger.debug("📡 Creating data task with request: \(request.url?.absoluteString ?? "nil")")
        LiveLogger.debug("📡 Request method: \(request.httpMethod ?? "nil")")
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            LiveLogger.debug("📡 Data task completed - response received")
            guard let self = self else { 
                LiveLogger.error("Self is nil in data task completion")
                return 
            }
            
            self.metrics.urlResolutionEndTime = Date()
            
            if let httpResponse = response as? HTTPURLResponse {
                self.metrics.httpStatusCode = httpResponse.statusCode
                LiveLogger.debug("HTTP Status Code: \(httpResponse.statusCode)")
                
                // Log response headers
                LiveLogger.debug("Response headers: \(httpResponse.allHeaderFields)")
                
                // Count redirects
                if httpResponse.statusCode >= 300 && httpResponse.statusCode < 400 {
                    self.metrics.redirectCount += 1
                }
                
                // Check for redirect
                if let location = httpResponse.allHeaderFields["Location"] as? String,
                   let redirectUrl = URL(string: location) {
                    LiveLogger.debug("Redirect detected to: \(redirectUrl)")
                    self.metrics.redirectCount += 1
                    self.resolveStreamURLWithMetrics(from: redirectUrl, completion: completion)
                    return
                }
            }
            
            if let error = error {
                LiveLogger.error("Error resolving URL: \(error.localizedDescription)")
                
                // Categorize error
                let streamError: StreamError
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .notConnectedToInternet, .networkConnectionLost:
                        streamError = StreamError(
                            type: .network,
                            description: "No internet connection",
                            timestamp: Date(),
                            context: urlError.localizedDescription
                        )
                    case .timedOut:
                        streamError = StreamError(
                            type: .timeout,
                            description: "Request timed out",
                            timestamp: Date(),
                            context: "URL: \(originalUrl.absoluteString)"
                        )
                    case .userAuthenticationRequired:
                        streamError = StreamError(
                            type: .authentication,
                            description: "Authentication required",
                            timestamp: Date(),
                            context: nil
                        )
                    default:
                        streamError = StreamError(
                            type: .urlResolution,
                            description: urlError.localizedDescription,
                            timestamp: Date(),
                            context: "Code: \(urlError.code)"
                        )
                    }
                } else {
                    streamError = StreamError(
                        type: .unknown,
                        description: error.localizedDescription,
                        timestamp: Date(),
                        context: nil
                    )
                }
                
                self.metrics.error = streamError
                completion(nil, self.metrics)
                return
            }
            
            LiveLogger.debug("URL resolution completed. Redirects: \(self.metrics.redirectCount)")
            LiveLogger.debug("✅ Calling completion with resolved URL: \(originalUrl)")
            
            // For live streams, we might need to use the response URL
            let finalUrl = (response as? HTTPURLResponse)?.url ?? originalUrl
            LiveLogger.debug("📍 Final URL after resolution: \(finalUrl)")
            
            completion(finalUrl, self.metrics)
        }
        
        task.resume()
    }
    
    func setupStreamPlayerWithMetrics(with url: URL, completion: @escaping (AVPlayer?, PerformanceMetrics) -> Void) {
        metrics.playerInitStartTime = Date()
        
        LiveLogger.debug("Setting up player with metrics for URL: \(url)")
        
        // Check if this is a live stream
        let isLiveStream = url.absoluteString.contains("/live/") || url.pathExtension == "ts"
        if isLiveStream {
            LiveLogger.debug("🔴 Setting up LIVE STREAM player")
            LiveLogger.debug("📺 Stream extension: \(url.pathExtension)")
        }
        
        let headers = IPTVConfiguration.defaultRequestHeaders()
        LiveLogger.debug("Using headers: \(headers)")
        
        // Try different options for the asset
        var assetOptions: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        
        // Add options to handle different stream types
        assetOptions["AVURLAssetPreferPreciseDurationAndTimingKey"] = false
        assetOptions["AVURLAssetHTTPCookiesKey"] = HTTPCookieStorage.shared.cookies ?? []
        
        // For live streams, add specific options
        if isLiveStream {
            LiveLogger.debug("🔴 Applying LIVE STREAM specific options")
            assetOptions["AVURLAssetReferenceRestrictionsKey"] = 0
            assetOptions["AVURLAssetAllowsCellularAccessKey"] = true
            // Optimize for live streaming
            assetOptions["AVURLAssetPreferPreciseDurationAndTimingKey"] = false
            assetOptions["AVURLAssetHTTPShouldUsePipeliningKey"] = true
        }
        
        let asset = AVURLAsset(url: url, options: assetOptions)
        
        // For live streams, try to load the asset first
        if isLiveStream {
            LiveLogger.debug("🔴 Loading live stream asset...")
            asset.loadValuesAsynchronously(forKeys: ["playable", "tracks"]) { [weak self] in
                guard let self = self else { return }
                
                var error: NSError?
                let playableStatus = asset.statusOfValue(forKey: "playable", error: &error)
                
                DispatchQueue.main.async {
                    if playableStatus == .loaded {
                        LiveLogger.debug("🔴 Live stream asset loaded successfully")
                        self.createPlayerFromAsset(asset, isLiveStream: isLiveStream, completion: completion)
                    } else {
                        LiveLogger.error("🔴 Live stream asset failed to load: \(error?.localizedDescription ?? "Unknown error")")
                        // Try anyway - some streams work even if playable check fails
                        self.createPlayerFromAsset(asset, isLiveStream: isLiveStream, completion: completion)
                    }
                }
            }
        } else {
            // For VOD, create player directly
            createPlayerFromAsset(asset, isLiveStream: isLiveStream, completion: completion)
        }
    }
    
    private var playerCompletion: ((AVPlayer?, PerformanceMetrics) -> Void)?
    private var currentPlayer: AVPlayer?
    
    private func createPlayerFromAsset(_ asset: AVURLAsset, isLiveStream: Bool, completion: @escaping (AVPlayer?, PerformanceMetrics) -> Void) {
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // Configure player for optimal live streaming
        if isLiveStream {
            // For live streams, we still need some buffering to ensure smooth playback
            player.automaticallyWaitsToMinimizeStalling = true
            playerItem.preferredForwardBufferDuration = 1.0 // Smaller buffer for live but not too small
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            
            // Add notification observer for access log to monitor stream health
            NotificationCenter.default.addObserver(
                self, 
                selector: #selector(playerItemDidAccessLog(_:)), 
                name: .AVPlayerItemNewAccessLogEntry, 
                object: playerItem
            )
            
            LiveLogger.debug("🔴 Player configured for live streaming with optimized buffering")
        } else {
            // For VOD content, use default behavior
            player.automaticallyWaitsToMinimizeStalling = true
            LiveLogger.debug("Player configured for VOD content")
        }
        
        LiveLogger.debug("Player created with optimized settings")
        
        // Store completion for later use
        self.playerCompletion = completion
        self.currentPlayer = player
        
        // Monitor player status
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new], context: nil)
        
        // Also observe for errors
        playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.error), options: [.new], context: nil)
        
        // For VOD content, set additional buffer duration if not already set
        if !isLiveStream && playerItem.preferredForwardBufferDuration == 0 {
            playerItem.preferredForwardBufferDuration = 5.0 // Larger buffer for VOD
        }
        
        // Set a timeout in case player never becomes ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
            guard let self = self else { return }
            if self.playerCompletion != nil {
                LiveLogger.error("Player initialization timeout after 15 seconds")
                LiveLogger.debug("Player item status: \(playerItem.status.rawValue)")
                if let error = playerItem.error {
                    LiveLogger.error("Player item error details: \(error)")
                }
                self.metrics.playerInitEndTime = Date()
                self.metrics.error = StreamError(
                    type: .timeout,
                    description: "Player initialization timeout",
                    timestamp: Date(),
                    context: "URL: \(asset.url.absoluteString)"
                )
                self.playerCompletion?(nil, self.metrics)
                self.playerCompletion = nil
                
                // Clean up observers
                playerItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
                playerItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.error))
            }
        }
    }
    
    @objc private func playerItemDidPlayToEnd(_ notification: Notification) {
        LiveLogger.debug("Player item access log entry received")
    }
    
    @objc private func playerItemDidAccessLog(_ notification: Notification) {
        guard let playerItem = notification.object as? AVPlayerItem,
              let accessLog = playerItem.accessLog(),
              let lastEvent = accessLog.events.last else { return }
        
        LiveLogger.debug("🔴 Live stream access log: bitrate=\(lastEvent.indicatedBitrate), buffered=\(lastEvent.segmentsDownloadedDuration)s")
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let playerItem = object as? AVPlayerItem else { return }
        
        if keyPath == #keyPath(AVPlayerItem.status) {
            switch playerItem.status {
            case .readyToPlay:
                LiveLogger.debug("Player is ready to play")
                metrics.playerInitEndTime = Date()
                
                // Call completion if we have one
                if let completion = playerCompletion, let player = currentPlayer {
                    completion(player, metrics)
                    playerCompletion = nil
                }
                
            case .failed:
                let errorDescription = playerItem.error?.localizedDescription ?? "Unknown error"
                LiveLogger.error("Player failed: \(errorDescription)")
                metrics.playerInitEndTime = Date()
                
                // Determine error type
                let errorType: StreamError.ErrorType
                if let error = playerItem.error as? NSError {
                    switch error.code {
                    case -1009: errorType = .network
                    case -1001: errorType = .timeout
                    case -12938, -12939: errorType = .codec // Common codec errors
                    default: errorType = .playerInit
                    }
                } else {
                    errorType = .playerInit
                }
                
                metrics.error = StreamError(
                    type: errorType,
                    description: errorDescription,
                    timestamp: Date(),
                    context: "Asset URL: \(playerItem.asset.description)"
                )
                
                if let completion = playerCompletion {
                    completion(nil, metrics)
                    playerCompletion = nil
                }
                
            case .unknown:
                LiveLogger.debug("Player status unknown")
                // Log more details about the player item
                LiveLogger.debug("Player item duration: \(playerItem.duration.seconds)")
                LiveLogger.debug("Player item loaded time ranges: \(playerItem.loadedTimeRanges)")
                LiveLogger.debug("Player item is playback likely to keep up: \(playerItem.isPlaybackLikelyToKeepUp)")
                
            @unknown default:
                LiveLogger.debug("Player status: unknown new case")
            }
        } else if keyPath == #keyPath(AVPlayerItem.error) {
            if let error = playerItem.error {
                LiveLogger.error("Player item error: \(error.localizedDescription)")
            }
        }
    }
}