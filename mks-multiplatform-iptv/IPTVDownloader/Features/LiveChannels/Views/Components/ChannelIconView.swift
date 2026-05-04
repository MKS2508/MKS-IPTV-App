//
//  ChannelIconView.swift
//  mks-multiplatform-iptv
//
//  Async image loader for channel icons with skeleton placeholder.
//  Uses CachedAsyncImage with Liquid Glass styling.
//

import SwiftUI
import IPTVCore

// MARK: - Channel Icon View

/// Async image view for channel icons with skeleton loading state.
/// Provides consistent styling and error handling for channel logos.
struct ChannelIconView: View {
    // MARK: - Properties

    /// URL of the channel icon
    let url: URL?

    /// Size of the icon
    var size: CGSize

    /// Corner radius for the icon
    var cornerRadius: CGFloat

    /// Whether to show a placeholder on error
    var showPlaceholderOnError: Bool

    // MARK: - Initialization

    init(
        url: URL?,
        size: CGSize = CGSize(width: 64, height: 64),
        cornerRadius: CGFloat = 12,
        showPlaceholderOnError: Bool = true
    ) {
        self.url = url
        self.size = size
        self.cornerRadius = cornerRadius
        self.showPlaceholderOnError = showPlaceholderOnError
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    skeletonPlaceholder

                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                case .failure:
                    errorPlaceholder
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    // MARK: - Private Views

    private var skeletonPlaceholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size.width, height: size.height)
            .overlay(
                // Shimmer effect
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: size.width * 0.3, height: size.height)
                    .offset(x: shimmerOffset)
                    .animation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                        value: true
                    )
            )
    }

    private var errorPlaceholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.1))
            .frame(width: size.width, height: size.height)
            .overlay(
                Image(systemName: "tv")
                    .font(.system(size: size.width * 0.4))
                    .foregroundColor(.white.opacity(0.3))
            )
    }

    // MARK: - Private Properties

    @State private var shimmerOffset: CGFloat = -100
}

// MARK: - Platform-Specific Sizes

extension ChannelIconView {
    /// Creates a platform-adaptive icon size
    /// - Returns: CGSize appropriate for the current platform
    static var adaptiveSize: CGSize {
        #if os(iOS)
        return CGSize(width: 56, height: 56)
        #elseif os(macOS)
        return CGSize(width: 64, height: 64)
        #elseif os(tvOS)
        return CGSize(width: 80, height: 80)
        #else
        return CGSize(width: 56, height: 56)
        #endif
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        ChannelIconView(url: URL(string: "https://example.com/icon.jpg"))
        ChannelIconView(url: nil)
        ChannelIconView(url: URL(string: "invalid-url"))
    }
    .padding()
}
