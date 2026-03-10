//
//  LiveLogger.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 5/3/25.
//


import Foundation
import AVFoundation

// MARK: - LiveLogger Utility
enum LiveLogger {
    static func debug(_ message: String, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        print("🔍 DEBUG [\(fileName):\(line)] \(message)")
    }
    
    static func error(_ message: String, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        print("❌ ERROR [\(fileName):\(line)] \(message)")
    }
}

// MARK: - AVPlayer Status Extension
extension AVPlayerItem.Status: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .readyToPlay: return "Ready to Play"
        case .failed: return "Failed"
        @unknown default: return "Unknown (New Case)"
        }
    }
}
