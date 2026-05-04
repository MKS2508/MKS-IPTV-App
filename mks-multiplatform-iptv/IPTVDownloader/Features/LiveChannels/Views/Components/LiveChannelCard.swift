//
//  LiveChannelCard.swift
//  mks-multiplatform-iptv
//
//  Unified channel card with native iOS 26+ Liquid Glass styling.
//  Consolidates LiveChannelCardView and LiveChannelGridCard into one adaptive component.
//

import SwiftUI
import IPTVCore

// MARK: - Live Channel Card

/// Unified card for Live TV channels with native Liquid Glass styling.
/// Automatically adapts between compact (grid) and regular (list) modes.
///
/// - Note: Uses `GlassEffectContainer` for proper glass blending on iOS 26+.
///   Falls back to `.ultraThinMaterial` on older OS versions.
struct LiveChannelCard: View {
    // MARK: - Properties

    let displayModel: LiveChannelDisplayModel
    let mode: CardMode

    // MARK: - Actions (passed from parent for performance)

    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onFavoriteToggle: (() -> Void)?

    // MARK: - State

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Mode

    enum CardMode {
        case compact    // Grid mode - smaller, icon-focused
        case regular    // List mode - larger, more info
    }

    // MARK: - Layout Constants

    private var posterAspectRatio: CGFloat { 4 / 3 }
    private var cornerRadius: CGFloat { AppGlass.cornerRadiusSmall }

    // MARK: - Body

    var body: some View {
        Button(action: { onTap?() }) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to play")
        .onLongPressGesture(minimumDuration: 0.5, pressing: nil, perform: {
            onLongPress?()
        })
    }

    // MARK: - Card Content

    @ViewBuilder
    private var cardContent: some View {
        switch mode {
        case .compact:
            compactCard
        case .regular:
            regularCard
        }
    }

    // MARK: - Compact Card (Grid)

