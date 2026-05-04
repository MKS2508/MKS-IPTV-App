//
//  TVMovieCard.swift
//  mks-multiplataforma-tvos-iptv
//
//  Focus-driven movie poster card for tvOS following Apple HIG:
//  - Min 250x150pt target
//  - Scale 1.1x on focus + shadow
//  - Title 48pt+, body 29pt+
//  - Reduce Motion respected
//

import SwiftUI
import IPTVCore

struct TVMovieCard: View {
    let movie: Movie
    let onSelect: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 420

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                poster
                titleOverlay
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white, lineWidth: isFocused ? 4 : 0)
            )
            .scaleEffect(isFocused && !reduceMotion ? 1.08 : 1.0)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0.25),
                    radius: isFocused ? 28 : 8,
                    x: 0,
                    y: isFocused ? 18 : 4)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isFocused)
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .accessibilityLabel(movie.name)
        .accessibilityHint(Text("Opens movie details"))
    }

    @ViewBuilder
    private var poster: some View {
        if let urlString = movie.streamIcon, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.purple.opacity(0.6), .blue.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(movie.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let rating = movie.rating, !rating.isEmpty, rating != "0" {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(rating)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
