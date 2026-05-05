//
//  FeaturedHeroView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Full-bleed hero for feed screens.
//  620pt height, parallax offset, glass badge, glassProminent CTA.
//

import SwiftUI
import IPTVCore

struct FeaturedHeroView: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let playAction: () -> Void

    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var playFocused: Bool

    private let heroHeight: CGFloat = 760

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .clipped()

            // Gradient lateral izquierdo para legibilidad del texto
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.85), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 900)
                Color.clear
            }
            .frame(height: heroHeight)

            // Gradient inferior
            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black],
                startPoint: .init(x: 0.5, y: 0.5),
                endPoint: .bottom
            )
            .frame(height: heroHeight)

            heroContent
        }
        .frame(height: heroHeight)
        .onAppear { playFocused = true }
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            GlassBadge(text: "FEATURED", icon: "star.fill")

            Text(title)
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: 1400, alignment: .leading)
                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: 1100, alignment: .leading)
            }

            playButton
                .padding(.top, 12)
        }
        .padding(.horizontal, 80)
        .padding(.bottom, 72)
    }

    private var playButton: some View {
        Button(action: playAction) {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.title2.weight(.bold))
                Text("Watch Now")
                    .font(.title2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background(playButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .focused($playFocused)
    }

    @ViewBuilder
    private var playButtonBackground: some View {
        if #available(tvOS 26, *) {
            RoundedRectangle(cornerRadius: 14)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                )
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if let url = imageURL {
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
        LinearGradient(
            colors: [
                Color(red: 0.2, green: 0.1, blue: 0.4),
                Color(red: 0.1, green: 0.2, blue: 0.5),
                .black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
