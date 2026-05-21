import Vapor
import JWT
import Foundation

// MARK: - Main Entry Point

// Configure and run the server
var env = try Environment.detect()
try LoggingSystem.bootstrap(from: &env)

let app = Application(env)
defer { try? app.shutdown() }

// Configure MKSLog
app.configureMKSLog()

// Start logging session
MKSLog.startSession(serverType: "mksiptv-server", version: "1.0.0")

// Configure middleware and routes
try await configure(app)

// Run the server
try await app.execute()

// MARK: - Server Configuration

func configure(_ app: Application) async throws {
    // Register middleware
    app.middleware.use(CORSMiddleware(
        configuration: .init(
            allowedOrigin: .all,
            allowedMethods: [.GET, .POST, .PUT, .DELETE, .OPTIONS],
            allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
        )
    ))

    // Initialize profile store
    let profileStore = try ProfileStore()

    // Initialize event bus
    let eventBus = EventBus()

    // Initialize download manager
    let downloadPath = Environment.get("DOWNLOAD_PATH")
    let downloadManager = ServerDownloadManager(eventBus: eventBus, downloadPath: downloadPath)

    // MARK: - OIDC Authentication Setup

    // Initialize OIDC provider
    guard let oidcIssuer = Environment.get("OIDC_ISSUER") else {
        MKSLog.server.error("OIDC_ISSUER environment variable not set")
        throw Abort(.internalServerError, reason: "OIDC_ISSUER environment variable not set")
    }

    guard let oidcClientID = Environment.get("OIDC_CLIENT_ID") else {
        MKSLog.server.error("OIDC_CLIENT_ID environment variable not set")
        throw Abort(.internalServerError, reason: "OIDC_CLIENT_ID environment variable not set")
    }

    guard let oidcClientSecret = Environment.get("OIDC_CLIENT_SECRET") else {
        MKSLog.server.error("OIDC_CLIENT_SECRET environment variable not set")
        throw Abort(.internalServerError, reason: "OIDC_CLIENT_SECRET environment variable not set")
    }

    let oidcRedirectURI = Environment.get("OIDC_REDIRECT_URI") ?? "http://localhost:4848/auth/callback"
    let oidcScopes = (Environment.get("OIDC_SCOPES") ?? "openid profile email").components(separatedBy: " ")
    let sessionTTL = TimeInterval(Environment.get("SESSION_TTL") ?? "3600") ?? 3600

    let credentials = OIDCProvider.ClientCredentials(
        clientId: oidcClientID,
        clientSecret: oidcClientSecret,
        redirectURI: oidcRedirectURI,
        scopes: oidcScopes
    )

    let oidcProvider = OIDCProvider(
        issuer: oidcIssuer,
        credentials: credentials,
        client: app.client
    )

    // Initialize auth session
    let authSession = AuthSession(sessionTTL: sessionTTL)

    // Initialize JWT validator
    let jwtValidator = JWTValidator(client: app.client)

    // Register auth routes BEFORE other routes
    let authRoutes = AuthRoutes(
        oidcProvider: oidcProvider,
        authSession: authSession,
        jwtValidator: jwtValidator,
        credentials: credentials
    )
    try app.register(collection: authRoutes)

    // Apply auth middleware globally EXCEPT public paths
    app.middleware.use(AuthMiddleware(
        authSession: authSession,
        publicPaths: ["/health", "/", "/auth/login", "/auth/callback"]
    ))

    MKSLog.server.info("OIDC authentication initialized", fields: [
        "issuer": oidcIssuer,
        "clientId": oidcClientID,
        "redirectURI": oidcRedirectURI,
        "sessionTTL": sessionTTL
    ])

    // Register profile routes
    try app.register(collection: ProfileRoutes(profileStore: profileStore))

    // Register live channel routes
    try app.register(collection: LiveChannelRoutes(profileStore: profileStore))

    // Register movie routes
    try app.register(collection: MovieRoutes(profileStore: profileStore))

    // Register series routes
    try app.register(collection: SerieRoutes(profileStore: profileStore))

    // Register search routes
    try app.register(collection: SearchRoutes(profileStore: profileStore))

    // Register download routes
    try app.register(collection: DownloadRoutes(downloadManager: downloadManager, profileStore: profileStore))

    // Register WebSocket event routes
    try app.register(collection: EventRoutes(eventBus: eventBus))

    // Health check endpoint
    app.get("health") { req -> [String: String] in
        MKSLog.api.debug("Health check requested")

        return [
            "status": "ok",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
    }

    // Root endpoint
    app.get { req -> [String: String] in
        MKSLog.api.info("Root endpoint requested")

        return [
            "message": "MKS IPTV Server API",
            "version": "1.0.0",
            "endpoints": "GET /health, GET /profiles, POST /profiles, GET /live-channels, GET /movies, GET /series, GET /search, GET /downloads, POST /downloads, WS /ws/events"
        ]
    }

    // Configure server
    let port = Environment.get("PORT").flatMap(Int.init) ?? 4848
    app.http.server.configuration.hostname = Environment.get("HOST") ?? "0.0.0.0"
    app.http.server.configuration.port = port

    // Log server startup with MKSLog
    MKSLog.server.info("Server starting on port \(port)", fields: ["host": app.http.server.configuration.hostname])
}
