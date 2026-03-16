// TODO: Remove any usage of static config elsewhere. All code should use an IPTVProfile.
import Foundation
import SwiftUI

final class IPTVProfile: ObservableObject, Codable, Equatable, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var baseURL: String
    @Published var username: String
    @Published var password: String
    @Published var fileExtension: String
    
    init(id: UUID = UUID(), name: String, baseURL: String, username: String, password: String, fileExtension: String = "mkv") {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.fileExtension = fileExtension
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, username, password, fileExtension
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(fileExtension, forKey: .fileExtension)
    }
    
    // MARK: - Equatable
    static func == (lhs: IPTVProfile, rhs: IPTVProfile) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.baseURL == rhs.baseURL &&
               lhs.username == rhs.username &&
               lhs.password == rhs.password &&
               lhs.fileExtension == rhs.fileExtension
    }
}

enum IPTVConfiguration {
    static let seriesEndpoint = "series"
    static let moviesEndpoint = "movie"
    static let liveChannelsEndpoint = "live"
    
    static func buildMovieURL(profile: IPTVProfile, vodID: String, vodExtension: String) -> String {
        return "\(profile.baseURL)/\(moviesEndpoint)/\(profile.username)/\(profile.password)/\(vodID).\(vodExtension)"
    }
    
    static func buildSeriesURL(profile: IPTVProfile, vodID: String, vodExtension: String) -> String {
        return "\(profile.baseURL)/\(seriesEndpoint)/\(profile.username)/\(profile.password)/\(vodID).\(vodExtension)"
    }
    
    static func buildLiveChannelURL(profile: IPTVProfile, channelID: Int) -> String {
        return "\(profile.baseURL)/\(liveChannelsEndpoint)/\(profile.username)/\(profile.password)/\(channelID).m3u8"
    }

    static func defaultRequestHeaders() -> [String: String] {
        return [
            "Accept-Encoding": "identity",
            "Connection": "Keep-Alive",
            "User-Agent": "VLC/3.0.18 LibVLC/3.0.18"
        ]
    }
}
