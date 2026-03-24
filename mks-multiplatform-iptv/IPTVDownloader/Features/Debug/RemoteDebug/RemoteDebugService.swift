import Foundation
import Network

// MARK: - Remote Command

/// Commands sent from the viewer to the iOS app.
enum RemoteCommand: String, Codable, Sendable {
    case play
    case pause
    case stop
    case getDebugInfo
    case forceReloadPipeline
}

/// Typed command message received via WebSocket.
struct RemoteCommandMessage: Codable, Sendable {
    let type: String // "command"
    let command: String
    let payload: [String: String]?
}

// MARK: - Remote Debug Service

/// Orchestrates the remote debugging system:
/// 1. Browses for `_mksiptv-debug._tcp` Bonjour services on the LAN
/// 2. Connects to the first discovered viewer via WebSocket
/// 3. Forwards all MKSLog output to the viewer in real-time
/// 4. Receives commands from the viewer and dispatches them
///
/// **Lifecycle**: Created at app launch, starts browsing automatically.
/// Call `stop()` when the app terminates.
@MainActor
@Observable
final class RemoteDebugService {

    // MARK: - Singleton

    static let shared = RemoteDebugService()

    // MARK: - Observable State

    /// Whether currently connected to a remote viewer.
    private(set) var isConnected = false

    /// Name of the connected viewer (from Bonjour TXT record).
    private(set) var viewerName: String?

    /// Whether Bonjour is actively browsing for viewers.
    private(set) var isBrowsing = false

    // MARK: - Callbacks

    /// Called when a remote command is received. Set by the app to wire up player actions.
    var onCommand: ((RemoteCommand) -> Void)?

    /// Called when a seek command is received with a position.
    var onSeek: ((Double) -> Void)?

    /// Called when a channel change command is received.
    var onChangeChannel: ((Int) -> Void)?

    /// Called when a log level change is requested.
    var onSetLogLevel: ((String) -> Void)?

    // MARK: - Private

    private let transport = RemoteLogTransport()
    private var browser: NWBrowser?
    private let bonjourType = "_mksiptv-debug._tcp"
    private let decoder = JSONDecoder()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Start Bonjour browsing and auto-connect to the first viewer found.
    func start() {
        guard browser == nil else { return }
        MKSLog.debug.info("RemoteDebug: Starting Bonjour browse for \(bonjourType)")

        let params = NWParameters()
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: bonjourType, domain: nil), using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isBrowsing = true
                    MKSLog.debug.info("RemoteDebug: Bonjour browser ready")
                case .failed(let error):
                    self?.isBrowsing = false
                    MKSLog.debug.error("RemoteDebug: Bonjour browser failed: \(error)")
                case .cancelled:
                    self?.isBrowsing = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                await self?.handleBrowseResults(results)
            }
        }

        browser.start(queue: .main)
    }

    /// Stop browsing and disconnect.
    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        Task { await transport.disconnect() }
        isConnected = false
        viewerName = nil
        MKSLog.remoteTransport = nil
        MKSLog.debug.info("RemoteDebug: Stopped")
    }

    // MARK: - Private: Bonjour Discovery

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        // Connect to the first discovered viewer
        guard let result = results.first else { return }

        switch result.endpoint {
        case .service(let name, let type, let domain, _):
            MKSLog.debug.info("RemoteDebug: Found viewer '\(name)' (\(type) in \(domain))")
            viewerName = name
            resolveAndConnect(result: result)
        default:
            break
        }
    }

    private func resolveAndConnect(result: NWBrowser.Result) {
        // Use NWConnection to resolve the Bonjour endpoint to an IP:port
        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                // Extract resolved IP and port from the connection's path
                if let path = connection.currentPath,
                   let endpoint = path.remoteEndpoint {
                    let host: String
                    let port: UInt16
                    switch endpoint {
                    case .hostPort(let h, let p):
                        host = "\(h)"
                        port = p.rawValue
                    default:
                        connection.cancel()
                        return
                    }
                    connection.cancel()

                    // Extract WS path from TXT record
                    var wsPath = "/ws/device"
                    if case .service(_, _, _, _) = result.endpoint {
                        if let txtData = result.metadata as? NWBrowser.Result.Metadata,
                           case let .bonjour(record) = txtData {
                            wsPath = record.dictionary["ws"] ?? "/ws/device"
                        }
                    }

                    let wsURL = URL(string: "ws://\(host):\(port)\(wsPath)")!
                    Task { @MainActor in
                        self?.connectWebSocket(to: wsURL)
                    }
                }
            case .failed:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .global(qos: .utility))
    }

    // MARK: - Private: WebSocket

    private func connectWebSocket(to url: URL) {
        MKSLog.debug.info("RemoteDebug: Connecting WS to \(url.absoluteString)")

        // Wire up command handling
        Task {
            await transport.setOnMessage { [weak self] data in
                Task { @MainActor in
                    self?.handleIncomingMessage(data)
                }
            }
            await transport.connect(to: url)
        }

        isConnected = true
        MKSLog.remoteTransport = transport
        MKSLog.debug.info("RemoteDebug: Connected to viewer")
    }

    // MARK: - Private: Command Handling

    private func handleIncomingMessage(_ data: Data) {
        guard let message = try? decoder.decode(RemoteCommandMessage.self, from: data) else {
            MKSLog.debug.warning("RemoteDebug: Failed to decode command message")
            return
        }

        guard message.type == "command" else { return }

        MKSLog.debug.info("RemoteDebug: Received command '\(message.command)'")

        // Handle typed commands
        if let cmd = RemoteCommand(rawValue: message.command) {
            onCommand?(cmd)
            return
        }

        // Handle parameterized commands
        switch message.command {
        case "seek":
            if let posStr = message.payload?["position"], let pos = Double(posStr) {
                onSeek?(pos)
            }
        case "changeChannel":
            if let idStr = message.payload?["streamId"], let id = Int(idStr) {
                onChangeChannel?(id)
            }
        case "setLogLevel":
            if let level = message.payload?["level"] {
                onSetLogLevel?(level)
            }
        default:
            MKSLog.debug.warning("RemoteDebug: Unknown command '\(message.command)'")
        }
    }
}
