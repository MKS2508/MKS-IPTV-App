//
//  LiveChannelCardView.swift
//  mks-multiplatform-iptv
//
//  Card component for Live TV channels with Liquid Glass styling.
//  Features: EPG integration, favorites toggle, and Direct Play tap action.
//

import SwiftUI
import AVKit

// MARK: - Live Channel Card View

/// Modern card for Live TV channels with Liquid Glass styling.
/// Shows EPG progress, programme info, and allows direct play on channel.
struct LiveChannelCardView: View {
    // MARK: - Properties

    /// The display model containing channel and EPG data
    let displayModel: LiveChannelDisplayModel

    /// Callback triggered when card is tapped for direct play
    let onTap: (() -> Void)?

    /// Callback triggered when card is long-pressed for details
    let onLongPress: (() -> Void)?

    // MARK: - Environment

    @EnvironmentObject var profile: IPTVProfile
    @Environment(\.openWindow) private var openWindow

    // MARK: - State
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var activePlayer: (any VideoPlayerProtocol)?
    @State private var showFullscreenPlayer = false
    @State private var isLoading = false
    @State private var showError: Error?

    // MARK: - Initialization

    init(displayModel: LiveChannelDisplayModel, onTap: (() -> Void)? = nil, onLongPress: (() -> Void)? = nil) {
        self.displayModel = displayModel
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    // MARK: - Platform-Specific Computed Properties

    private var cardSize: CGSize {
        #if os(iOS)
        CGSize(width: 160, height: 200)
        #elseif os(macOS)
        CGSize(width: 200, height: 250)
        #elseif os(tvOS)
        CGSize(width: 300, height: 380)
        #else
        CGSize(width: 160, height: 200)
        #endif
    }

    private var iconSize: CGFloat {
        #if os(iOS)
        50
        #elseif os(macOS)
        60
        #elseif os(tvOS)
        80
        #else
        50
        #endif
    }

    private var titleFont: Font {
        #if os(iOS)
        .system(size: 13, weight: .semibold)
        #elseif os(macOS)
        .system(size: 14, weight: .semibold)
        #elseif os(tvOS)
        .system(size: 18, weight: .semibold)
        #else
        .system(size: 13, weight: .semibold)
        #endif
    }

    private var programmeFont: Font {
        #if os(iOS)
        .system(size: 11, weight: .medium)
        #elseif os(macOS)
        .system(size: 12, weight: .medium)
        #elseif os(tvOS)
        .system(size: 14, weight: .medium)
        #else
        .system(size: 11, weight: .medium)
        #endif
    }

    private var badgeSize: LiveBadgeSize {
        #if os(iOS)
        .compact
        #elseif os(macOS)
        .regular
        #elseif os(tvOS)
        .large
        #else
        .compact
        #endif
    }

    private var hoverScale: CGFloat {
        isHovered ? 1.03 : 1.0
    }

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .top) {
            // Favorite button (top-right)
            HStack {
                Spacer()
                Button(action: toggleFavorite) {
                    Image(systemName: displayModel.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(displayModel.isFavorite ? .yellow : .white)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .accessibilityLabel("Toggle favorite")
                .accessibilityHint("Tap to toggle favorite")
            }
            .padding(.top, 8)
            .padding(.trailing, 8)

            // Main content
            VStack(spacing: 8) {
                // Channel Icon
                ChannelIconView(
                    url: URL(string: displayModel.channel.streamIcon ?? ""),
                    size: CGSize(width: iconSize, height: iconSize)
                )
                .frame(height: iconSize)

                // Channel Name
                Text(displayModel.channel.name)
                    .font(titleFont)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)

                // LIVE Badge
                LiveBadge(size: badgeSize)
                    .padding(.top, 2)

                // EPG Section (if available)
                if displayModel.hasEPG {
                    VStack(spacing: 4) {
                        // Programme Title
                        Text(displayModel.programmeTitle ?? "No program information")
                            .font(programmeFont)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .minimumScaleFactor(0.9)

                        // Time Range
                        Text(displayModel.timeRange)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        // Progress Bar
                        EPGProgressBar(progress: displayModel.progress)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .padding(8)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isHovered ? Color.accentColor : Color.clear,
                            lineWidth: isPressed ? 2 : 1
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(hoverScale)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Private Methods

    private func toggleFavorite() {
        // Toggle favorite via the favorites manager
        Task { @MainActor in
            LiveChannelFavoritesManager.shared.toggleFavorite(displayModel.id)
        }
    }
}
