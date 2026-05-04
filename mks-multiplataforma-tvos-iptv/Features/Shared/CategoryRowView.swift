//
//  CategoryRowView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Generic horizontal-scroll row of focusable cards.
//  Apple TV+ style: title above, lazy horizontal stack below.
//

import SwiftUI

struct CategoryRowView<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    let card: (Item) -> Card

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
        }
    }
}
