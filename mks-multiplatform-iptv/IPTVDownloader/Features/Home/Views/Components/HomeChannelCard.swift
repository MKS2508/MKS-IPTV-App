//
//  HomeChannelCard.swift
//  mks-multiplatform-iptv
//
//  Card showing a live channel with current EPG programme and progress bar
//

import SwiftUI

struct HomeChannelCard: View {
    let liveChannel: LiveChannel
    let epgChannel: EPGChannel?
    let programme: EPGProgramme

    private let cardWidth: CGFloat = 200
    private let cardHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Channel icon + name + LIVE badge
            HStack(spacing: 8) {
                if let iconURL = epgChannel?.iconURL ?? liveChannel.streamIcon,
                   let url = URL(string: iconURL) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            channelPlaceholder
                        }
                    }
                } else {
                    channelPlaceholder
                }

                Text(liveChannel.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // LIVE glass badge
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppColors.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .adaptiveGlass(in: Capsule())
            }

            Spacer()

            // Programme title
            Text(programme.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)

            // Time range
            Text("\(programme.formattedStartTime) - \(programme.formattedStopTime)")
                .font(.caption2)
                .foregroundStyle(AppColors.textTertiary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColors.accent)
                        .frame(width: geo.size.width * programme.progress, height: 3)
                }
            }
            .frame(height: 3)
        }
        .padding(12)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(Color.white.opacity(0.06))
        )
        .adaptiveGlassInteractive(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
    }

    private var channelPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(AppColors.surface)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: "tv")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }
}
