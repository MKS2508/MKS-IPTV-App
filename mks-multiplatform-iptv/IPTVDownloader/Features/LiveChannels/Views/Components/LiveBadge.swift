//
//  LiveBadge.swift
//  mks-multiplatform-iptv
//
//  Animated LIVE badge for live TV channels with Liquid Glass styling.
//

import SwiftUI
import IPTVCore

// MARK: - Live Badge

/// Animated badge indicating a live broadcast.
/// Features a pulsing animation to draw attention.
struct LiveBadge: View {
    // MARK: - Properties

    /// Size variant (compact, regular, large)
    var size: LiveBadgeSize

    /// Whether to show the pulsing animation
    var animated: Bool

    // MARK: - Initialization

    init(size: LiveBadgeSize = .regular, animated: Bool = true) {
        self.size = size
        self.animated = animated
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            // Live indicator dot
            Circle()
                .fill(Color.red)
                .frame(width: size.dotSize, height: size.dotSize)
                .overlay(
                    Circle()
                        .fill(Color.red)
                        .frame(width: size.dotSize, height: size.dotSize)
                        .scaleEffect(animated ? pulseScale : 1.0)
                        .opacity(animated ? pulseOpacity : 1.0)
                        .animation(
                            animated ?
                                .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true) :
                                .default,
                            value: animated
                        )
                )

            // LIVE text
            Text("LIVE")
                .font(.system(size: size.fontSize, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            Capsule()
                .fill(Color.red.opacity(0.85))
        )
        .accessibilityLabel("Live broadcast")
    }

    // MARK: - Private Properties

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0
}

// MARK: - Badge Size

/// Size variants for the LiveBadge component
enum LiveBadgeSize {
    case compact
    case regular
    case large

    /// Font size for this badge size
    var fontSize: CGFloat {
        switch self {
        case .compact: return 8
        case .regular: return 10
        case .large: return 12
        }
    }

    /// Dot indicator size
    var dotSize: CGFloat {
        switch self {
        case .compact: return 4
        case .regular: return 5
        case .large: return 6
        }
    }

    /// Horizontal padding
    var horizontalPadding: CGFloat {
        switch self {
        case .compact: return 6
        case .regular: return 8
        case .large: return 10
        }
    }

    /// Vertical padding
    var verticalPadding: CGFloat {
        switch self {
        case .compact: return 3
        case .regular: return 4
        case .large: return 5
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        LiveBadge(size: .compact)
        LiveBadge(size: .regular)
        LiveBadge(size: .large)
        LiveBadge(size: .regular, animated: false)
    }
    .padding()
}
