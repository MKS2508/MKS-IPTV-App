//
//  mks_multiplataforma_tvos_iptvApp.swift
//  mks-multiplataforma-tvos-iptv
//
//  Created by Marcos Asensio on 27/3/25.
//

import SwiftUI
import IPTVCore

@main
struct mks_multiplataforma_tvos_iptvApp: App {
    @StateObject private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if profileStore.profile != nil {
                    RootTabView()
                } else {
                    ProfileBootstrapView()
                }
            }
            .environmentObject(profileStore)
            .task {
                // Clean up expired cache entries once on launch
                await TVCacheManager.shared.clearExpired()
            }
        }
    }
}
