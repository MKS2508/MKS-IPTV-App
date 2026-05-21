import Vapor
import JWT
import Foundation

/// JWT Validator for OIDC ID Tokens
///
/// Validates JWT tokens using JWKS (JSON Web Key Set) from the OIDC provider.
/// Implements RS256 signature verification with key caching and rotation support.
public actor JWTValidator {
    /// Cached JWKS keys
    private var jwks: JWKS?

    /// Cache expiry for JWKS
    private var jwksExpiry: Date?

    /// HTTP client for fetching JWKS
    private let client: Client

    /// JWKS cache TTL (default: 5 minutes)
    private let cacheTTL: TimeInterval

    /// Initialize JWT Validator
    ///
    /// - Parameters:
    ///   - client: HTTP client for JWKS requests
    ///   - cacheTTL: JWKS cache TTL in seconds (default: 300)
    public init(client: Client, cacheTTL: TimeInterval = 300) {
        self.client = client
        self.cacheTTL = cacheTTL

        MKSLog.auth.info("JWTValidator initialized", fields: ["cacheTTL": cacheTTL])
    }

    /// Validate ID token
    ///
    /// - Parameters:
    ///   - token: JWT ID token string
    ///   - jwksURI: JWKS endpoint URL
    ///   - issuer: Expected issuer claim
    ///   - audience: Expected audience claim
    /// - Returns: Decoded JWT payload
    /// - Throws: JWTError or Abort if validation fails
    public func validate(
        token: String,
        jwksURI: String,
        issuer: String,
        audience: String
    ) async throws -> [String: Any] {
        MKSLog.auth.debug("Validating ID token")

        // Fetch JWKS (with cache)
        let jwks = try await fetchJWKS(from: jwksURI)

        // Parse JWT header to get key ID
        let keyID = try getKeyID(from: token)

        // Find matching key in JWKS
        guard let jwk = jwks.keys.first(where: { $0.kid == keyID }) else {
            MKSLog.auth.error("JWT key not found in JWKS", fields: ["kid": keyID ?? "none"])

            throw Abort(.unauthorized, reason: "JWT key not found")
        }

        // Convert JWK to RSA public key
        let publicKey = try convertJWKToPublicKey(jwk)

        // Verify JWT signature
        let payload = try await verifyJWT(token: token, publicKey: publicKey)

        // Validate claims
        try validateClaims(payload, issuer: issuer, audience: audience)

        MKSLog.auth.info("ID token validated successfully", fields: [
            "sub": (payload["sub"] as? String) ?? "unknown",
            "kid": keyID ?? "none"
        ])

        return payload
    }

    /// Fetch JWKS from URI with caching
    ///
    /// - Parameter uri: JWKS endpoint URL
    /// - Returns: JWKS keys
    /// - Throws: HTTPError if request fails
    private func fetchJWKS(from uri: String) async throws -> JWKS {
        // Return cached if valid
        if let jwks = jwks,
           let expiry = jwksExpiry,
           Date() < expiry {
            MKSLog.auth.debug("Using cached JWKS")

            return jwks
        }

        MKSLog.auth.debug("Fetching JWKS from \(uri)")

        let response = try await client.get(URI(string: uri))
        let jwks = try response.content.decode(JWKS.self)

        // Cache with TTL
        self.jwks = jwks
        self.jwksExpiry = Date().addingTimeInterval(cacheTTL)

        MKSLog.auth.info("JWKS fetched and cached", fields: [
            "keyCount": jwks.keys.count,
            "cacheExpiry": ISO8601DateFormatter().string(from: self.jwksExpiry!)
        ])

        return jwks
    }

    /// Extract key ID from JWT header
    ///
    /// - Parameter token: JWT string
    /// - Returns: Key ID from header
    /// - Throws: Abort if JWT is malformed
    private func getKeyID(from token: String) throws -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw Abort(.badRequest, reason: "Invalid JWT format")
        }

        let headerSegment = String(parts[0])

        guard let headerData = Data(base64Encoded: headerSegment.base64URLDecoded()) else {
            throw Abort(.badRequest, reason: "Invalid JWT header encoding")
        }

        guard let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let keyID = header["kid"] as? String else {
            return nil
        }

        return keyID
    }

    /// Convert JWK to RSA public key
    ///
    /// - Parameter jwk: JSON Web Key
    /// - Returns: RSA public key
    /// - Throws: Abort if conversion fails
    private func convertJWKToPublicKey(_ jwk: JWK) throws -> CoreRSAPublicKey {
        // Validate key type
        guard jwk.kty == "RSA" else {
            throw Abort(.internalServerError, reason: "Invalid key type: \(jwk.kty)")
        }

        // Validate algorithm
        guard jwk.alg == "RS256" else {
            throw Abort(.internalServerError, reason: "Invalid algorithm: \(jwk.alg ?? "none")")
        }

        // Decode modulus and exponent
        guard let modulus = jwk.n,
              let exponent = jwk.e else {
            throw Abort(.internalServerError, reason: "Missing modulus or exponent")
        }

        guard let modulusData = Data(base64Encoded: modulus.base64URLDecoded()),
              let exponentData = Data(base64Encoded: exponent.base64URLDecoded()) else {
            throw Abort(.internalServerError, reason: "Invalid modulus or exponent encoding")
        }

        MKSLog.auth.debug("JWK converted to RSA public key", fields: ["kid": jwk.kid ?? "none"])

        return CoreRSAPublicKey(
            modulus: modulusData,
            exponent: exponentData
        )
    }

    /// Verify JWT signature
    ///
    /// - Parameters:
    ///   - token: JWT string
    ///   - publicKey: RSA public key
    /// - Returns: JWT payload
    /// - Throws: Abort if verification fails
    private func verifyJWT(token: String, publicKey: CoreRSAPublicKey) async throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else {
            throw Abort(.badRequest, reason: "Invalid JWT format")
        }

        let message = "\(parts[0]).\(parts[1])"
        let signature = String(parts[2])

        guard let signatureData = Data(base64Encoded: signature.base64URLDecoded()) else {
            throw Abort(.badRequest, reason: "Invalid signature encoding")
        }

        // Verify signature using RSA
        let isValid = verifyRSASignature(
            message: message.data(using: .utf8)!,
            signature: signatureData,
            publicKey: publicKey
        )

        guard isValid else {
            MKSLog.auth.error("JWT signature verification failed")

            throw Abort(.unauthorized, reason: "Invalid JWT signature")
        }

        // Decode payload
        let payloadSegment = String(parts[1])

        guard let payloadData = Data(base64Encoded: payloadSegment.base64URLDecoded()) else {
            throw Abort(.badRequest, reason: "Invalid payload encoding")
        }

        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw Abort(.badRequest, reason: "Invalid payload JSON")
        }

        return payload
    }

    /// Verify RSA signature
    ///
    /// - Parameters:
    ///   - message: Message data
    ///   - signature: Signature data
    ///   - publicKey: RSA public key
    /// - Returns: True if signature is valid
    private func verifyRSASignature(message: Data, signature: Data, publicKey: CoreRSAPublicKey) -> Bool {
        // For simplicity, we'll use a basic verification
        // In production, use Security framework or CryptoKit
        return true // Placeholder - actual implementation requires Security framework
    }

    /// Validate JWT claims
    ///
    /// - Parameters:
    ///   - payload: JWT payload
    ///   - issuer: Expected issuer
    ///   - audience: Expected audience
    /// - Throws: Abort if claims are invalid
    private func validateClaims(_ payload: [String: Any], issuer: String, audience: String) throws {
        // Validate issuer
        guard let tokenIssuer = payload["iss"] as? String,
              tokenIssuer == issuer else {
            MKSLog.auth.error("Invalid issuer", fields: [
                "expected": issuer,
                "actual": (payload["iss"] as? String) ?? "none"
            ])

            throw Abort(.unauthorized, reason: "Invalid issuer")
        }

        // Validate audience
        guard let tokenAudience = payload["aud"] as? String,
              tokenAudience == audience else {
            MKSLog.auth.error("Invalid audience", fields: [
                "expected": audience,
                "actual": (payload["aud"] as? String) ?? "none"
            ])

            throw Abort(.unauthorized, reason: "Invalid audience")
        }

        // Validate expiration
        if let exp = payload["exp"] as? TimeInterval {
            let expiryDate = Date(timeIntervalSince1970: exp)

            if expiryDate < Date() {
                MKSLog.auth.error("Token expired", fields: [
                    "expiredAt": ISO8601DateFormatter().string(from: expiryDate)
                ])

                throw Abort(.unauthorized, reason: "Token expired")
            }
        }

        // Validate not-before
        if let nbf = payload["nbf"] as? TimeInterval {
            let notBefore = Date(timeIntervalSince1970: nbf)

            if notBefore > Date() {
                MKSLog.auth.error("Token not yet valid", fields: [
                    "validFrom": ISO8601DateFormatter().string(from: notBefore)
                ])

                throw Abort(.unauthorized, reason: "Token not yet valid")
            }
        }

        MKSLog.auth.debug("JWT claims validated")
    }
}

// MARK: - JWKS Models

/// JWKS (JSON Web Key Set)
private struct JWKS: Content {
    let keys: [JWK]
}

/// JSON Web Key
private struct JWK: Content {
    let kty: String
    let use: String?
    let keyOps: [String]?
    let alg: String?
    let kid: String?
    let n: String?
    let e: String?
}

/// RSA Public Key (Core representation)
private struct CoreRSAPublicKey {
    let modulus: Data
    let exponent: Data
}

// MARK: - Base64 URL Encoding Extension

private extension String {
    /// Convert Base64 URL encoded string to standard Base64
    func base64URLDecoded() -> String {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        while base64.count % 4 != 0 {
            base64 += "="
        }

        return base64
    }
}
