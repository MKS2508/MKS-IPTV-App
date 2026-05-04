//
//  StreamManager.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 5/3/25.
//


import Foundation
import AVKit
import IPTVCore

class StreamManager {
    private var player: AVPlayer?
    private var playerStatusObserver: NSKeyValueObservation?
    private var urlSessionTask: URLSessionTask?

    func resolveStreamURL(from originalUrl: URL, completion: @escaping (URL?) -> Void) {
        LiveLogger.debug("Resolving stream redirect URL: \(originalUrl.absoluteString)")
        
        var request = URLRequest(url: originalUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 3
        request.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
        request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        
        let session = URLSession(configuration: .ephemeral)
        urlSessionTask = session.dataTask(with: request) { [weak self] _, response, error in
            defer { self?.urlSessionTask = nil }
            
            if let error = error {
                LiveLogger.error("URL Resolution Error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                LiveLogger.error("Invalid HTTP Response")
                completion(nil)
                return
            }
            
            // Capture the final URL after redirects
            let resolvedUrl = httpResponse.url ?? originalUrl
            LiveLogger.debug("Resolved URL: \(resolvedUrl.absoluteString)")
            completion(resolvedUrl)
        }
        
        urlSessionTask?.resume()
    }
    
    func setupStreamPlayer(with url: URL, completion: @escaping (AVPlayer?) -> Void) {
        LiveLogger.debug("Setting up player with validated URL: \(url.absoluteString)")
        
        // Configure custom headers for AVPlayer
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": [
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18",
            "Range": "bytes=0-"
        ]])
        
        Task { [weak self] in
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    LiveLogger.error("Asset is not playable")
                    completion(nil)
                    return
                }
                let playerItem = AVPlayerItem(asset: asset)
                self?.setupPlayerItemObservers(playerItem: playerItem, completion: completion)
            } catch {
                LiveLogger.error("Asset loading failed: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    private func setupPlayerItemObservers(playerItem: AVPlayerItem, completion: @escaping (AVPlayer?) -> Void) {
        playerStatusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            
            switch item.status {
            case .readyToPlay:
                LiveLogger.debug("Player item ready to play")
                let player = AVPlayer(playerItem: item)
                self.player = player
                
                // Add buffer observer
                player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 1, preferredTimescale: 600),
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    LiveLogger.debug("Playback buffer status: \(self.player?.currentItem?.isPlaybackBufferFull ?? false ? "Full" : "Buffering")")
                }
                
                completion(player)
                
            case .failed:
                LiveLogger.error("Player item failed: \(item.error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                
            case .unknown:
                LiveLogger.debug("Player item state unknown")
                
            @unknown default:
                break
            }
        }
    }

    func cleanUpPlayer() {
        LiveLogger.debug("Performing full cleanup")
        urlSessionTask?.cancel()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
    }
}
