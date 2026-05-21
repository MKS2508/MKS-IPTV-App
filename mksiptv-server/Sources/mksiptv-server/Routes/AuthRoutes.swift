import Vapor

/// Authentication Routes
///
/// Handles OIDC authentication flow endpoints:
/// - /auth/login - Redirect to PocketID
/// - /auth/callback - OAuth callback
/// - /auth/validate - Validate token/session
/// - /auth/logout - Clear session
/// - /auth/info - Get user info
public struct AuthRoutes: RouteCollection {
    /// OIDC provider
    private let oidcProvider: OIDCProvider

    /// Auth session manager
    private let authSession: AuthSession

    /// JWT validator
    private let jwtValidator: JWTValidator

    /// Client credentials
    private let credentials: OIDCProvider.ClientCredentials

    /// Initialize Auth Routes
    ///
    /// - Parameters:
    ///   - oidcProvider: OIDC provider instance
    ///   - authSession: Auth session manager
    ///   - jwtValidator: JWT validator
    ///   - credentials: OIDC client credentials
    public init(
        oidcProvider: OIDCProvider,
        authSession: AuthSession,
        jwtValidator: JWTValidator,
        credentials: OIDCProvider.ClientCredentials
    ) {
        self.oidcProvider = oidcProvider
        self.authSession = authSession
        self.jwtValidator = jwtValidator
        self.credentials = credentials
    }

    /// Register routes
    ///
    /// - Parameter app: Vapor application
    /// - Throws: Error if registration fails
    public func boot(routes: RoutesBuilder) throws {
        let auth = routes.grouped("auth")

        // GET /auth/login - Redirect to PocketID
        auth.get("login", use: login)

        // GET /auth/callback - OAuth callback
        auth.get("callback", use: callback)

        // POST /auth/validate - Validate token
        auth.post("validate", use: validate)

        // POST /auth/logout - Clear session
        auth.post("logout", use: logout)

        // GET /auth/info - Get user info
        auth.get("info", use: info)

        MKSLog.auth.info("Auth routes registered")
    }

    /// Login Handler
    ///
    /// Redirects user to PocketID for authentication.
    ///
    /// - Parameter req: Vapor request
    /// - Returns: Response redirecting to PocketID
    func login(_ req: Request) async throws -> Response {
        MKSLog.auth.info("Login requested")

        // Generate state and nonce for security
        let state = generateRandomToken()
        let nonce = generateRandomToken()

        // Store state in session for callback validation
        req.session.data["oauth_state"] = state
        req.session.data["oauth_nonce"] = nonce

        // Get authorization URL
        let authURL = try await oidcProvider.getAuthorizationURL(
            state: state,
            nonce: nonce
        )

        MKSLog.auth.info("Redirecting to PocketID", fields: [
            "state": state,
            "authURL": authURL.prefix(50) + "..."
        ])

        return Response(
            status: .seeOther,
            headers: ["Location": authURL]
        )
    }

    /// Callback Handler
    ///
    /// Handles OAuth callback from PocketID.
    ///
    /// - Parameter req: Vapor request
    /// - Returns: Response with session cookie or error
    func callback(_ req: Request) async throws -> Response {
        MKSLog.auth.info("OAuth callback received")

        // Extract parameters
        guard let code = try? req.query.get(String.self, at: "code") else {
            MKSLog.auth.error("Missing authorization code")

            throw Abort(.badRequest, reason: "Missing authorization code")
        }

        guard let state = try? req.query.get(String.self, at: "state") else {
            MKSLog.auth.error("Missing state parameter")

            throw Abort(.badRequest, reason: "Missing state parameter")
        }

        // Validate state
        let storedState = req.session.data["oauth_state"]
        guard storedState == state else {
            MKSLog.auth.error("Invalid state parameter", fields: [
                "received": state,
                "stored": storedState ?? "none"
            ])

            throw Abort(.badRequest, reason: "Invalid state parameter")
        }

        // Clear state from session
        req.session.data["oauth_state"] = nil

        do {
            // Exchange code for tokens
            let tokenResponse = try await oidcProvider.exchangeCodeForToken(code: code)

            // Fetch user info
            let userInfo = try await oidcProvider.fetchUserInfo(
                accessToken: tokenResponse.accessToken
            )

            // Create session
            let sessionID = await authSession.createSession(
                userInfo: userInfo,
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken,
                idToken: tokenResponse.idToken,
                expiresIn: tokenResponse.expiresIn ?? 3600
            )

            MKSLog.auth.info("Authentication successful", fields: [
                "sessionID": sessionID.prefix(8),
                "sub": (userInfo["sub"] as? String) ?? "unknown"
            ])

            // Create response
            let result: [String: Any] = [
                "status": "authenticated",
                "message": "Login successful",
                "sessionID": sessionID
            ]

            let response = Response(
                status: .ok,
                body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
            )

            // Set session cookie
            response.cookies["session"] = HTTPCookies.Value(
                string: sessionID,
                expires: Date().addingTimeInterval(3600),
                maxAge: 3600
            )

            return response

        } catch {
            MKSLog.auth.error("Authentication failed", fields: ["error": error.localizedDescription])

            throw Abort(.internalServerError, reason: "Authentication failed: \(error.localizedDescription)")
        }
    }

