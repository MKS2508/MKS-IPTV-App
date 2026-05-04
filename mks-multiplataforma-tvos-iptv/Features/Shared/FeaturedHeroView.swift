//
//  FeaturedHeroView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Full-bleed hero for the top of feed screens.
//  Backdrop blurred image + bottom-left text overlay + Play CTA.
//

import SwiftUI
import IPTVCore

struct FeaturedHeroView: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let playAction: () -> Void

    @FocusState private var playFocused: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .frame(height: 720)
                .clipped()

            // Gradient mask for text legibility
            LinearGradient(
                colors: [.clear, .black.opacity(0.4), .black.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 720)

            VStack(alignment: .leading, spacing: 20) {
                Text("FEATURED")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(4)

                Text(title)
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 1200, alignment: .leading)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                        .frame(maxWidth: 1100, alignment: .leading)
                }

                Button(action: playAction) {
                    HStack(spacing: 14) {
                        Image(systemName: "play.fill")
                        Text("Watch Now")
                    }
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .focused($playFocused)
                .padding(.top, 12)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
        .frame(height: 720)
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
            colors: [.purple.opacity(0.6), .blue.opacity(0.4), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
