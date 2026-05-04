//
//  TVSerieCard.swift
//  mks-multiplataforma-tvos-iptv
//

import SwiftUI
import IPTVCore

struct TVSerieCard: View {
    let serie: Serie

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 420

    var body: some View {
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
        .accessibilityLabel(serie.name)
        .accessibilityHint(Text("Opens series details"))
    }

    @ViewBuilder
    private var poster: some View {
        if let urlString = serie.cover, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
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
                colors: [.indigo.opacity(0.7), .pink.opacity(0.4)],
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
            Text(serie.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if !serie.genre.isEmpty {
                    Text(serie.genre.split(separator: ",").first.map(String.init) ?? serie.genre)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if serie.rating5Based > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f", serie.rating5Based))
                    }
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
