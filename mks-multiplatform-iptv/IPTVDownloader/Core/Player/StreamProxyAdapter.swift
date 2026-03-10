import Foundation
import TransmuxCore

// MARK: - StreamProxy Adapter

/// Adapts the app's `StreamProxy` to the `StreamProxyProvider` protocol
/// required by `TransmuxCore`.
///
/// This allows `TransmuxingService` to proxy HTTPS URLs through the app's
/// URLSession-based streaming proxy without direct dependency on app-specific code.
///
/// ## Usage
/// ```swift
/// import TransmuxCore
///
/// let service = TransmuxingService(streamProxy: StreamProxyAdapter())
/// let session = try await service.startTransmux(from: httpsURL)
/// ```
struct StreamProxyAdapter: StreamProxyProvider {

    /// Starts proxying the given HTTPS URL through the app's StreamProxy.
    /// - Parameter url: The HTTPS URL to proxy
    /// - Returns: A `ProxySession` with the local HTTP URL and session ID
    /// - Throws: If the proxy cannot be started
    func startProxy(for url: URL) async throws -> TransmuxCore.ProxySession {
        let appSession = try await StreamProxy.shared.startProxy(for: url)

        return TransmuxCore.ProxySession(
            id: appSession.id,
            localURL: appSession.localURL
        )
    }

    /// Stops an active proxy session.
    /// - Parameter sessionID: The ID of the session to stop
    func stop(sessionID: Int) async {
        await StreamProxy.shared.stop(sessionID: sessionID)
    }
}
