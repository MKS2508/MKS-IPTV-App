import Foundation
import SwiftUI

/// Model and persistence for all IPTV profiles, handles active selection
typealias ProfileID = UUID

@MainActor
class IPTVProfilesManager: ObservableObject {
    @Published private(set) var profiles: [IPTVProfile] = []
    @Published var activeProfileID: ProfileID? = nil

    private let profilesKey = "iptv_profiles"
    private let activeProfileKey = "iptv_active_profile"

    static let shared = IPTVProfilesManager()
    
    private init() {
        loadProfiles()
    }

    func loadProfiles() {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: profilesKey), let loaded = try? decoder.decode([IPTVProfile].self, from: data) {
            self.profiles = loaded
        } else {
            self.profiles = []
        }
        
        if let idString = UserDefaults.standard.string(forKey: activeProfileKey), let id = UUID(uuidString: idString) {
            self.activeProfileID = id
        } else {
            self.activeProfileID = profiles.first?.id
        }
    }
    
    func saveProfiles() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
        if let id = activeProfileID {
            UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
        }
    }
    
    func addProfile(_ profile: IPTVProfile) {
        profiles.append(profile)
        activeProfileID = profile.id
        saveProfiles()
    }
    
    func updateProfile(_ profile: IPTVProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            saveProfiles()
        }
    }
    
    func deleteProfile(_ id: ProfileID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        saveProfiles()
    }
    
    func selectProfile(_ id: ProfileID) {
        activeProfileID = id
        saveProfiles()
    }
    
    var activeProfile: IPTVProfile? {
        profiles.first(where: { $0.id == activeProfileID })
    }
}