    private var compactCard: some View {
        VStack(spacing: 0) {
            // Icon area with overlay
            iconArea
                .aspectRatio(posterAspectRatio, contentMode: .fit)

            // Info area
            compactInfoArea
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .glassEffectWithFallback()
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: isPressed ? 8 : 4, y: isPressed ? 4 : 2)
        .scaleEffect(isPressed ? 1.02 : 1)
        .brightness(isPressed ? 0.03 : 0)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: - Regular Card (List Row)

    private var regularCard: some View {
        HStack(spacing: 12) {
            // Channel icon
            iconThumbnail
                .frame(width: 56, height: 56)

            // Channel info
            channelInfoStack

            Spacer()

            // Trailing indicators
            trailingIndicators
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffectWithFallback(in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Icon Area (Grid)

    private var iconArea: some View {
        ZStack(alignment: .top) {
            // Background image
            CachedAsyncImage(url: URL(string: displayModel.channel.streamIcon ?? "")) { phase in
                switch phase {
                case .empty:
                    SkeletonLoader()
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
            .overlay(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            )

            // Top badges
            HStack {
                // Favorite star
                if displayModel.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .glassEffectWithFallback(in: .circle, fallbackOpacity: 0.6)
                }

                Spacer()

                // LIVE badge
                LiveBadge(size: .compact, animated: displayModel.isLive)
            }
            .padding(8)

            // EPG progress at bottom
            if displayModel.hasEPG {
                VStack {
                    Spacer()
                    EPGProgressBar(progress: displayModel.progress)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)
                }
            }

            // Football event overlay
            if let event = displayModel.footballEvent, displayModel.hasLiveFootball {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FootballEventBadge(event: event, size: .compact)
                            .padding(8)
                    }
                }
            }
        }
    }

    // MARK: - Compact Info Area

    private var compactInfoArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Channel name
            Text(displayModel.channel.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            // Programme title (if EPG available)
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
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    // MARK: - Icon Thumbnail (List)

    private var iconThumbnail: some View {
        CachedAsyncImage(url: URL(string: displayModel.channel.streamIcon ?? "")) { phase in
            switch phase {
            case .empty:
                SkeletonLoader()
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholderIconCompact
            @unknown default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholderIcon: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "tv")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderIconCompact: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "tv")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Channel Info Stack (List)

    private var channelInfoStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Channel name
            Text(displayModel.channel.name)
                .font(.body.weight(.medium))
                .lineLimit(1)

            // Subtitle row
            HStack(spacing: 8) {
                // Programme title or category
                if displayModel.hasEPG, let programme = displayModel.programmeTitle {
                    Text(programme)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                LiveBadge(size: .compact, animated: false)
            }
        }
    }

    // MARK: - Trailing Indicators

    @ViewBuilder
    private var trailingIndicators: some View {
        HStack(spacing: 8) {
            // Favorite indicator
            if displayModel.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }

            // Football live indicator
            if displayModel.hasLiveFootball, let score = displayModel.footballScoreDisplay {
                Text(score)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }

            // Disclosure indicator
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helper Properties

    private var borderColor: Color {
        Color.secondary.opacity(isPressed ? 0.2 : 0.1)
    }

    private var accessibilityLabel: String {
        var label = displayModel.channel.name
        if displayModel.isFavorite {
            label += ", favorite"
        }
        if displayModel.isLive {
            label += ", live"
        }
        if let programme = displayModel.programmeTitle {
            label += ", now playing: \(programme)"
        }
        return label
    }
}

// MARK: - Glass Effect Extension

private extension View {
    /// Applies glass effect with fallback for older OS versions.
    /// - Parameters:
    ///   - shape: Shape for the glass effect
    ///   - interactive: Whether the element responds to user interaction (default: true for cards)
    ///   - fallbackOpacity: Opacity for the fallback material
    @ViewBuilder
    func glassEffectWithFallback(
        in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall),
        interactive: Bool = true,
        fallbackOpacity: Double = 1.0
    ) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            if interactive {
                self.glassEffect(.regular.tint(AppColors.glassTint).interactive(), in: shape)
            } else {
                self.glassEffect(.regular.tint(AppColors.glassTint), in: shape)
            }
        } else {
            self.background(.ultraThinMaterial.opacity(fallbackOpacity), in: shape)
        }
    }

    /// Applies interactive glass effect (for tappable elements)
    @ViewBuilder
    func interactiveGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall),
        fallbackOpacity: Double = 1.0
    ) -> some View {
        glassEffectWithFallback(in: shape, interactive: true, fallbackOpacity: fallbackOpacity)
    }

    /// Applies static glass effect (for decorative elements)
    @ViewBuilder
    func staticGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall),
        fallbackOpacity: Double = 1.0
    ) -> some View {
        glassEffectWithFallback(in: shape, interactive: false, fallbackOpacity: fallbackOpacity)
    }
}

// MARK: - Previews

#Preview("Grid Mode") {
    LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12, alignment: .top)],
        spacing: 12
    ) {
        ForEach(0..<6) { index in
            LiveChannelCard(
                displayModel: LiveChannelDisplayModel(
                    channel: LiveChannel(
                        num: index + 1,
                        name: "Channel \(index + 1)",
                        streamType: "live",
                        streamId: index + 1,
                        streamIcon: "https://example.com/icon.jpg",
                        epgChannelId: nil,
                        added: "1620000000",
                        isAdult: "0",
                        categoryId: ["145", "147", "148"].randomElement(),
                        customSid: nil,
                        tvArchive: 0,
                        directSource: nil,
                        tvArchiveDuration: 0
                    ),
                    isFavorite: index == 0
                ),
                mode: .compact
            )
        }
    }
    .padding()
}

#Preview("List Mode") {
    LazyVStack(spacing: 8) {
        ForEach(0..<6) { index in
            LiveChannelCard(
                displayModel: LiveChannelDisplayModel(
                    channel: LiveChannel(
                        num: index + 1,
                        name: "Channel \(index + 1)",
                        streamType: "live",
                        streamId: index + 1,
                        streamIcon: "https://example.com/icon.jpg",
                        epgChannelId: nil,
                        added: "1620000000",
                        isAdult: "0",
                        categoryId: ["145", "147", "148"].randomElement(),
                        customSid: nil,
                        tvArchive: 0,
                        directSource: nil,
                        tvArchiveDuration: 0
                    ),
                    isFavorite: index == 0
                ),
                mode: .regular
            )
        }
    }
    .padding()
}
