import Vapor

/// Authentication Middleware
///
/// Protects routes by requiring valid authentication sessions.
/// Allows public paths to bypass authentication.
public struct AuthMiddleware: Middleware {
    /// Authentication session manager
    private let authSession: AuthSession

    /// Paths that don't require authentication
    private let publicPaths: [String]

    /// Initialize Auth Middleware
    ///
    /// - Parameters:
    ///   - authSession: Auth session manager
    ///   - publicPaths: Paths to exempt from authentication
    public init(authSession: AuthSession, publicPaths: [String] = []) {
        self.authSession = authSession
        self.publicPaths = publicPaths

        MKSLog.auth.info("AuthMiddleware initialized", fields: [
            "publicPaths": publicPaths.count
        ])
    }

    /// Middleware responder
    ///
    /// - Parameters:
    ///   - request: Incoming request
    ///   - next: Next responder in chain
    /// - Returns: EventLoopFuture<Response>
    public func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        // Check if path is public
        let path = request.url.path

        if isPublicPath(path) {
            MKSLog.auth.debug("Public path, skipping auth", fields: ["path": path])

            return next.respond(to: request)
        }

        // Extract session from Authorization header or cookie
        let sessionID = extractSessionID(from: request)

        guard let sessionID = sessionID else {
            MKSLog.auth.warning("Missing session ID", fields: ["path": path])

            return request.eventLoop.makeSucceededFuture(
                Response(
                    status: .unauthorized,
                    body: .init(
                        string: "{\"error\": \"Unauthorized\", \"message\": \"Missing authentication\"}"
                    )
                )
            )
        }

        // Validate session synchronously using event loop
        let promise = request.eventLoop.makePromise(of: Response.self)

        Task.detached {
            let userInfo = await self.authSession.validateSession(sessionID)

            guard let userInfo = userInfo else {
                MKSLog.auth.warning("Invalid or expired session", fields: [
                    "sessionID": sessionID.prefix(8),
                    "path": path
                ])

                promise.succeed(
                    Response(
                        status: .unauthorized,
                        body: .init(
                            string: "{\"error\": \"Unauthorized\", \"message\": \"Invalid or expired session\"}"
                        )
                    )
                )
                return
            }

            // Store user info in request for downstream handlers
            request.storage.set(AuthUserInfo.self, to: AuthUserInfo(userInfo))

            MKSLog.auth.debug("Session validated", fields: [
                "sessionID": sessionID.prefix(8),
                "sub": (userInfo["sub"] as? String) ?? "unknown",
                "path": path
            ])

            let response = try? await next.respond(to: request).get()
            promise.succeed(response ?? Response(status: .internalServerError))
        }

        return promise.futureResult
    }

    /// Check if path is public
    ///
    /// - Parameter path: Request path
    /// - Returns: True if path is public
    private func isPublicPath(_ path: String) -> Bool {
        return publicPaths.contains { publicPath in
            if publicPath.hasSuffix("/*") {
                let prefix = String(publicPath.dropLast(2))
                return path.hasPrefix(prefix)
            } else {
                return path == publicPath
            }
        }
    }

    /// Extract session ID from request
    ///
    /// - Parameter request: Incoming request
    /// - Returns: Session ID if found
    private func extractSessionID(from request: Request) -> String? {
        // Try Authorization header first: Bearer <sessionID>
        if let authHeader = request.headers.first(name: .authorization) {
            let parts = authHeader.split(separator: " ", maxSplits: 1)
            if parts.count == 2 && parts[0] == "Bearer" {
                return String(parts[1])
            }
        }

        // Try query parameter: ?session=<sessionID>
        if let sessionParam = try? request.query.get(String.self, at: "session") {
            return sessionParam
        }

        // Try cookie: session=<sessionID>
        if let sessionCookie = request.cookies["session"]?.string {
            return sessionCookie
        }

        return nil
    }
}

/// Auth User Info storage key
public struct AuthUserInfo: StorageKey {
    public typealias Value = AuthUserInfo

    public let userInfo: [String: Any]

    public init(_ userInfo: [String: Any]) {
        self.userInfo = userInfo
    }

    public var sub: String? {
        return userInfo["sub"] as? String
    }

    public var name: String? {
        return userInfo["name"] as? String
    }

    public var email: String? {
        return userInfo["email"] as? String
    }
}

/// Request extension for easy user info access
extension Request {
    /// Get authenticated user info
    public var authUser: AuthUserInfo? {
        return storage.get(AuthUserInfo.self)
    }

    /// Check if request is authenticated
    public var isAuthenticated: Bool {
        return authUser != nil
    }
}