    /// Validate Handler
    ///
    /// Validates access token or session.
    ///
    /// - Parameter req: Vapor request
    /// - Returns: Validation result
    func validate(_ req: Request) async throws -> Response {
        MKSLog.auth.debug("Validate requested")

        // Try token validation first
        if let token = req.headers.bearerAuthorization?.token {
            MKSLog.auth.debug("Validating bearer token")

            do {
                let jwksURI = try await oidcProvider.getJWKSURI()
                let issuer = Environment.get("OIDC_ISSUER")!

                let payload = try await jwtValidator.validate(
                    token: token,
                    jwksURI: jwksURI,
                    issuer: issuer,
                    audience: credentials.clientId
                )

                let result: [String: Any] = [
                    "valid": true,
                    "type": "token",
                    "sub": payload["sub"] as? String ?? "",
                    "exp": payload["exp"] as? TimeInterval ?? 0
                ]

                return Response(
                    status: .ok,
                    body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
                )
            } catch {
                MKSLog.auth.warning("Token validation failed", fields: ["error": error.localizedDescription])

                let result: [String: Any] = [
                    "valid": false,
                    "type": "token",
                    "error": error.localizedDescription
                ]

                return Response(
                    status: .ok,
                    body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
                )
            }
        }

        // Try session validation
        if let sessionID = req.cookies["session"]?.string {
            MKSLog.auth.debug("Validating session", fields: ["sessionID": sessionID.prefix(8)])

            if let userInfo = await authSession.validateSession(sessionID) {
                let result: [String: Any] = [
                    "valid": true,
                    "type": "session",
                    "sub": userInfo["sub"] as? String ?? "",
                    "sessionID": sessionID
                ]

                return Response(
                    status: .ok,
                    body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
                )
            } else {
                let result: [String: Any] = [
                    "valid": false,
                    "type": "session",
                    "error": "Invalid or expired session"
                ]

                return Response(
                    status: .ok,
                    body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
                )
            }
        }

        MKSLog.auth.warning("No token or session provided")

        throw Abort(.badRequest, reason: "No token or session provided")
    }

    /// Logout Handler
    ///
    /// Clears user session.
    ///
    /// - Parameter req: Vapor request
    /// - Returns: Success response
    func logout(_ req: Request) async throws -> Response {
        MKSLog.auth.info("Logout requested")

        // Get session ID from cookie
        guard let sessionID = req.cookies["session"]?.string else {
            throw Abort(.badRequest, reason: "No session found")
        }

        // Remove session
        let removed = await authSession.removeSession(sessionID)

        MKSLog.auth.info("Logout completed", fields: [
            "sessionID": sessionID.prefix(8),
            "removed": removed
        ])

        // Create response
        let result = ["status": "ok", "message": "Logged out"]
        let response = Response(
            status: .ok,
            body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
        )

        // Clear session cookie
        response.cookies["session"] = HTTPCookies.Value(
            string: "",
            expires: .distantPast
        )

        return response
    }

    /// Info Handler
    ///
    /// Returns authenticated user information.
    ///
    /// - Parameter req: Vapor request
    /// - Returns: User info
    func info(_ req: Request) async throws -> Response {
        MKSLog.auth.debug("User info requested")

        // Get session ID from cookie
        guard let sessionID = req.cookies["session"]?.string else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }

        // Validate session and get user info
        guard let session = await authSession.getSession(sessionID) else {
            throw Abort(.unauthorized, reason: "Invalid or expired session")
        }

        let result: [String: Any] = [
            "sub": session.sub,
            "name": session.name as Any,
            "email": session.email as Any,
            "sessionID": sessionID,
            "expiresAt": ISO8601DateFormatter().string(from: session.expiresAt)
        ]

        return Response(
            status: .ok,
            body: .init(string: try JSONSerialization.data(withJSONObject: result).toString())
        )
    }

    /// Generate cryptographically secure random token
    ///
    /// - Returns: Random token string
    private func generateRandomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}

// MARK: - Data Extension

private extension Data {
    /// Convert Data to String
    func toString() -> String {
        return String(data: self, encoding: .utf8) ?? ""
    }
}
