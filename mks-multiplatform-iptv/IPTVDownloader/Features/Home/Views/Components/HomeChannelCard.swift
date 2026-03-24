//
//  HomeChannelCard.swift
//  mks-multiplatform-iptv
//
//  Apple TV-style card for live channels with EPG programme info.
//  Features:
//  - Native Liquid Glass styling (iOS 26+)
//  - Animated LIVE indicator
//  - EPG progress bar with glow
//  - Focus state for tvOS
//

import SwiftUI

// MARK: - Home Channel Card

/// Apple TV-style live channel card with native Liquid Glass styling.
///
/// **Design Features:**
/// - Channel icon with glass background
/// - Animated LIVE badge with pulse
/// - Current programme title and time
/// - Progress bar with accent glow
/// - Interactive glass effect
///
struct HomeChannelCard: View {
    let liveChannel: LiveChannel
    let epgChannel: EPGChannel?
    let programme: EPGProgramme
    let onTap: (() -> Void)?

    @State private var isFocused = false
    @State private var isPressed = false

    // MARK: - Platform-Specific Sizing

    #if os(tvOS)
    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 200
    #else
    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 160
    #endif

    // MARK: - Body

    var body: some View {
        Button(action: { onTap?() }) {
            cardContent
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.97 : (isFocused ? 1.02 : 1.0))
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .animation(.easeInOut(duration: 0.25), value: isFocused)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Card Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Channel info + LIVE badge
            headerSection
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Spacer()

            // Footer: Programme info + progress
            footerSection
                .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall, style: .continuous)
                .stroke(isFocused ? AppColors.accent.opacity(0.6) : .white.opacity(0.1), lineWidth: isFocused ? 2 : 1)
        )
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 10) {
            // Channel icon
            channelIcon
                .frame(width: iconSize, height: iconSize)

            // Channel name
            Text(liveChannel.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // LIVE badge
            LiveBadge(size: .compact, animated: true)
        }
    }

    private var iconSize: CGFloat {
        #if os(tvOS)
        return 40
        #else
        return 32
        #endif
    }

    // MARK: - Channel Icon

    @ViewBuilder
    private var channelIcon: some View {
        let iconURL = epgChannel?.iconURL ?? liveChannel.streamIcon

        if let urlString = iconURL, let url = URL(string: urlString) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure, .empty:
                    iconPlaceholder
                @unknown default:
                    iconPlaceholder
                }
            }
        } else {
            iconPlaceholder
        }
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.1))
            .overlay {
                Image(systemName: "tv")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Programme title
            Text(programme.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)

            // Time range
            Text("\(programme.formattedStartTime) - \(programme.formattedStopTime)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))

            // Progress bar with glow
            progressBar
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall - 4))
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 3)

                // Progress fill with glow
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [AppColors.accent, AppColors.accentLight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * programme.progress, height: 3)
                    .shadow(color: AppColors.accent.opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 3)
    }

    // MARK: - Background

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(.white.opacity(0.04))
                .glassEffect(.regular.tint(.black.opacity(0.05)).interactive(), in: .rect(cornerRadius: AppGlass.cornerRadiusSmall))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                    .fill(.white.opacity(0.04))
                RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                    .fill(.ultraThinMaterial.opacity(0.3))
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var label = liveChannel.name
        label += ", now playing: \(programme.title)"
        label += ", \(programme.formattedStartTime) to \(programme.formattedStopTime)"
        let progress = Int(programme.progress * 100)
        label += ", \(progress)% complete"
        return label
    }
}

// MARK: - Preview

#Preview("Channel Cards") {
    HStack(spacing: 16) {
        HomeChannelCard(
            liveChannel: LiveChannel(
                num: 1,
                name: "ESPN HD",
                streamType: "live",
                streamId: 1,
                streamIcon: "https://example.com/espn.png",
                epgChannelId: nil,
                added: "1620000000",
                isAdult: "0",
                categoryId: "147",
                customSid: nil,
                tvArchive: 0,
                directSource: nil,
                tvArchiveDuration: 0
            ),
            epgChannel: nil,
            programme: EPGProgramme(
                channelId: "espn",
                start: Date().addingTimeInterval(-1800),
                stop: Date().addingTimeInterval(3600),
                title: "Live Sports Event",
                description: nil,
                category: nil,
                year: nil,
                rating: nil
            ),
            onTap: {}
        )

        HomeChannelCard(
            liveChannel: LiveChannel(
                num: 2,
                name: "CNN",
                streamType: "live",
                streamId: 2,
                streamIcon: nil,
                epgChannelId: nil,
                added: "1620000000",
                isAdult: "0",
                categoryId: "148",
                customSid: nil,
                tvArchive: 0,
                directSource: nil,
                tvArchiveDuration: 0
            ),
            epgChannel: nil,
            programme: EPGProgramme(
                channelId: "cnn",
                start: Date().addingTimeInterval(-3600),
                stop: Date().addingTimeInterval(1800),
                title: "Breaking News Coverage",
                description: nil,
                category: nil,
                year: nil,
                rating: nil
            ),
            onTap: {}
        )
    }
    .padding()
    .background(Color.black)
}
