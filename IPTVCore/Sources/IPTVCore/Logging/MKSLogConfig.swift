//
//  MKSLogConfig.swift
//  mks-multiplatform-iptv
//
//  Centralized logging configuration singleton.
//  Reads defaults from LogConfig.plist (bundle) with UserDefaults overrides
//  for runtime changes via the Settings > Logging panel.
//
//  Log files are stored in ~/Library/Application Support/MKS-IPTV/Logs/
//  (persistent across reboots, unlike $TMPDIR).
//

import Foundation

/// Centralized logging configuration for all app subsystems.
///
/// Priority chain: UserDefaults (`MKSLog.*` keys) > LogConfig.plist > hardcoded `.info`.
/// The debug panel (Settings > Logging) writes to UserDefaults so changes take
/// effect immediately and persist across launches.
public final class MKSLogConfig: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = MKSLogConfig()

    // MARK: - Subsystem

    /// Identifies each independent logging subsystem.
    public enum Subsystem: String, CaseIterable, Identifiable {
        case transmux
        case player
        case cast
        case live
        case ffmpeg

        public var id: String { rawValue }

        /// Human-readable name for the Settings UI.
        public var displayName: String {
            switch self {
            case .transmux: return "Transmux"
            case .player:   return "Player"
            case .cast:     return "Cast"
            case .live:     return "Live"
            case .ffmpeg:   return "FFmpeg"
            }
        }

        /// Log file name on disk.
        public var fileName: String {
            switch self {
            case .transmux, .ffmpeg: return "mks-iptv-transmux.log"
            case .player:            return "mks-iptv-player.log"
            case .cast:              return "mks-iptv-cast.log"
            case .live:              return "mks-iptv-live.log"
            }
        }

        /// UserDefaults key for the level override.
        public var defaultsKey: String { "MKSLog.level.\(rawValue)" }
    }

    // MARK: - Level

    /// Log severity level. Lower raw value = more verbose.
    public enum Level: Int, CaseIterable, Comparable, Identifiable {
        case debug   = 0
        case info    = 1
        case warning = 2
        case error   = 3

        public var id: Int { rawValue }

        public var displayName: String {
            switch self {
            case .debug:   return "Debug"
            case .info:    return "Info"
            case .warning: return "Warning"
            case .error:   return "Error"
            }
        }

        public var abbreviation: String {
            switch self {
            case .debug:   return "DBG"
            case .info:    return "INF"
            case .warning: return "WRN"
            case .error:   return "ERR"
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - State

    private let defaults = UserDefaults.standard
    private let plistLevels: [String: Int]
    private let plistDirectory: String
    private let plistMaxFileSize: Int

    // MARK: - Init

    private init() {
        // Load bundle plist defaults
        var levels: [String: Int] = [:]
        var directory = ""
        var maxSize = 10_485_760 // 10 MB

        if let url = Bundle.main.url(forResource: "LogConfig", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let dir = plist["logDirectory"] as? String {
                directory = dir
            }
            if let size = plist["maxFileSize"] as? Int {
                maxSize = size
            }
            if let lvls = plist["levels"] as? [String: Int] {
                levels = lvls
            }
        }

        self.plistLevels = levels
        self.plistDirectory = directory
        self.plistMaxFileSize = maxSize
    }

    // MARK: - Log Directory

    /// Resolved log directory path.
    /// Priority: UserDefaults > plist > default Application Support path.
    public var logDirectory: String {
        if let override = defaults.string(forKey: "MKSLog.directory"), !override.isEmpty {
            return override
        }
        if !plistDirectory.isEmpty {
            return plistDirectory
        }
        return Self.defaultLogDirectory
    }

    /// Default log directory: ~/Library/Application Support/MKS-IPTV/Logs/
    public static var defaultLogDirectory: String {
        #if os(tvOS)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        #endif
        return base.appendingPathComponent("MKS-IPTV/Logs", isDirectory: true).path
    }

    /// Maximum log file size in bytes.
    public var maxFileSize: Int { plistMaxFileSize }

    // MARK: - File Paths

    /// Full file path for a given subsystem's log.
    public func filePath(for subsystem: Subsystem) -> String {
        (logDirectory as NSString).appendingPathComponent(subsystem.fileName)
    }

    /// File size in bytes for a given subsystem's log, or 0 if not present.
    public func fileSize(for subsystem: Subsystem) -> Int64 {
        let path = filePath(for: subsystem)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }

    // MARK: - Level Access

    /// Current effective level for a subsystem.
    /// Priority: UserDefaults > plist > `.info`.
    public func level(for subsystem: Subsystem) -> Level {
        let key = subsystem.defaultsKey
        // UserDefaults returns 0 for missing keys, but 0 is a valid level (debug).
        // Use object(forKey:) to distinguish "not set" from "set to 0".
        if defaults.object(forKey: key) != nil {
            let raw = defaults.integer(forKey: key)
            return Level(rawValue: raw) ?? .info
        }
        if let plistRaw = plistLevels[subsystem.rawValue] {
            return Level(rawValue: plistRaw) ?? .info
        }
        return .info
    }

    /// Persist a level override for a subsystem via UserDefaults.
    public func setLevel(_ level: Level, for subsystem: Subsystem) {
        defaults.set(level.rawValue, forKey: subsystem.defaultsKey)
    }

    /// Reset a subsystem's level to the plist/hardcoded default.
    public func resetLevel(for subsystem: Subsystem) {
        defaults.removeObject(forKey: subsystem.defaultsKey)
    }

    // MARK: - Directory Management

    /// Create the log directory (with intermediates) if it doesn't exist.
    public func ensureLogDirectoryExists() {
        let dir = logDirectory
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    /// Reset the log directory override to the default Application Support path.
    public func resetLogDirectory() {
        defaults.removeObject(forKey: "MKSLog.directory")
    }

    // MARK: - File Operations

    /// Clear (truncate) all log files.
    public func clearAllLogs() {
        let fm = FileManager.default
        // Collect unique file names to avoid truncating the shared transmux file twice.
        var cleared = Set<String>()
        for subsystem in Subsystem.allCases {
            let path = filePath(for: subsystem)
            guard !cleared.contains(path) else { continue }
            cleared.insert(path)
            if fm.fileExists(atPath: path) {
                // Truncate by overwriting with empty data.
                fm.createFile(atPath: path, contents: nil)
            }
        }
    }

    /// Clear a single subsystem's log file.
    public func clearLog(for subsystem: Subsystem) {
        let path = filePath(for: subsystem)
        if FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
    }
}
