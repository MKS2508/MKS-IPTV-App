//
//  EPGProgressBar.swift
//  mks-multiplatform-iptv
//
//  Progress bar showing current programme progress with Liquid Glass styling.
//

import SwiftUI
import IPTVCore

// MARK: - EPG Progress Bar

/// Progress bar component showing the current progress through a TV programme.
/// Uses Liquid Glass styling with platform-adaptive sizing.
struct EPGProgressBar: View {
    // MARK: - Properties

    /// Progress value from 0.0 to 1.0
    let progress: Double

    /// Whether to show the progress percentage
    var showPercentage: Bool

    /// Corner radius of the bar
    var cornerRadius: CGFloat

    // MARK: - Initialization

    init(
        progress: Double,
        showPercentage: Bool = false,
        cornerRadius: CGFloat = 4
    ) {
        self.progress = progress
        self.showPercentage = showPercentage
        self.cornerRadius = cornerRadius
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.15))

                // Progress fill
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(progressGradient)
                    .frame(width: max(geometry.size.width * min(progress, 1.0), 1))

                // Optional percentage text
                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(progress * 100)) percent complete")
    }

    // MARK: - Private Properties

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color.accentColor.opacity(0.7)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EPGProgressBar(progress: 0.0)
        EPGProgressBar(progress: 0.25)
        EPGProgressBar(progress: 0.5)
        EPGProgressBar(progress: 0.75)
        EPGProgressBar(progress: 1.0)
        EPGProgressBar(progress: 0.6, showPercentage: true)
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
