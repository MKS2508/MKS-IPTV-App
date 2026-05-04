//
//  MoviesGridView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Focus-based grid of movies for tvOS.
//  Default focus on first card. Lazy grid for memory.
//  Sample data for Block 3 — real service wiring lands when Networking
//  + Services migrate to IPTVCore (Block 5/6).
//

import SwiftUI
import IPTVCore

struct MoviesGridView: View {
    @State private var movies: [Movie] = SampleMovies.placeholderSet
    @FocusState private var focusedID: Int?

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(280), spacing: 56),
        count: 4
    )

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                header

                LazyVGrid(columns: columns, alignment: .leading, spacing: 64) {
                    ForEach(movies) { movie in
                        TVMovieCard(movie: movie) {
                            MKSLog.app.info("tap movie streamId=\(movie.streamId)")
                        }
                        .focused($focusedID, equals: movie.streamId)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .background(backgroundGradient.ignoresSafeArea())
        .onAppear {
            if let first = movies.first {
                focusedID = first.streamId
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Movies")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Text("\(movies.count) titles")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .accessibilityElement(children: .combine)
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.10),
                Color(red: 0.10, green: 0.05, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Sample Data (Block 3 scaffold; replaced by service in later block)

enum SampleMovies {
    static let placeholderSet: [Movie] = (1...16).map { i in
        Movie(
            name: "Sample Movie \(i)",
            streamType: "movie",
            streamId: i,
            tmdbId: nil,
            streamIcon: nil,
            rating: String(format: "%.1f", Double(i % 5) + 5.0),
            rating5Based: 4.0,
            added: nil,
            isAdult: "0",
            categoryId: "0",
            containerExtension: "mp4",
            customSid: nil,
            directSource: nil
        )
    }
}
