//
//  NativeLaunchScreen.swift
//  mks-multiplatform-iptv
//
//  Native launch screen following Apple HIG for iOS 26+/macOS 26+
//  Uses skeleton loading pattern with shimmer effect
//

import SwiftUI

/// Native launch screen that follows Apple Human Interface Guidelines
/// - Uses skeleton loading pattern (shows app structure)
/// - Subtle loading indicators
/// - Seamless transition to main app content
struct NativeLaunchScreen: View {
    let loadingStatus: String

    var body: some View {
        ZStack {
            // Native dark background
            Color.black.ignoresSafeArea()

            // Subtle gradient for depth
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.04, green: 0.01, blue: 0.01),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            contentView
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading \(loadingStatus)")
    }

    // MARK: - Content

    private var contentView: some View {
        VStack(spacing: 0) {
            // Header skeleton
            headerSkeleton
                .padding(.horizontal)
                .padding(.vertical, 16)

            Divider()
                .background(Color.white.opacity(0.1))

            // Content skeleton (grid)
            contentGridSkeleton
                .padding()
        }
    }

    // MARK: - Header Skeleton

    private var headerSkeleton: some View {
        HStack {
            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerColor)
                .frame(width: 120, height: 24)

            Spacer()

            // Button skeletons
            HStack(spacing: 12) {
                Circle()
                    .fill(shimmerColor)
                    .frame(width: 28, height: 28)

                Circle()
                    .fill(shimmerColor)
                    .frame(width: 28, height: 28)
            }
        }
    }

    // MARK: - Content Grid Skeleton

    private var contentGridSkeleton: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
                ],
                spacing: 20
            ) {
                ForEach(0..<12, id: \.self) { _ in
                    cardSkeleton
                }
            }
        }
    }

    private var cardSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Poster skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(shimmerColor)
                .aspectRatio(2/3, contentMode: .fit)

            // Title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerColor)
                .frame(height: 16)

            // Subtitle skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerColor)
                .frame(height: 12)
                .frame(maxWidth: 80)
        }
    }

    // MARK: - Shimmer Color

    private var shimmerColor: Color {
        Color.white.opacity(0.08)
    }
}

// MARK: - Preview

#Preview("Native Launch Screen") {
    NativeLaunchScreen(loadingStatus: "Connecting to server...")
}
