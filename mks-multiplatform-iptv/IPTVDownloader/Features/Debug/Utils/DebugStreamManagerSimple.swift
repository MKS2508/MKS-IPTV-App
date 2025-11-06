import Foundation
import AVKit

// Simplified version that mimics the original StreamManager more closely
class DebugStreamManagerSimple {
    
    func testDirectPlayback(with url: URL, completion: @escaping (AVPlayer?) -> Void) {
        LiveLogger.debug("Testing direct playback with URL: \(url)")
        
        // Use headers from configuration
        let headers = IPTVConfiguration.defaultRequestHeaders()
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // Set player properties
        player.automaticallyWaitsToMinimizeStalling = true
        
        // Configure for live streaming if it's a .ts file
        if url.pathExtension == "ts" || url.absoluteString.contains("/live/") {
            playerItem.preferredForwardBufferDuration = 1.0
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            LiveLogger.debug("🔴 Configured for live streaming")
        }
        
        LiveLogger.debug("Direct player created with headers, returning immediately")
        
        // Return player immediately
        completion(player)
    }
    
    func testWithCustomHeaders(with url: URL, completion: @escaping (AVPlayer?) -> Void) {
        LiveLogger.debug("Testing with custom headers for URL: \(url)")
        
        let headers = [
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18",
            "Accept-Encoding": "gzip, deflate, br, identity",
            "Connection": "Keep-Alive"
        ]
        
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = true
        player.appliesMediaSelectionCriteriaAutomatically = true
        
        LiveLogger.debug("Player with headers created, returning immediately")
        completion(player)
    }
    
    func testWithMinimalBuffering(with url: URL, completion: @escaping (AVPlayer?) -> Void) {
        LiveLogger.debug("Testing with minimal buffering for URL: \(url)")
        
        // Use headers from configuration
        let headers = IPTVConfiguration.defaultRequestHeaders()
        
        // Create asset with minimal options
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers,
            "AVURLAssetPreferPreciseDurationAndTimingKey": false
        ])
        
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        // Minimal buffering for faster start
        player.automaticallyWaitsToMinimizeStalling = false
        playerItem.preferredForwardBufferDuration = 0.5
        playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        
        LiveLogger.debug("🔴 Player created with minimal buffering")
        
        completion(player)
    }
}