import Foundation

// MARK: - Stream Proxy Protocol

/// Protocol for proxying HTTPS streams to local HTTP for FFmpeg compatibility.
/// FFmpeg's bundled builds often lack HTTPS protocol support, requiring
/// external proxies like URLSession to handle HTTPS connections.
public protocol StreamProxyProvider {
    /// Start proxying the given HTTPS URL to a local HTTP endpoint.
    /// - Parameter url: The HTTPS URL to proxy
    /// - Returns: A ProxySession containing the local HTTP URL and session ID
    /// - Throws: If the proxy cannot be started
    func startProxy(for url: URL) async throws -> ProxySession

    /// Stop an active proxy session.
    /// - Parameter sessionID: The ID of the session to stop
    func stop(sessionID: Int) async
}

/// A proxy session representing an active HTTPS-to-HTTP proxy.
public struct ProxySession {
    /// Unique identifier for this proxy session
    public let id: Int

    /// Local HTTP URL that proxies the original HTTPS URL
    public let localURL: URL

    public init(id: Int, localURL: URL) {
        self.id = id
        self.localURL = localURL
    }
}
