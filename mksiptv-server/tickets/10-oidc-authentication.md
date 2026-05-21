# mksiptv-server#10 — OIDC Authentication Integration

## Summary

Implementar el flow OIDC (OpenID Connect) nativo en Swift para autenticación con PocketID como provider. El server maneja login, callback, validación de tokens, y middleware para proteger endpoints.

## Context

- PocketID ya está desplegado en VPS Helsinki
- PocketID es estándar OIDC Discovery — `/.well-known/openid-configuration`
- El server Swift implementa Authorization Code Flow
- Session state se maneja en-memory con Swift Actor

## Scope

### Must Have
- [ ] `GET /auth/login` → Redirect a PocketID authorization endpoint
- [ ] `GET /auth/callback` → Exchange authorization code por tokens
- [ ] `POST /auth/validate` → Introspect/validate JWT token (para middleware)
- [ ] `AuthMiddleware` → Protege endpoints basado en token válido
- [ ] Session Actor → Almacena tokens activos con expiración
- [ ] JWKS fetching → Obtener public keys de PocketID para verificar JWT
- [ ] Logout (opcional pero recomendado)

### Should Have
- [ ] Token refresh (usando refresh_token de PocketID)
- [ ] Session cleanup automático (expiración)
- [ ] Health check endpoint para auth status

### Won't Have
- User registration (PocketID lo maneja)
- Profile management (separado en ticket #2)
- Multi-factor auth (PocketID lo puede añadir)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  OIDC Flow                                               │
│                                                          │
│  [Browser/CLI]                                          │
│       │                                                  │
│       │ GET /auth/login                                 │
│       ├──────────────────────────────────────────────┐  │
│       │                                              │  │
│       ▼                                              │  │
│  [Swift Server]  ←─ Redirect to PocketID ───>  [PocketID]│
│       │                                              │  │
│       │ User authorize                               │  │
│       │                                              │  │
│       │ callback?code=xxx ───────────────────────────┘  │
│       │                                                  │
│       ▼                                                  │
│  Exchange code for tokens (PocketID token endpoint)     │
│       │                                                  │
│       ▼                                                  │
│  Validate JWT signature (JWKS from PocketID)            │
│       │                                                  │
│       ▼                                                  │
│  Store session in Actor (token + expires)               │
│       │                                                  │
│       ▼                                                  │
│  Return session token (or set cookie)                   │
└─────────────────────────────────────────────────────────┘
```

## API Design

```
GET  /auth/login                    → 302 Redirect to PocketID
GET  /auth/callback?code=...&state=... → SessionToken or 302 to frontend
POST /auth/validate                 → {valid: true, user: {...}} or 401
POST /auth/logout                   → 204 No Content (clears session)
GET  /auth/status                   → {authenticated: true/false}
```

## Data Models

```swift
// OIDC Configuration (from PocketID Discovery)
struct OIDCConfiguration: Codable {
    let issuer: String
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let jwksUri: String
    let userInfoEndpoint: String
    let supportedScopes: [String]
}

// Session state (Actor)
actor AuthSession {
    private var sessions: [String: Session] = [:]

    struct Session {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
        let user: UserInfo
    }

    struct UserInfo {
        let sub: String              // Subject (user ID)
        let name: String?
        let email: String?
    }

    func create(token: String, refresh: String?, expires: Date, user: UserInfo) -> String
    func validate(sessionToken: String) -> UserInfo?
    func revoke(sessionToken: String)
}

// JWT Validation
struct JWTValidator {
    func validate(token: String, jwks: JWKS) throws -> UserInfo
}
```

## Technical Notes

### OIDC Discovery

PocketID expone configuración en:
```
https://pocketid.example.com/.well-known/openid-configuration
```

Response contiene:
- `authorization_endpoint`
- `token_endpoint`
- `jwks_uri`
- `scopes_supported`

### Authorization Code Flow

1. **Login Request**:
```http
GET /auth/login
→ Redirect to:
https://pocketid.example.com/authorize?
  response_type=code&
  client_id=mksiptv-server&
  redirect_uri=http://localhost:4848/auth/callback&
  scope=openid+profile+email&
  state=random_state
```

2. **Callback**:
```http
GET /auth/callback?code=xxx&state=yyy
→ POST to PocketID token endpoint:
grant_type=authorization_code&
code=xxx&
redirect_uri=...&
client_id=...&
client_secret=...
→ Returns: {access_token, refresh_token, id_token, expires_in}
```

3. **JWT Validation**:
- Fetch JWKS from PocketID `jwks_uri`
- Verify JWT signature with public key
- Extract claims: `sub`, `name`, `email`, `exp`

### Middleware

```swift
struct AuthMiddleware: Middleware {
    func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        guard let token = req.headers[.authorization] else {
            return req.eventLoop.makeFailedFuture(Abort.unauthorized)
        }

        // Validate with AuthSession actor
        guard let user = await authSession.validate(sessionToken: token) else {
            return req.eventLoop.makeFailedFuture(Abort.unauthorized)
        }

        // Add user to request metadata
        req.storage[User.self] = user
        return next.respond(to: req)
    }
}
```

## Environment Variables

```bash
OIDC_ISSUER=https://pocketid.example.com
OIDC_CLIENT_ID=mksiptv-server
OIDC_CLIENT_SECRET=secret_from_pocketid
OIDC_REDIRECT_URI=http://localhost:4848/auth/callback
OIDC_SCOPES=openid profile email
SESSION_TTL=3600  # Session TTL in seconds
```

## Dependencies to Add

```swift
// Package.swift
.package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),
```

Vapor JWT package incluye helpers para:
- JWT signing/verification
- JWKS fetching
- Claims validation

## Verification

```bash
# 1. Login flow
curl -L http://localhost:4848/auth/login
# → Should redirect to PocketID

