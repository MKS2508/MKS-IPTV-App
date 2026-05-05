//
//  TVMovieCard.swift
//  mks-multiplataforma-tvos-iptv
//
//  Focus-driven movie poster card.
//  320x480pt, FocusableCardModifier, glass overlay, rating glass pill.
//

import SwiftUI
import IPTVCore

struct TVMovieCard: View {
    let movie: Movie

    private let cardWidth: CGFloat = 320
    private let cardHeight: CGFloat = 480

    var body: some View {
        ZStack(alignment: .bottom) {
            poster
            titleOverlay
            ratingBadge
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(movie.name)
        .accessibilityHint(Text("Opens movie details"))
    }

    @ViewBuilder
    private var poster: some View {
        if let urlString = movie.streamIcon, let url = URL(string: urlString) {
            CachedHTTPImage(url: url) { phase in
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
                colors: [
                    Color(red: 0.25, green: 0.1, blue: 0.45),
                    Color(red: 0.1, green: 0.2, blue: 0.6)
                ],
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
            Spacer()

            Text(movie.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var ratingBadge: some View {
        if let rating = movie.rating, !rating.isEmpty, rating != "0" {
            VStack {
                HStack {
                    Spacer()
                    GlassBadge(text: rating, icon: "star.fill")
                        .padding(12)
                }
                Spacer()
            }
        }
    }
}
