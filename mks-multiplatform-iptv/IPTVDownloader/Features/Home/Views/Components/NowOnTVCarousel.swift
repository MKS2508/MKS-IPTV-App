//
//  NowOnTVCarousel.swift
//  mks-multiplatform-iptv
//
//  Horizontal carousel of channels currently airing with EPG programme data
//

import SwiftUI

struct NowOnTVCarousel: View {
    let channels: [(liveChannel: LiveChannel, epgChannel: EPGChannel?, programme: EPGProgramme)]
    @Binding var selectedView: String?

    var body: some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(channels.enumerated()), id: \.offset) { _, entry in
                        Button {
                            selectedView = NavigationDestination.liveChannels.rawValue
                        } label: {
                            HomeChannelCard(
                                liveChannel: entry.liveChannel,
                                epgChannel: entry.epgChannel,
                                programme: entry.programme
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
