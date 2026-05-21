//
//  ProfileModels.swift
//  mksiptv-server
//
//  Request/Response models for Profile management endpoints.
//

import Vapor
import IPTVCore

// MARK: - Response Models

/// Profile response without password (security)
public struct ProfileResponse: Content {
    public let id: UUID
    public let name: String
    public let baseURL: String
    public let username: String
    public let fileExtension: String
    public let isActive: Bool
    public let createdAt: Date

    public init(
        id: UUID,
        name: String,
        baseURL: String,
        username: String,
        fileExtension: String,
        isActive: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.fileExtension = fileExtension
        self.isActive = isActive
        self.createdAt = createdAt
    }

    /// Create from IPTVProfile
    public init(from profile: IPTVProfile, isActive: Bool = false, createdAt: Date = Date()) {
        self.id = profile.id
        self.name = profile.name
        self.baseURL = profile.baseURL
        self.username = profile.username
        self.fileExtension = profile.fileExtension
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// MARK: - Request Models

/// Request to create a new profile
public struct CreateProfileRequest: Content {
    public let name: String
    public let baseURL: String
    public let username: String
    public let password: String
    public let fileExtension: String?

    public init(name: String, baseURL: String, username: String, password: String, fileExtension: String? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.fileExtension = fileExtension
    }

    /// Validate request fields
    public func validate() throws {
        if name.isEmpty {
            throw Abort(.badRequest, reason: "Profile name cannot be empty")
        }

        if baseURL.isEmpty {
            throw Abort(.badRequest, reason: "Base URL cannot be empty")
        }

        // Validate URL format
        guard let _ = URL(string: baseURL) else {
            throw Abort(.badRequest, reason: "Invalid base URL format")
        }

        if username.isEmpty {
            throw Abort(.badRequest, reason: "Username cannot be empty")
        }

        if password.isEmpty {
            throw Abort(.badRequest, reason: "Password cannot be empty")
        }
    }
}

/// Request to update an existing profile
public struct UpdateProfileRequest: Content {
    public let name: String?
    public let baseURL: String?
    public let username: String?
    public let password: String?
    public let fileExtension: String?

    public init(name: String? = nil, baseURL: String? = nil, username: String? = nil, password: String? = nil, fileExtension: String? = nil) {
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.fileExtension = fileExtension
    }
}

// MARK: - Error Responses

/// Profile error response
public struct ProfileErrorResponse: Content {
    public let error: String
    public let message: String

    public init(error: String, message: String) {
        self.error = error
        self.message = message
    }
}

// MARK: - Profile Error Types

public enum ProfileError: String {
    case invalidCredentials = "INVALID_CREDENTIALS"
    case profileNotFound = "PROFILE_NOT_FOUND"
    case duplicateName = "DUPLICATE_NAME"
    case storageError = "STORAGE_ERROR"
}
