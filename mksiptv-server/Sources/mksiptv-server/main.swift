import Vapor
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
