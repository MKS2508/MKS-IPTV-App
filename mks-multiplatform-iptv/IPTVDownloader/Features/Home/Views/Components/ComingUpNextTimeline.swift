//
//  ComingUpNextTimeline.swift
//  mks-multiplatform-iptv
//
//  Horizontal timeline of upcoming EPG programmes across channels
//

import SwiftUI

struct ComingUpNextTimeline: View {
    let programmes: [(programme: EPGProgramme, channelName: String)]

    var body: some View {
        AdaptiveGlassContainer {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(programmes.enumerated()), id: \.offset) { _, entry in
                        HomeProgrammeCard(
                            programme: entry.programme,
                            channelName: entry.channelName
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}
