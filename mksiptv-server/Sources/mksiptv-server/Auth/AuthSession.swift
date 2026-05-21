import Vapor
import Foundation

/// Authentication Session Manager
///
/// Actor-based session storage for managing authenticated user sessions.
/// Thread-safe access to session data with automatic TTL expiration.
public actor AuthSession {
    /// User session data
    public struct UserSession: Codable {
        public let id: String
        public let sub: String
        public let name: String?
        public let email: String?
        public let accessToken: String
        public let refreshToken: String?
        public let idToken: String?
        public let createdAt: Date
        public let expiresAt: Date

        public init(
            id: String,
            sub: String,
            name: String? = nil,
            email: String? = nil,
            accessToken: String,
            refreshToken: String? = nil,
            idToken: String? = nil,
            expiresAt: Date
        ) {
            self.id = id
            self.sub = sub
            self.name = name
            self.email = email
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.idToken = idToken
            self.createdAt = Date()
            self.expiresAt = expiresAt
        }

        /// Check if session is expired
        public var isExpired: Bool {
            return Date() > expiresAt
        }

        /// Time until expiration in seconds
        public var timeUntilExpiry: TimeInterval {
            return max(0, expiresAt.timeIntervalSince(Date()))
        }
    }

    /// Active sessions storage [sessionID: UserSession]
    private var sessions: [String: UserSession] = [:]

    /// User to session mapping [userID: sessionID]
    private var userSessions: [String: String] = [:]

    /// Session TTL in seconds (default: 1 hour)
    private let sessionTTL: TimeInterval

    /// Initialize Auth Session Manager
    ///
    /// - Parameter sessionTTL: Session time-to-live in seconds (default: 3600)
    public init(sessionTTL: TimeInterval = 3600) {
        self.sessionTTL = sessionTTL

        MKSLog.auth.info("AuthSession initialized", fields: ["sessionTTL": sessionTTL])
    }

    /// Create new session from user info and tokens
    ///
    /// - Parameters:
    ///   - userInfo: User information from OIDC
    ///   - accessToken: OAuth access token
    ///   - refreshToken: OAuth refresh token (optional)
    ///   - idToken: OAuth ID token (optional)
    ///   - expiresIn: Access token expiry in seconds (default: 3600)
    /// - Returns: Session ID
    public func createSession(
        userInfo: [String: Any],
        accessToken: String,
        refreshToken: String? = nil,
        idToken: String? = nil,
        expiresIn: Int = 3600
    ) -> String {
        // Generate session ID
        let sessionID = UUID().uuidString

        // Extract user info
        let sub = (userInfo["sub"] as? String) ?? ""
        let name = userInfo["name"] as? String
        let email = userInfo["email"] as? String

        // Calculate expiry
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        // Create session
        let session = UserSession(
            id: sessionID,
            sub: sub,
            name: name,
            email: email,
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            expiresAt: expiresAt
        )

        // Store session
        sessions[sessionID] = session
        userSessions[sub] = sessionID

        MKSLog.auth.info("Session created", fields: [
            "sessionID": sessionID.prefix(8),
            "sub": sub,
            "expiresIn": expiresIn
        ])

        return sessionID
    }

    /// Get session by ID
    ///
    /// - Parameter sessionID: Session identifier
    /// - Returns: User session if found and not expired
    public func getSession(_ sessionID: String) -> UserSession? {
        guard let session = sessions[sessionID] else {
            MKSLog.auth.debug("Session not found", fields: ["sessionID": sessionID.prefix(8)])

            return nil
        }

        if session.isExpired {
            MKSLog.auth.debug("Session expired", fields: ["sessionID": sessionID.prefix(8)])

            // Clean up expired session
            removeSession(sessionID)

            return nil
        }

        return session
    }

    /// Get session by user ID
    ///
    /// - Parameter sub: User subject identifier
    /// - Returns: User session if found and not expired
    public func getSessionByUser(_ sub: String) -> UserSession? {
        guard let sessionID = userSessions[sub] else {
            return nil
        }

        return getSession(sessionID)
    }

    /// Validate session and return user info
    ///
    /// - Parameter sessionID: Session identifier
    /// - Returns: User info if session is valid
    public func validateSession(_ sessionID: String) -> [String: Any]? {
        guard let session = getSession(sessionID) else {
            return nil
        }

        return [
            "sub": session.sub,
            "name": session.name as Any,
            "email": session.email as Any,
            "expiresAt": ISO8601DateFormatter().string(from: session.expiresAt)
        ]
    }

    /// Remove session
    ///
    /// - Parameter sessionID: Session identifier
    /// - Returns: True if session was removed
    public func removeSession(_ sessionID: String) -> Bool {
        guard let session = sessions[sessionID] else {
            return false
        }

        sessions.removeValue(forKey: sessionID)
        userSessions.removeValue(forKey: session.sub)

        MKSLog.auth.info("Session removed", fields: [
            "sessionID": sessionID.prefix(8),
            "sub": session.sub
        ])

        return true
    }

    /// Clean up all expired sessions
    ///
    /// - Returns: Number of sessions cleaned up
    public func cleanupExpiredSessions() -> Int {
        let now = Date()
        var cleaned = 0

        for (sessionID, session) in sessions {
            if session.expiresAt < now {
                _ = removeSession(sessionID)
                cleaned += 1
            }
        }

        if cleaned > 0 {
            MKSLog.auth.info("Cleaned up expired sessions", fields: ["count": cleaned])
        }

        return cleaned
    }

    /// Get active session count
    public var activeSessionCount: Int {
        return sessions.count
    }

    /// Get all active sessions (for debugging)
    public var allSessions: [UserSession] {
        return Array(sessions.values)
    }
}
