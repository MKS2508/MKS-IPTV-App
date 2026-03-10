//
//  HomeMediaCarousel.swift
//  mks-multiplatform-iptv
//
//  Reusable horizontal carousel for LibraryItem arrays (movies/series)
//  Used for "Added Last 24h", "Added This Week", and category spotlights
//

import SwiftUI

struct HomeMediaCarousel: View {
    let items: [any LibraryItem]
    @Binding var selectedView: String?

    var body: some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HomeMediaCard(
                            item: item,
                            selectedView: $selectedView
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
