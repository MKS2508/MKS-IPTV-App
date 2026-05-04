//
//  HomeMediaCarousel.swift
//  mks-multiplatform-iptv
//
//  Apple TV-style horizontal carousel for MediaLibraryItem arrays (movies/series).
//  Features:
//  - Native Liquid Glass container (iOS 26+)
//  - Smooth scrolling with proper spacing
//  - Focus-friendly for tvOS
//

import SwiftUI
import IPTVCore

// MARK: - Home Media Carousel

/// Apple TV-style horizontal carousel for movies and series.
///
/// **Design Features:**
/// - Native GlassEffectContainer for grouped glass elements
/// - Proper spacing that matches container spacing
/// - Lazy loading for performance
/// - tvOS focus support
///
struct HomeMediaCarousel: View {
    let items: [any MediaLibraryItem]
    @Binding var selectedView: String?

    // MARK: - Platform-Specific Spacing

    private var cardSpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 12
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
        return 80
        #else
        return 20
        #endif
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26, macOS 26, tvOS 26, *) {
                GlassEffectContainer(spacing: cardSpacing) {
                    carouselContent
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                carouselContent
                    .padding(.horizontal, horizontalPadding)
            }
        }
    }

    // MARK: - Carousel Content

    private var carouselContent: some View {
        LazyHStack(spacing: cardSpacing) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HomeMediaCard(
                    item: item,
                    selectedView: $selectedView
                )
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Preview

#Preview("Media Carousel") {
    HomeMediaCarousel(
        items: [
            Movie(
                name: "Dune: Part Two",
                streamType: "movie",
                streamId: 1,
                tmdbId: nil,
                streamIcon: nil,
                rating: "8.5",
                rating5Based: 4.25,
                added: nil,
                isAdult: "0",
                categoryId: "1",
                containerExtension: "mp4",
                customSid: nil,
                directSource: nil
            ),
            Movie(
                name: "Oppenheimer",
                streamType: "movie",
                streamId: 2,
                tmdbId: nil,
                streamIcon: nil,
                rating: "9.0",
                rating5Based: 4.5,
                added: nil,
                isAdult: "0",
                categoryId: "1",
                containerExtension: "mp4",
                customSid: nil,
                directSource: nil
            ),
            Movie(
                name: "Barbie",
                streamType: "movie",
                streamId: 3,
                tmdbId: nil,
                streamIcon: nil,
                rating: "7.5",
                rating5Based: 3.75,
                added: nil,
                isAdult: "0",
                categoryId: "1",
                containerExtension: "mp4",
                customSid: nil,
                directSource: nil
            ),
        ],
        selectedView: .constant(nil)
    )
    .background(Color.black)
}
