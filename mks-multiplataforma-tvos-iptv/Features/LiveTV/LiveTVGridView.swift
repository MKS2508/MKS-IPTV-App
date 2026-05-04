//
//  LiveTVGridView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Live TV feed: featured channel + horizontal category rows.
//

import SwiftUI
import IPTVCore

struct LiveTVGridView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @StateObject private var viewModel = LiveTVViewModel()

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
            Text("Loading channels…")
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
            Text("Couldn't load channels")
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
                    let current = MockEPG.currentProgramme(for: featured)
                    FeaturedHeroView(
                        title: featured.name,
                        subtitle: current.map { "Now: \($0.title)" } ?? "Live channel",
                        imageURL: featured.streamIcon.flatMap(URL.init(string:)),
                        playAction: {
                            MKSLog.app.info("Featured live play streamId=\(featured.streamId)")
                        }
                    )
                }

                ForEach(viewModel.sections) { section in
                    CategoryRowView(
                        title: section.title,
                        items: section.channels
                    ) { channel in
                        NavigationLink {
                            ChannelDetailView(channel: channel)
                        } label: {
                            TVChannelCard(channel: channel)
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
                Color(red: 0.12, green: 0.04, blue: 0.04)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
