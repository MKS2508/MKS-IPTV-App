# mksiptv-server#2 — Profile Management Endpoints

## Summary

Implementar endpoints CRUD para gestionar perfiles IPTV (Xtream Codes credentials). Los perfiles ya existen como modelo `IPTVProfile` en IPTVCore — solo hay que exponerlos via API.

## Context

- `IPTVProfile` en IPTVCore ya tiene: `id`, `name`, `baseURL`, `username`, `password`, `fileExtension`
- `IPTVProfilesManager` en IPTVDownloader gestiona persistencia (UserDefaults)
- Para el server, persistencia via filesystem (JSON en `~/.config/mksiptv/profiles.json`)

## Scope

### Must Have
- [ ] `GET /profiles` → lista todos los perfiles (sin password en response)
- [ ] `POST /profiles` → crear perfil nuevo (valida Xtream connection)
- [ ] `PUT /profiles/:id` → actualizar perfil
- [ ] `DELETE /profiles/:id` → eliminar perfil
- [ ] `POST /profiles/:id/activate` → marcar como activo
- [ ] `GET /profiles/active` → obtener perfil activo actual

### Should Have
- [ ] Validación de credentials al crear/actualizar (intentar fetch categories)
- [ ] Profile cloning (duplicate)

### Won't Have
- CloudKit sync (fuera de scope para server)
- Profile import/export

## Data Model

```swift
// Request/Response types
struct ProfileResponse: Codable {
    let id: UUID
    let name: String
    let baseURL: String
    let username: String
    let fileExtension: String
    let isActive: Bool
    // password OMITIDO en response por seguridad
}

struct CreateProfileRequest: Codable {
    let name: String
    let baseURL: String
    let username: String
    let password: String
    let fileExtension: String?
}

struct ActivateProfileRequest: Codable {
    let id: UUID
}
```

## API Design

```
GET    /profiles              → [ProfileResponse]
POST   /profiles             → ProfileResponse (body: CreateProfileRequest)
GET    /profiles/:id         → ProfileResponse
PUT    /profiles/:id         → ProfileResponse (body: CreateProfileRequest)
DELETE /profiles/:id         → 204 No Content
POST   /profiles/:id/activate → ProfileResponse
GET    /profiles/active      → ProfileResponse
```

## Error Responses

```json
// 400 Bad Request (invalid credentials)
{"error": "INVALID_CREDENTIALS", "message": "Cannot connect to Xtream server with provided credentials"}

// 404 Not Found
{"error": "PROFILE_NOT_FOUND", "message": "Profile with id xxx not found"}

// 409 Conflict (duplicate name)
{"error": "DUPLICATE_NAME", "message": "Profile with name 'Casa' already exists"}
```

## Technical Notes

- Reutilizar `IPTVService` actor para validar credentials
- Persistencia: `Codable` + `JSONEncoder`/`JSONDecoder` a archivo
- Directorio de config: `FileManager.default.urls(for: .applicationSupportDirectory).first/appName`

## Verification

```bash
curl http://localhost:4848/profiles
# → []

curl -X POST http://localhost:4848/profiles \
  -H "Content-Type: application/json" \
  -d '{"name":"Casa","baseURL":"http://xtream.example.com","username":"user","password":"pass"}'
# → {"id":"...","name":"Casa",...}

curl -X POST http://localhost:4848/profiles/<id>/activate
# → {"id":"...", "isActive": true, ...}
```

## File Ownership

- `Sources/mksiptv-server/Models/ProfileModels.swift` — crear
- `Sources/mksiptv-server/Services/ProfileStore.swift` — crear
- `Sources/mksiptv-server/Routes/ProfileRoutes.swift` — crear

## Metadata

| Field | Value |
|-------|-------|
| category | feature |
| component | mksiptv-server |
| dependsOn | [1] |
| estimate | 1.5h |
| phase | 3 |
| priority | high |
| status | pending |
| tags | [profiles, api, crud] |
