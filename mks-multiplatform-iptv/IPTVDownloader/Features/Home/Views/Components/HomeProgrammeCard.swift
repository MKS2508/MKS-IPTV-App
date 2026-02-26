//
//  HomeProgrammeCard.swift
//  mks-multiplatform-iptv
//
//  Compact card for the "Coming Up Next" timeline section
//  Shows time, programme title, and channel name badge
//

import SwiftUI

struct HomeProgrammeCard: View {
    let programme: EPGProgramme
    let channelName: String

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 100

    var body: some View {
        HStack(spacing: 12) {
            // Time column
            VStack(spacing: 2) {
                Text(programme.formattedStartTime)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppColors.accent)

                Text(programme.formattedStopTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(width: 56)

            // Separator
            Rectangle()
                .fill(AppColors.accent.opacity(0.3))
                .frame(width: 2)
                .padding(.vertical, 4)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(programme.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                // Channel badge
                HStack(spacing: 4) {
                    Image(systemName: "tv")
                        .font(.caption2)
                    Text(channelName)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.white.opacity(0.08))
                )

                if let category = programme.category {
                    Text(category)
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: cardWidth, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                .fill(Color.white.opacity(0.04))
        )
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall))
    }
}
