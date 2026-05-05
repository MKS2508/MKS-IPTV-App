//
//  CategoryRowView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Apple TV+ style horizontal scroll row.
//  Padding 48pt, peek del siguiente card, glass title.
//

import SwiftUI

struct CategoryRowView<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    let card: (Item) -> Card

    private let leadingPadding: CGFloat = 48
    private let spacing: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            categoryTitle

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(items) { item in
                        card(item)
                    }
                }
                .padding(.horizontal, leadingPadding)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
    }

    private var categoryTitle: some View {
        Text(title.uppercased())
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .tracking(1.5)
            .padding(.leading, leadingPadding)
    }
}


