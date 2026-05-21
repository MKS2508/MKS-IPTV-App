//
//  ProfileStore.swift
//  mksiptv-server
//
//  Filesystem-based persistence for IPTV profiles.
//  Storage: ~/.config/mksiptv/profiles.json
//

import Vapor
import IPTVCore
import Foundation

// MARK: - Storage Model

/// Internal storage model for JSON persistence
private struct ProfileStorage: Codable {
    var activeProfileId: UUID?
    var profiles: [StoredProfile]

    init(activeProfileId: UUID? = nil, profiles: [StoredProfile] = []) {
        self.activeProfileId = activeProfileId
        self.profiles = profiles
    }

    /// Stored profile with metadata
    struct StoredProfile: Codable {
        let id: UUID
        let name: String
        let baseURL: String
        let username: String
        let password: String
        let fileExtension: String
        let createdAt: Date

        init(from profile: IPTVProfile, createdAt: Date = Date()) {
            self.id = profile.id
            self.name = profile.name
            self.baseURL = profile.baseURL
            self.username = profile.username
            self.password = profile.password
            self.fileExtension = profile.fileExtension
            self.createdAt = createdAt
        }

        /// Convert to IPTVProfile
        func toIPTVProfile() -> IPTVProfile {
            IPTVProfile(
                id: id,
                name: name,
                baseURL: baseURL,
                username: username,
                password: password,
                fileExtension: fileExtension
            )
        }
    }
}

// MARK: - Profile Store Actor

/// Thread-safe profile storage with JSON persistence
public actor ProfileStore {
    private var storage: ProfileStorage
    private let storageURL: URL
    private let fileManager = FileManager.default

    /// Initialize profile store with default storage path
    public init() throws {
        // Get application support directory
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        // Create app config directory
        let configDir = appSupportURL.appendingPathComponent("mksiptv", isDirectory: true)
        self.storageURL = configDir.appendingPathComponent("profiles.json")

        // Create directory if needed
        if !fileManager.fileExists(atPath: configDir.path) {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
            MKSLog.server.info("Created config directory: \(configDir.path)")
        }

        // Load existing storage or create new
        if fileManager.fileExists(atPath: storageURL.path) {
            self.storage = try Self.loadStorage(from: storageURL)
            MKSLog.server.info("Loaded profiles from: \(storageURL.path)")
        } else {
            self.storage = ProfileStorage()
            try self.save()
            MKSLog.server.info("Initialized new profile storage: \(storageURL.path)")
        }
    }

    // MARK: - CRUD Operations

    /// List all profiles
    public func getAllProfiles() -> [IPTVProfile] {
        return storage.profiles.map { $0.toIPTVProfile() }
    }

    /// Get profile by ID
    public func getProfile(id: UUID) throws -> IPTVProfile {
        guard let stored = storage.profiles.first(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Profile with id \(id.uuidString) not found")
        }
        return stored.toIPTVProfile()
    }

    /// Get active profile
    public func getActiveProfile() throws -> IPTVProfile? {
        guard let activeId = storage.activeProfileId else {
            return nil
        }
        return try getProfile(id: activeId)
    }

    /// Create new profile
    public func createProfile(from request: CreateProfileRequest) throws -> IPTVProfile {
        // Validate request
        try request.validate()

        // Check for duplicate name
        if storage.profiles.contains(where: { $0.name == request.name }) {
            throw Abort(.conflict, reason: "Profile with name '\(request.name)' already exists")
        }

        // Create profile
        let profile = IPTVProfile(
            name: request.name,
            baseURL: request.baseURL,
            username: request.username,
            password: request.password,
            fileExtension: request.fileExtension ?? "mkv"
        )

        // Store with metadata
        let stored = ProfileStorage.StoredProfile(from: profile)
        storage.profiles.append(stored)

        // Persist
        try save()

        MKSLog.server.info("Created profile: \(profile.name)")

        return profile
    }

    /// Update existing profile
    public func updateProfile(id: UUID, from request: UpdateProfileRequest) throws -> IPTVProfile {
        guard let index = storage.profiles.firstIndex(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Profile with id \(id.uuidString) not found")
        }

        var stored = storage.profiles[index]

        // Update fields if provided
        if let name = request.name {
            // Check duplicate name (excluding current profile)
            if storage.profiles.contains(where: { $0.name == name && $0.id != id }) {
                throw Abort(.conflict, reason: "Profile with name '\(name)' already exists")
            }
        }

        // Build updated profile
        let profile = IPTVProfile(
            id: id,
            name: request.name ?? stored.name,
            baseURL: request.baseURL ?? stored.baseURL,
            username: request.username ?? stored.username,
            password: request.password ?? stored.password,
            fileExtension: request.fileExtension ?? stored.fileExtension
        )

        // Validate URL if changed
        if request.baseURL != nil {
            guard URL(string: profile.baseURL) != nil else {
                throw Abort(.badRequest, reason: "Invalid base URL format")
            }
        }

        // Create new stored profile with updated data
        let updatedStored = ProfileStorage.StoredProfile(
            from: profile,
            createdAt: stored.createdAt
        )

        storage.profiles[index] = updatedStored
        try save()

        MKSLog.server.info("Updated profile: \(profile.name)")

        return profile
    }

    /// Delete profile
    public func deleteProfile(id: UUID) throws {
        guard let index = storage.profiles.firstIndex(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Profile with id \(id.uuidString) not found")
        }

        let profile = storage.profiles[index]
        storage.profiles.remove(at: index)

        // Clear active profile if this was it
        if storage.activeProfileId == id {
            storage.activeProfileId = nil
        }

        try save()

        MKSLog.server.info("Deleted profile: \(profile.name)")
    }

    /// Set active profile
    public func setActiveProfile(id: UUID) throws -> IPTVProfile {
        // Verify profile exists
        let profile = try getProfile(id: id)

        storage.activeProfileId = id
        try save()

        MKSLog.server.info("Activated profile: \(profile.name)")

        return profile
    }

    /// Get profile creation date
    public func getProfileCreatedAt(id: UUID) throws -> Date {
        guard let stored = storage.profiles.first(where: { $0.id == id }) else {
            throw Abort(.notFound, reason: "Profile with id \(id.uuidString) not found")
        }
        return stored.createdAt
    }

    // MARK: - Persistence

    /// Save storage to disk
    private func save() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(storage)
        try data.write(to: storageURL, options: .atomic)
    }

    /// Load storage from disk
    private static func loadStorage(from url: URL) throws -> ProfileStorage {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfileStorage.self, from: data)
    }
}
