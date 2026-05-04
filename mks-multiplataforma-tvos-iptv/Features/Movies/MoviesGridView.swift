//
//  MoviesGridView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Apple TV+ style movie feed: featured hero + horizontal category rows.
//  Pulls real data via IPTVService from the active profile.
//

import SwiftUI
import IPTVCore

struct MoviesGridView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @StateObject private var viewModel = MoviesViewModel()

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
            ProgressView()
                .scaleEffect(2.0)
            Text("Loading movies…")
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
            Text("Couldn't load movies")
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
                        subtitle: featured.rating.flatMap { "Rated \($0)" },
                        imageURL: featured.streamIcon.flatMap(URL.init(string:)),
                        playAction: {
                            MKSLog.app.info("Featured play streamId=\(featured.streamId)")
                        }
                    )
                }

                ForEach(viewModel.sections) { section in
                    CategoryRowView(
                        title: section.title,
                        items: section.movies
                    ) { movie in
                        NavigationLink {
                            MovieDetailView(movie: movie)
                        } label: {
                            TVMovieCard(movie: movie)
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
                Color(red: 0.04, green: 0.04, blue: 0.08),
                Color(red: 0.08, green: 0.04, blue: 0.14)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
