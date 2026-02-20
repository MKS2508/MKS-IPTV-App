import Foundation

#if canImport(FlyingFox)
import FlyingFox
#endif

// MARK: - Local HLS Server

/// Lightweight HTTP server that serves transmuxed HLS segments to AVPlayer.
/// Uses FlyingFox for the HTTP layer. When FlyingFox is not available,
/// falls back to returning file:// URLs (works for local playback but not AirPlay).
actor LocalHLSServer {
    static let shared = LocalHLSServer()

    private var isRunning = false
    private var serverPort: UInt16 = 0
    private var servingDirectory: URL?

    #if canImport(FlyingFox)
    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?
    #endif

    private init() {}

    // MARK: - Public API

    /// Start serving HLS content from the given directory.
    /// - Parameters:
    ///   - directory: Directory containing HLS segments (.m4s) and playlist (.m3u8 or .mp4).
    ///   - playlist: Filename of the playlist (e.g. "stream.m3u8" or "stream.mp4").
    /// - Returns: The HTTP URL to the playlist (e.g. http://localhost:8142/stream.m3u8).
    func serve(directory: URL, playlist: String) async throws -> URL {
        // Stop any previous server
        stop()

        #if canImport(FlyingFox)
        let port = randomPort()
        self.serverPort = port
        self.servingDirectory = directory
        self.isRunning = true

        let dir = directory

        let server = HTTPServer(port: port)

        // Route: serve any file from the segment directory
        await server.appendRoute("GET /*") { request in
            let path = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let filePath = dir.appendingPathComponent(path)

            guard FileManager.default.fileExists(atPath: filePath.path) else {
                return HTTPResponse(statusCode: .notFound)
            }

            let data = try Data(contentsOf: filePath)
            let contentType = Self.mimeType(for: filePath.pathExtension)

            return HTTPResponse(
                statusCode: .ok,
                headers: [
                    HTTPHeader("Content-Type"): contentType,
                    HTTPHeader("Access-Control-Allow-Origin"): "*",
                    HTTPHeader("Cache-Control"): "no-cache"
                ],
                body: data
            )
        }

        self.server = server

        // Start server in background
        self.serverTask = Task.detached { [server] in
            do {
                try await server.start()
            } catch {
                print("[LocalHLSServer] Server stopped: \(error)")
            }
        }

        let url = URL(string: "http://localhost:\(port)/\(playlist)")!
        print("[LocalHLSServer] Serving at \(url)")
        return url
        #else
        // FlyingFox not available — return file URL directly
        let fileURL = directory.appendingPathComponent(playlist)
        print("[LocalHLSServer] FlyingFox not available, using file URL: \(fileURL)")
        return fileURL
        #endif
    }

    /// Stop the HTTP server and clean up.
    func stop() {
        #if canImport(FlyingFox)
        serverTask?.cancel()
        serverTask = nil
        server = nil
        #endif

        if let dir = servingDirectory {
            try? FileManager.default.removeItem(at: dir)
        }

        isRunning = false
        servingDirectory = nil
        print("[LocalHLSServer] Stopped")
    }

    /// Whether the server is currently running.
    var running: Bool { isRunning }

    // MARK: - Private Helpers

    /// Pick a random port in the 8100-8999 range.
    private func randomPort() -> UInt16 {
        UInt16.random(in: 8100...8999)
    }

    /// Map file extension to MIME type for HLS content.
    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "m4s":
            return "video/iso.segment"
        case "mp4":
            return "video/mp4"
        case "ts":
            return "video/mp2t"
        case "m4a":
            return "audio/mp4"
        default:
            return "application/octet-stream"
        }
    }
}
