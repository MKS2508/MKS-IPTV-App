//
//  RootTabView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Top tab bar (tvOS convention). Three tabs: Movies, Series, Live TV.
//  Selected tab persists across launches via @AppStorage.
//

import SwiftUI

struct RootTabView: View {
    @AppStorage("tvos.selectedTab") private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MoviesGridView()
                .tabItem { Label("Movies", systemImage: "film") }
                .tag(0)

            SeriesGridView()
                .tabItem { Label("Series", systemImage: "tv") }
                .tag(1)

            LiveTVGridView()
                .tabItem { Label("Live TV", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(2)
        }
    }
}
