//
//  FootballEventBadge.swift
//  mks-multiplatform-iptv
//
//  Badge component displaying live football match information.
//  Shows score, match status, and teams with Liquid Glass styling.
//

import SwiftUI

// MARK: - Football Event Badge

/// Badge displaying live football match information with score and status.
/// Uses Liquid Glass styling with platform-adaptive sizing.
struct FootballEventBadge: View {
    // MARK: - Properties

    /// The football event to display
    let event: FootballMatchedChannel

    /// Size variant for different contexts
    var size: FootballBadgeSize

    /// Whether to show the competition name
    var showCompetition: Bool

    // MARK: - Initialization

    init(
        event: FootballMatchedChannel,
        size: FootballBadgeSize = .regular,
        showCompetition: Bool = false
    ) {
        self.event = event
        self.size = size
        self.showCompetition = showCompetition
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: spacing) {
            // Live indicator (if match is live)
            if event.isLive {
                liveIndicator
            }

            // Match info
            VStack(alignment: .leading, spacing: 2) {
                // Teams and score
                HStack(spacing: 4) {
                    Text(event.fixture.teams.home.name)
                        .font(.system(size: teamFontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let score = event.fixture.scoreDisplay {
                        Text(score)
                            .font(.system(size: scoreFontSize, weight: .bold))
                            .foregroundColor(event.isLive ? .green : .white)
                    }

                    Text(event.fixture.teams.away.name)
                        .font(.system(size: teamFontSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                // Status or time
                Text(statusText)
                    .font(.system(size: statusFontSize, weight: .medium))
                    .foregroundColor(.secondary)

                // Competition (optional)
                if showCompetition {
                    Text(event.fixture.league.name)
                        .font(.system(size: competitionFontSize, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.6))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        )
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: - Computed Properties

    private var statusText: String {
        if event.isLive {
            return event.fixture.statusDisplay  // e.g., "65'", "HT"
        } else {
            return event.fixture.formattedTime  // e.g., "21:00"
        }
    }

    // MARK: - Subviews

    private var liveIndicator: some View {
        Circle()
            .fill(Color.red)
            .frame(width: liveIndicatorSize, height: liveIndicatorSize)
            .overlay(
                Circle()
                    .fill(Color.red.opacity(0.5))
                    .blur(radius: 4)
            )
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                value: 0.5
            )
    }

    // MARK: - Size-dependent Properties

    private var spacing: CGFloat {
        switch size {
        case .compact: return 6
        case .regular: return 8
        case .large: return 10
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact: return 8
        case .regular: return 10
        case .large: return 12
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact: return 4
        case .regular: return 6
        case .large: return 8
        }
    }

    private var liveIndicatorSize: CGFloat {
        switch size {
        case .compact: return 6
        case .regular: return 8
        case .large: return 10
        }
    }

    private var teamFontSize: CGFloat {
        switch size {
        case .compact: return 9
        case .regular: return 11
        case .large: return 13
        }
    }

    private var scoreFontSize: CGFloat {
        switch size {
        case .compact: return 10
        case .regular: return 12
        case .large: return 14
        }
    }

    private var statusFontSize: CGFloat {
        switch size {
        case .compact: return 8
        case .regular: return 9
        case .large: return 11
        }
    }

    private var competitionFontSize: CGFloat {
        switch size {
        case .compact: return 7
        case .regular: return 8
        case .large: return 9
        }
    }
}

// MARK: - Badge Size Enum

/// Size variants for football badges.
enum FootballBadgeSize {
    case compact
    case regular
    case large
}

// MARK: - Preview

#Preview("Football Badge") {
    VStack(spacing: 16) {
        Text("Football badges require live fixture data")
            .font(.caption)
            .foregroundColor(.secondary)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
