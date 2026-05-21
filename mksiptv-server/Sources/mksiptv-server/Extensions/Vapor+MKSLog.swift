import Vapor
import Foundation

// MARK: - MKSLog Server Implementation

/// Server-compatible logging system that mirrors MKSLog from IPTVCore
/// but uses Vapor's Logger instead of os.Logger (unavailable on Linux).
///
/// **Usage**:
/// ```swift
/// MKSLog.server.info("Server starting on port 4848")
/// MKSLog.server.warning("High memory usage: 512MB")
/// MKSLog.server.error("Failed to connect to database: \(error)")
/// ```
public enum MKSLog {

    // MARK: - Categories

    public static var server = Logger(category: "server")
    public static var api = Logger(category: "api")
    public static var auth = Logger(category: "auth")
    public static var download = Logger(category: "download")
    public static var stream = Logger(category: "stream")
    public static var network = Logger(category: "network")
    public static var diagnostics = Logger(category: "diagnostics") // renamed from 'debug' to avoid conflict

    // MARK: - Session Management

    /// Session ID for correlating events across logs.
    public static var sessionID: String = UUID().uuidString.prefix(8).lowercased().description

    /// Start a new logging session.
    public static func startSession(serverType: String, version: String) {
        sessionID = UUID().uuidString.prefix(8).lowercased().description
        let ts = ISO8601DateFormatter().string(from: Date())
        let separator = String(repeating: "=", count: 60)
        let entry = "\n\(separator)\n[\(ts)] [INF] [session] SESSION_START session=\(sessionID) server=\(serverType) version=\(version)\n\(separator)\n"
        print(entry)
        server.info("SESSION_START server=\(serverType) version=\(version)")
    }

    /// End the current logging session.
    public static func endSession() {
        let ts = ISO8601DateFormatter().string(from: Date())
        let separator = String(repeating: "=", count: 60)
        let entry = "\n\(separator)\n[\(ts)] [INF] [session] SESSION_END session=\(sessionID)\n\(separator)\n"
        print(entry)
        server.info("SESSION_END")
    }

    // MARK: - Logger

    /// A lightweight logger that wraps Vapor's Logger.
    public struct Logger {
        public let category: String
        public var logger: Vapor.Logger?

        public init(category: String) {
            self.category = category
            self.logger = nil // Will be set during app configuration
        }

        public func debug(_ message: String, fields: [String: Any]? = nil) {
            emit(level: .debug, message: message, fields: fields)
        }

        public func info(_ message: String, fields: [String: Any]? = nil) {
            emit(level: .info, message: message, fields: fields)
        }

        public func warning(_ message: String, fields: [String: Any]? = nil) {
            emit(level: .warning, message: message, fields: fields)
        }

        public func error(_ message: String, fields: [String: Any]? = nil) {
            emit(level: .error, message: message, fields: fields)
        }

        private func emit(level: LogLevel, message: String, fields: [String: Any]?) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var logMessage = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(category)] \(message)"

            if let fields = fields {
                let fieldsStr = fields.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                logMessage += " [\(fieldsStr)]"
            }

            // Print to stdout (captured by Vapor's logging system)
            print(logMessage)

            // Also use Vapor's logger if available
            if let logger = logger {
                switch level {
                case .debug:
                    logger.debug("\(message)")
                case .info:
                    logger.info("\(message)")
                case .warning:
                    logger.warning("\(message)")
                case .error:
                    logger.error("\(message)")
                }
            }
        }
    }

    // MARK: - LogLevel

    public enum LogLevel: String {
        case debug
        case info
        case warning
        case error
    }

    // MARK: - ISO8601 Formatter

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withYear,
            .withMonth,
            .withDay,
            .withTime
        ]
        return formatter
    }()
}

// MARK: - Application+MKSLog

extension Application {
    /// Configure MKSLog with Vapor's logger.
    public func configureMKSLog() {
        MKSLog.server.logger = self.logger
        MKSLog.api.logger = self.logger
        MKSLog.auth.logger = self.logger
        MKSLog.download.logger = self.logger
        MKSLog.stream.logger = self.logger
        MKSLog.network.logger = self.logger
        MKSLog.diagnostics.logger = self.logger
    }
}
