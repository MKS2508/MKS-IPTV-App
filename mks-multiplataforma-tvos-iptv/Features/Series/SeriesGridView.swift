//
//  SeriesGridView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Stub for Block 4. Renders a placeholder while Series flow is wired.
//

import SwiftUI

struct SeriesGridView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "tv")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Series")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text("Coming next")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