# 2. After callback, validate token
curl -X POST http://localhost:4848/auth/validate \
  -H "Authorization: Bearer <session_token>"
# → {"valid": true, "user": {"sub": "...", "name": "..."}}

# 3. Protected endpoint without token
curl http://localhost:4848/profiles
# → 401 Unauthorized

# 4. Protected endpoint with valid token
curl http://localhost:4848/profiles \
  -H "Authorization: Bearer <valid_session_token>"
# → 200 OK (profiles list)
```

## File Ownership

- `Sources/mksiptv-server/Auth/` — crear directorio
- `Sources/mksiptv-server/Auth/OIDCProvider.swift` — crear
- `Sources/mksiptv-server/Auth/AuthSession.swift` — crear (actor)
- `Sources/mksiptv-server/Auth/JWTValidator.swift` — crear
- `Sources/mksiptv-server/Auth/Middleware/AuthMiddleware.swift` — crear
- `Sources/mksiptv-server/Routes/AuthRoutes.swift` — crear

## Security Considerations

- **state parameter**: Random string para CSRF protection en login
- **PKCE**: Considerar PKCE para zusätzlicher security (bonus)
- **HTTPS**: Requerido en producción (VPS tiene HTTPS/Tailscale)
- **Secret storage**: `OIDC_CLIENT_SECRET` via env var, nunca hardcodeado
- **Session security**: Session tokens son UUID v4 random, no JWTs originales

## Integration with Tickets #2-#9

Once auth is working, protect existing endpoints:
- Profile management (#2): Require auth
- Content endpoints (#3-#5): Require auth
- Downloads (#8): Require auth
- WebSocket (#7): Validate on connection

Apply middleware globally:
```swift
// main.swift
app.middleware.use(AuthMiddleware())
// Public endpoints (health, login, callback) need exception
```

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [1] |
| estimate | 2h |
| phase | 2 (inserted after scaffold) |
| priority | high |
| status | pending |
| tags | [auth, oidc, pocketid, security] |

---

*Created: 2026-05-22*
*Decision: r01-mksiptv-server-design-decisions-2026-05-22.md*
