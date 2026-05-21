import Vapor
import Foundation

/// OIDC Provider Configuration and Discovery
///
/// Manages OpenID Connect discovery and endpoint resolution for PocketID integration.
/// Fetches and caches the OpenID Connect configuration document from the issuer.
public actor OIDCProvider {
    /// OIDC discovery configuration
    public struct DiscoveryConfig: Codable {
        public let issuer: String
        public let authorizationEndpoint: String
        public let tokenEndpoint: String
        public let userInfoEndpoint: String?
        public let jwksUri: String
        public let responseTypesSupported: [String]
        public let subjectTypesSupported: [String]
        public let idTokenSigningAlgValuesSupported: [String]
        public let scopesSupported: [String]?
        public let tokenEndpointAuthMethodsSupported: [String]?

        private enum CodingKeys: String, CodingKey {
            case issuer
            case authorizationEndpoint = "authorization_endpoint"
            case tokenEndpoint = "token_endpoint"
            case userInfoEndpoint = "userinfo_endpoint"
            case jwksUri = "jwks_uri"
            case responseTypesSupported = "response_types_supported"
            case subjectTypesSupported = "subject_types_supported"
            case idTokenSigningAlgValuesSupported = "id_token_signing_alg_values_supported"
            case scopesSupported = "scopes_supported"
            case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
        }
    }

    /// OIDC client credentials
    public struct ClientCredentials {
        public let clientId: String
        public let clientSecret: String
        public let redirectURI: String
        public let scopes: [String]

        public init(clientId: String, clientSecret: String, redirectURI: String, scopes: [String]) {
            self.clientId = clientId
            self.clientSecret = clientSecret
            self.redirectURI = redirectURI
            self.scopes = scopes
        }
    }

    /// Cached discovery configuration
    private var discoveryConfig: DiscoveryConfig?

    /// Provider configuration
    private let issuer: String
    private let credentials: ClientCredentials
    private let client: Client

    /// Initialize OIDC Provider
    ///
    /// - Parameters:
    ///   - issuer: OIDC issuer URL (e.g., https://pocketid.example.com)
    ///   - credentials: Client credentials for authentication
    ///   - client: HTTP client for requests
    public init(issuer: String, credentials: ClientCredentials, client: Client) {
        self.issuer = issuer.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.credentials = credentials
        self.client = client
    }

    /// Fetch discovery configuration from issuer
    ///
    /// - Returns: Discovery configuration
    /// - Throws: HTTPError if request fails
    public func fetchDiscoveryConfig() async throws -> DiscoveryConfig {
        if let cached = discoveryConfig {
            return cached
        }

        let discoveryURL = "\(issuer)/.well-known/openid-configuration"

        MKSLog.auth.debug("Fetching OIDC discovery from \(discoveryURL)")

        let response = try await client.get(URI(string: discoveryURL))
        let config = try response.content.decode(DiscoveryConfig.self)

        discoveryConfig = config

        MKSLog.auth.info("OIDC discovery fetched successfully", fields: [
            "issuer": config.issuer,
            "authEndpoint": config.authorizationEndpoint,
            "tokenEndpoint": config.tokenEndpoint,
            "jwksUri": config.jwksUri
        ])

        return config
    }

    /// Get authorization URL for login redirect
    ///
    /// - Parameters:
    ///   - state: CSRF protection token
    ///   - nonce: ID token nonce
    /// - Returns: Authorization URL
    /// - Throws: Error if discovery fails
    public func getAuthorizationURL(state: String, nonce: String) async throws -> String {
        let config = try await fetchDiscoveryConfig()

        var components = URLComponents(string: config.authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientId),
            URLQueryItem(name: "redirect_uri", value: credentials.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: credentials.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce)
        ]

        guard let authURL = components?.url?.absoluteString else {
            MKSLog.auth.error("Failed to construct authorization URL")

            throw Abort(.internalServerError, reason: "Failed to construct authorization URL")
        }

        MKSLog.auth.debug("Authorization URL constructed", fields: ["state": state])

        return authURL
    }

    /// Exchange authorization code for tokens
    ///
    /// - Parameters:
    ///   - code: Authorization code from callback
    /// - Returns: Token response
    /// - Throws: HTTPError if request fails
    public func exchangeCodeForToken(code: String) async throws -> TokenResponse {
        let config = try await fetchDiscoveryConfig()

        struct TokenRequest: Content {
            let grantType: String
            let clientId: String
            let clientSecret: String
            let code: String
            let redirectURI: String

            enum CodingKeys: String, CodingKey {
                case grantType = "grant_type"
                case clientId = "client_id"
                case clientSecret = "client_secret"
                case code
                case redirectURI = "redirect_uri"
            }
        }

        let request = TokenRequest(
            grantType: "authorization_code",
            clientId: credentials.clientId,
            clientSecret: credentials.clientSecret,
            code: code,
            redirectURI: credentials.redirectURI
        )

        MKSLog.auth.debug("Exchanging authorization code for token", fields: ["code": code.prefix(8) + "..."])

        let response = try await client.post(
            URI(string: config.tokenEndpoint),
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            content: request
        )

        let tokenResponse = try response.content.decode(TokenResponse.self)

        MKSLog.auth.info("Token exchange successful", fields: [
            "tokenType": tokenResponse.tokenType,
            "expiresIn": tokenResponse.expiresIn ?? 0
        ])

        return tokenResponse
    }

    /// Fetch user info from OIDC provider
    ///
    /// - Parameter accessToken: Access token
    /// - Returns: User info dictionary
    /// - Throws: HTTPError if request fails
    public func fetchUserInfo(accessToken: String) async throws -> [String: Any] {
        let config = try await fetchDiscoveryConfig()

        guard let userInfoEndpoint = config.userInfoEndpoint else {
            MKSLog.auth.warning("UserInfo endpoint not available in discovery config")

            throw Abort(.badRequest, reason: "UserInfo endpoint not available")
        }

        MKSLog.auth.debug("Fetching user info")

        let response = try await client.get(
            URI(string: userInfoEndpoint),
            headers: ["Authorization": "Bearer \(accessToken)"]
        )

        // Decode as UserInfo struct then convert to dictionary
        let userInfoData = try response.content.decode(UserInfo.self)

        let userInfo: [String: Any] = [
            "sub": userInfoData.sub,
            "name": userInfoData.name as Any,
            "email": userInfoData.email as Any,
            "picture": userInfoData.picture as Any,
            "preferred_username": userInfoData.preferredUsername as Any
        ]

        MKSLog.auth.info("User info fetched successfully", fields: [
            "subject": userInfoData.sub
        ])

        return userInfo
    }

    /// Get JWKS URI for JWT validation
    ///
    /// - Returns: JWKS URI string
    /// - Throws: Error if discovery fails
    public func getJWKSURI() async throws -> String {
        let config = try await fetchDiscoveryConfig()
        return config.jwksUri
    }
}

/// Token Response from OIDC token endpoint
public struct TokenResponse: Content {
    public let accessToken: String
    public let tokenType: String
    public let idToken: String?
    public let refreshToken: String?
    public let expiresIn: Int?
    public let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

/// User Info from OIDC userinfo endpoint
public struct UserInfo: Content {
    public let sub: String
    public let name: String?
    public let email: String?
    public let picture: String?
    public let preferredUsername: String?

    private enum CodingKeys: String, CodingKey {
        case sub
        case name
        case email
        case picture
        case preferredUsername = "preferred_username"
    }
}
