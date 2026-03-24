//
//  LiveLogger.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 5/3/25.
//


import Foundation
import AVFoundation

// MARK: - LiveLogger Utility

/// Structured logger for live channel events.
/// Writes to both console and persistent file via MKSLogConfig.
enum LiveLogger {

    // MARK: - Configuration

    /// Log file path resolved from the centralized config.
    static var filePath: String {
        MKSLogConfig.shared.filePath(for: .live)
    }

    private static let queue = DispatchQueue(label: "LiveLogger.write", qos: .utility)
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Public API

    static func debug(_ message: String, file: String = #file, line: Int = #line) {
        writeEntry(level: "DBG", configLevel: .debug, message: message, file: file, line: line)
    }

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        writeEntry(level: "INF", configLevel: .info, message: message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        writeEntry(level: "ERR", configLevel: .error, message: message, file: file, line: line)
    }

    // MARK: - Internal

    private static func writeEntry(
        level: String,
        configLevel: MKSLogConfig.Level,
        message: String,
        file: String,
        line: Int
    ) {
        guard configLevel >= MKSLogConfig.shared.level(for: .live) else { return }

        let fileName = (file as NSString).lastPathComponent
        let ts = dateFormatter.string(from: Date())
        let entry = "[\(ts)] [\(level)] [live] \(message) file=\(fileName) line=\(line)"

        // Console
        MKSLog.live.debug(entry)

        // File (async, thread-safe)
        queue.async {
            let line = entry + "\n"
            guard let data = line.data(using: .utf8) else { return }
            let path = filePath
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
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
