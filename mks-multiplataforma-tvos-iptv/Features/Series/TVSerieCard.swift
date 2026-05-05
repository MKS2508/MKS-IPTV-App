//
//  TVSerieCard.swift
//  mks-multiplataforma-tvos-iptv
//
//  Focus-driven series poster card.
//  320x480pt, FocusableCardModifier, glass overlay, rating glass pill.
//

import SwiftUI
import IPTVCore

struct TVSerieCard: View {
    let serie: Serie

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
        .accessibilityLabel(serie.name)
        .accessibilityHint(Text("Opens series details"))
    }

    @ViewBuilder
    private var poster: some View {
        if let urlString = serie.cover, let url = URL(string: urlString) {
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
                    Color(red: 0.15, green: 0.1, blue: 0.4),
                    Color(red: 0.3, green: 0.15, blue: 0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "tv")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()

            Text(serie.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !serie.genre.isEmpty {
                Text(serie.genre.split(separator: ",").first.map(String.init) ?? serie.genre)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
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
        if serie.rating5Based > 0 {
            VStack {
                HStack {
                    Spacer()
                    GlassBadge(
                        text: String(format: "%.1f", serie.rating5Based),
                        icon: "star.fill"
                    )
                    .padding(12)
                }
                Spacer()
            }
        }
    }
}
