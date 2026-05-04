//
//  ProfileStore.swift
//  mks-multiplataforma-tvos-iptv
//
//  Slim UserDefaults-backed profile store for tvOS.
//  Holds at most one active IPTVProfile. No CloudKit / no multi-profile.
//

import Foundation
import SwiftUI
import IPTVCore

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profile: IPTVProfile?

    private let key = "tvos.activeProfile"

    init() { load() }

    func save(name: String, baseURL: String, username: String, password: String) {
        let p = IPTVProfile(
            name: name,
            baseURL: baseURL,
            username: username,
            password: password
        )
        profile = p
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: key)
        }
        MKSLog.app.info("ProfileStore saved profile name=\(name) host=\(baseURL)")
    }

    func clear() {
        profile = nil
        UserDefaults.standard.removeObject(forKey: key)
        MKSLog.app.info("ProfileStore cleared profile")
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(IPTVProfile.self, from: data)
        else { return }
        profile = p
        MKSLog.app.info("ProfileStore loaded profile name=\(p.name)")
    }
}
