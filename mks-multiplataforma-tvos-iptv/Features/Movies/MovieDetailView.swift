//
//  MovieDetailView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Full-screen movie detail. Pushed onto NavigationStack from MoviesGridView.
//  Hero backdrop + plot + cast + Play CTA (no-op for now — Block 5 wires player).
//

import SwiftUI
import IPTVCore

struct MovieDetailView: View {
    let movie: Movie

    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var detail: MovieDetail?
    @State private var loadError: String?
    @State private var playingItem: PlayableItem?
    @FocusState private var isPlayFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                metadataSection
                if let detail, !detail.plot.isEmpty {
                    plotSection(detail.plot)
                }
                if let detail {
                    castSection(detail)
                }
                Spacer(minLength: 80)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .task {
            await loadDetail()
        }
        .onAppear { isPlayFocused = true }
        .fullScreenCover(item: $playingItem) { item in
            TVPlayerView(item: item) { playingItem = nil }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            backdropImage
                .frame(height: 720)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 720)

            VStack(alignment: .leading, spacing: 20) {
                Text(movie.name)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 1200, alignment: .leading)

                if let detail {
                    HStack(spacing: 16) {
                        if !detail.genre.isEmpty {
                            Text(detail.genre)
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        if !detail.releaseDate.isEmpty {
                            metaPill(detail.releaseDate)
                        }
                        if !detail.duration.isEmpty {
                            metaPill(detail.duration)
                        }
                        if let rating = detail.rating, !rating.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                Text(rating)
                            }
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        }
                    }
                }

                HStack(spacing: 24) {
                    Button(action: playMovie) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.fill")
                            Text("Play")
                        }
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .focused($isPlayFocused)

                    Button(action: { MKSLog.app.info("Trailer tapped streamId=\(movie.streamId)") }) {
                        HStack(spacing: 10) {
                            Image(systemName: "film")
                            Text("Trailer")
                        }
                        .font(.title3.weight(.medium))
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
        .frame(height: 720)
    }

    @ViewBuilder
    private var backdropImage: some View {
        let urlString = detail?.backdropPath?.first ?? detail?.backdrop ?? movie.streamIcon ?? ""
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    backdropPlaceholder
                @unknown default:
                    backdropPlaceholder
                }
            }
        } else {
            backdropPlaceholder
        }
    }

    private var backdropPlaceholder: some View {
        LinearGradient(
            colors: [.purple.opacity(0.6), .blue.opacity(0.4), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.white.opacity(0.12), in: Capsule())
    }

    private var metadataSection: some View {
        EmptyView()
    }

    private func plotSection(_ plot: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storyline")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(plot)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(8)
                .frame(maxWidth: 1400, alignment: .leading)
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
    }

    private func castSection(_ detail: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 80) {
                if !detail.director.isEmpty {
                    metaBlock(label: "Director", value: detail.director)
                }
                if !detail.cast.isEmpty {
                    metaBlock(label: "Cast", value: detail.cast.prefix(4).joined(separator: ", "))
                }
            }
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
    }

    private func metaBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(2)
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        }
    }

    private func playMovie() {
        guard let profile = profileStore.profile,
              let item = PlayableItem.movie(movie, profile: profile) else {
            MKSLog.player.error("Could not build PlayableItem for movie streamId=\(movie.streamId)")
            return
        }
        MKSLog.player.info("Play tapped streamId=\(movie.streamId)")
        playingItem = item
    }

    private func loadDetail() async {
        guard detail == nil, let profile = profileStore.profile else { return }
        let service = IPTVService(profile: profile)
        do {
            detail = try await service.fetchMovieDetails(vodId: movie.streamId)
        } catch {
            loadError = "\(error)"
            MKSLog.app.error("MovieDetail load failed: \(error)")
        }
    }
}
