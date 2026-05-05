//
//  RootTabView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Top tab bar (tvOS convention). Three tabs: Movies, Series, Live TV.
//  ViewModels live here so they persist across tab switches (no reload on return).
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @AppStorage("tvos.selectedTab") private var selectedTab: Int = 0

    // Owned here so they survive tab switches
    @StateObject private var moviesVM = MoviesViewModel()
    @StateObject private var seriesVM = SeriesViewModel()
    @StateObject private var liveTVVM = LiveTVViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            MoviesGridView(viewModel: moviesVM, onRetry: {
                Task { if let p = profileStore.profile { await moviesVM.load(profile: p) } }
            })
                .tabItem { Label("Movies", systemImage: "film") }
                .tag(0)

            SeriesGridView(viewModel: seriesVM, onRetry: {
                Task { if let p = profileStore.profile { await seriesVM.load(profile: p) } }
            })
                .tabItem { Label("Series", systemImage: "tv") }
                .tag(1)

            LiveTVGridView(viewModel: liveTVVM, onRetry: {
                Task { if let p = profileStore.profile { await liveTVVM.load(profile: p) } }
            })
                .tabItem { Label("Live TV", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(2)
        }
        .task {
            guard let profile = profileStore.profile else { return }
            // Carga los tres en paralelo, solo si aún no han cargado
            async let m: () = moviesVM.loadIfNeeded(profile: profile)
            async let s: () = seriesVM.loadIfNeeded(profile: profile)
            async let l: () = liveTVVM.loadIfNeeded(profile: profile)
            _ = await (m, s, l)
        }
    }
}
