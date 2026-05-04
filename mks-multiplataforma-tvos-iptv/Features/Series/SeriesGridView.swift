//
//  SeriesGridView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Apple TV+ style series feed: featured hero + horizontal category rows.
//

import SwiftUI
import IPTVCore

struct SeriesGridView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @StateObject private var viewModel = SeriesViewModel()

    var body: some View {
        NavigationStack {
            content
                .background(backgroundGradient.ignoresSafeArea())
        }
        .task {
            guard case .idle = viewModel.state, let profile = profileStore.profile else { return }
            await viewModel.load(profile: profile)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            loading
        case .failed(let message):
            failed(message)
        case .loaded:
            feed
        }
    }

    private var loading: some View {
        VStack(spacing: 24) {
            ProgressView().scaleEffect(2.0)
            Text("Loading series…")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
            Text("Couldn't load series")
                .font(.title.weight(.semibold))
                .foregroundStyle(.white)
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 200)

            Button("Retry") {
                Task {
                    if let profile = profileStore.profile {
                        await viewModel.load(profile: profile)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feed: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 60) {
                if let featured = viewModel.featured {
                    FeaturedHeroView(
                        title: featured.name,
                        subtitle: featured.genre,
                        imageURL: featured.cover.flatMap(URL.init(string:)),
                        playAction: {
                            MKSLog.app.info("Featured serie play seriesId=\(featured.seriesId)")
                        }
                    )
                }

                ForEach(viewModel.sections) { section in
                    CategoryRowView(
                        title: section.title,
                        items: section.series
                    ) { serie in
                        NavigationLink {
                            SerieDetailView(serie: serie)
                        } label: {
                            TVSerieCard(serie: serie)
                        }
                        .buttonStyle(.card)
                    }
                }

                Spacer(minLength: 80)
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.04, blue: 0.10),
                Color(red: 0.10, green: 0.04, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
