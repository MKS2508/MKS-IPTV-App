//
//  CategoryFilterBar.swift
//  mks-multiplatform-iptv
//
//  Horizontal filter bar for Live TV categories with Liquid Glass styling.
//

import SwiftUI
import os

// MARK: - Category Filter Bar

/// Horizontal filter bar for Live TV categories with Liquid Glass styling.
struct CategoryFilterBar: View {
    // MARK: - Properties
    /// Available categories
    let categories: [LiveChannelCategory]

    /// Currently selected category ID (nil for all)
    @Binding var selectedCategory: String?

    /// Callback when a category is selected
    let onCategorySelected: (String) -> Void

    // MARK: - Environment
    @Environment(\.colorScheme) var colorScheme

    private let logger = Logger(subsystem: "CategoryFilterBar", category: "UI")

    // MARK: - Body
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                            .font(.caption)
                        Text("All")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(selectedCategory == nil ? .primary : .secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(selectedBackgroundColor)
                            .opacity(selectedCategory == nil ? 1.0 : 0.7)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("All channels")
                .accessibilityHint("Show all channels")

                // Category buttons
                ForEach(categories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category.categoryId
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: categoryIcon(for: category.categoryId))
                                .font(.caption)
                            Text(category.categoryName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(selectedCategory == category.categoryId ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedBackgroundColor)
                                .opacity(selectedCategory == category.categoryId ? 0.8 : 0.5)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(category.categoryName)
                    .accessibilityHint("Select category")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12), fallbackOpacity: 0.8)
    }

    // MARK: - Platform-Specific Colors
    private var selectedBackgroundColor: Color {
        #if os(iOS)
        Color.accentColor
        #else
        Color.secondary
        #endif
    }

    // MARK: - Private Helpers
    private func categoryIcon(for categoryId: String) -> String {
        // Map known category IDs to icons
        let icons: [String: String] = [
            "145": "megaphone.fill",
            "147": "sportssoccer",
            "148": "newspaper",
            "149": "tv",
            "150": "globe",
            "151": "music.note",
            "152": "person.2",
            "153": "book",
            "154": "film"
        ]
        return icons[categoryId] ?? "tv"
    }
}
