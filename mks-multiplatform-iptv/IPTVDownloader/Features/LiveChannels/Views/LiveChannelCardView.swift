//
//  LiveChannelCardView.swift
//  mks-multiplatform-iptv
//
//  Card component for Live TV channels with Liquid Glass styling.
//  Matches VOD card design: flexible layout, adaptive glass, semantic fonts.
//

import SwiftUI

// MARK: - Live Channel Card View

/// Modern card for Live TV channels with Liquid Glass styling.
/// Uses flexible layout (no fixed frame) — fills the grid cell width,
/// matching the VOD MediaCardViewiOS design pattern.
struct LiveChannelCardView: View {
    // MARK: - Properties

    let displayModel: LiveChannelDisplayModel

    // MARK: - State
    @State private var isPressed = false

    // MARK: - Layout Constants
    private let posterAspectRatio: CGFloat = 4 / 3
    private let cornerRadius: CGFloat = AppGlass.cornerRadiusSmall

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Top: Channel icon area with gradient overlay
            channelIconArea

            // Bottom: Channel info
            channelInfoArea
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(isPressed ? 0.2 : 0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: isPressed ? 8 : 4, y: isPressed ? 4 : 2)
        .scaleEffect(isPressed ? 1.02 : 1)
        .brightness(isPressed ? 0.03 : 0)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Channel Icon Area

    private var channelIconArea: some View {
        ZStack(alignment: .topTrailing) {
            // Background
            CachedAsyncImage(url: URL(string: displayModel.channel.streamIcon ?? "")) { phase in
                switch phase {
                case .empty:
                    SkeletonLoader()
                        .aspectRatio(posterAspectRatio, contentMode: .fill)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                case .failure:
                    placeholderIcon
                @unknown default:
                    EmptyView()
                }
            }
            .aspectRatio(posterAspectRatio, contentMode: .fit)
            .overlay(
                // Bottom gradient for readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            )

            // LIVE badge (top-right)
            LiveBadge(size: .compact)
                .padding(8)

            // Favorite star (top-left)
            if displayModel.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.yellow)
                    .padding(6)
                    .adaptiveGlass(in: Circle(), fallbackOpacity: 0.6)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // EPG progress at bottom of icon area
            if displayModel.hasEPG {
                VStack {
                    Spacer()
                    EPGProgressBar(progress: displayModel.progress)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - Channel Info Area

    private var channelInfoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Channel name
            Text(displayModel.channel.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // EPG programme info
            if displayModel.hasEPG, let programme = displayModel.programmeTitle {
                Text(programme)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Time range
            if displayModel.hasEPG, !displayModel.timeRange.isEmpty {
                Text(displayModel.timeRange)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            // Football event badge
            if let event = displayModel.footballEvent {
                FootballEventBadge(event: event, size: .compact)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    // MARK: - Placeholder

    private var placeholderIcon: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "tv")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .aspectRatio(posterAspectRatio, contentMode: .fit)
    }
}
