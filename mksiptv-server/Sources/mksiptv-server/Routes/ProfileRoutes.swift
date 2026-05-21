//
//  ProfileRoutes.swift
//  mksiptv-server
//
//  REST API endpoints for profile management.
//

import Vapor
import IPTVCore

// MARK: - Profile Routes Collection

/// Profile management routes
public struct ProfileRoutes: RouteCollection {
    private let profileStore: ProfileStore

    public init(profileStore: ProfileStore) {
        self.profileStore = profileStore
    }

    public func boot(routes: RoutesBuilder) throws {
        // Grouped routes under /profiles
        let profiles = routes.grouped("profiles")

        // CRUD endpoints
        profiles.get(use: listProfiles)
        profiles.post(use: createProfile)

        // Individual profile routes
        profiles.get(":id", use: getProfile)
        profiles.put(":id", use: updateProfile)
        profiles.delete(":id", use: deleteProfile)

        // Activation endpoint
        profiles.post(":id", "activate", use: activateProfile)

        // Active profile endpoint (before :id to avoid route conflict)
        profiles.get("active", use: getActiveProfile)
    }

    // MARK: - Endpoint Handlers

    /// GET /profiles - List all profiles
    func listProfiles(req: Request) async throws -> [ProfileResponse] {
        MKSLog.api.debug("Listing all profiles")

        let profiles = await profileStore.getAllProfiles()
        let activeId = try await profileStore.getActiveProfile()?.id

        var responses: [ProfileResponse] = []
        for profile in profiles {
            let createdAt = (try? await profileStore.getProfileCreatedAt(id: profile.id)) ?? Date()
            responses.append(ProfileResponse(
                from: profile,
                isActive: profile.id == activeId,
                createdAt: createdAt
            ))
        }
        return responses
    }

    /// POST /profiles - Create new profile
    func createProfile(req: Request) async throws -> ProfileResponse {
        let request = try req.content.decode(CreateProfileRequest.self)

        MKSLog.api.info("Creating profile: \(request.name)")

        // Validate request
        try request.validate()

        // TODO: Validate Xtream credentials in background
        // For now, create without validation (will be added in #3)

        let profile = try await profileStore.createProfile(from: request)

        return ProfileResponse(
            from: profile,
            isActive: false,
            createdAt: Date()
        )
    }

    /// GET /profiles/:id - Get specific profile
    func getProfile(req: Request) async throws -> ProfileResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid profile ID format")
        }

        MKSLog.api.debug("Fetching profile: \(idString)")

        let profile = try await profileStore.getProfile(id: id)
        let activeId = try await profileStore.getActiveProfile()?.id
        let createdAt = try await profileStore.getProfileCreatedAt(id: id)

        return ProfileResponse(
            from: profile,
            isActive: profile.id == activeId,
            createdAt: createdAt
        )
    }

    /// PUT /profiles/:id - Update profile
    func updateProfile(req: Request) async throws -> ProfileResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid profile ID format")
        }

        let request = try req.content.decode(UpdateProfileRequest.self)

        MKSLog.api.info("Updating profile: \(idString)")

        let profile = try await profileStore.updateProfile(id: id, from: request)
        let activeId = try await profileStore.getActiveProfile()?.id
        let createdAt = try await profileStore.getProfileCreatedAt(id: id)

        return ProfileResponse(
            from: profile,
            isActive: profile.id == activeId,
            createdAt: createdAt
        )
    }

    /// DELETE /profiles/:id - Delete profile
    func deleteProfile(req: Request) async throws -> HTTPStatus {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid profile ID format")
        }

        MKSLog.api.info("Deleting profile: \(idString)")

        try await profileStore.deleteProfile(id: id)

        return .noContent
    }

    /// POST /profiles/:id/activate - Set active profile
    func activateProfile(req: Request) async throws -> ProfileResponse {
        guard let idString = req.parameters.get("id"),
              let id = UUID(uuidString: idString) else {
            throw Abort(.badRequest, reason: "Invalid profile ID format")
        }

        MKSLog.api.info("Activating profile: \(idString)")

        let profile = try await profileStore.setActiveProfile(id: id)
        let createdAt = try await profileStore.getProfileCreatedAt(id: id)

        return ProfileResponse(
            from: profile,
            isActive: true,
            createdAt: createdAt
        )
    }

    /// GET /profiles/active - Get active profile
    func getActiveProfile(req: Request) async throws -> ProfileResponse {
        MKSLog.api.debug("Fetching active profile")

        guard let profile = try await profileStore.getActiveProfile() else {
            throw Abort(.notFound, reason: "No active profile found")
        }

        let createdAt = try await profileStore.getProfileCreatedAt(id: profile.id)

        return ProfileResponse(
            from: profile,
            isActive: true,
            createdAt: createdAt
        )
    }
}
