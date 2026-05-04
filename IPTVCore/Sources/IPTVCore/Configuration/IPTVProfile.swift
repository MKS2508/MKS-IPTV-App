//
//  IPTVProfile.swift
//  IPTVCore
//
//  User credentials and server configuration. Shared across iOS / macOS / tvOS.
//

import Foundation
import SwiftUI

public final class IPTVProfile: ObservableObject, Codable, Equatable, Identifiable {
    public let id: UUID
    @Published public var name: String
    @Published public var baseURL: String
    @Published public var username: String
    @Published public var password: String
    @Published public var fileExtension: String

    public init(id: UUID = UUID(), name: String, baseURL: String, username: String, password: String, fileExtension: String = "mkv") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.fileExtension = fileExtension
    }

    // MARK: - Codable

    public enum CodingKeys: String, CodingKey {
        case id, name, baseURL, username, password, fileExtension
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(fileExtension, forKey: .fileExtension)
    }

    // MARK: - Equatable

    public static func == (lhs: IPTVProfile, rhs: IPTVProfile) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.baseURL == rhs.baseURL &&
        lhs.username == rhs.username &&
        lhs.password == rhs.password &&
        lhs.fileExtension == rhs.fileExtension
    }
}
