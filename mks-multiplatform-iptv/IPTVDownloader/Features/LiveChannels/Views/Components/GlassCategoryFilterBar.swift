//
//  GlassCategoryFilterBar.swift
//  mks-multiplatform-iptv
//
//  Horizontal filter bar with native Liquid Glass styling.
//  Replaces inline CategoryChip with proper GlassEffectContainer grouping.
//

import SwiftUI

// MARK: - Glass Category Filter Bar

/// Horizontal filter bar for categories with native Liquid Glass styling.
/// Uses `GlassEffectContainer` for proper glass blending on iOS 26+.
struct GlassCategoryFilterBar: View {
    // MARK: - Properties

    let categories: [LiveChannelCategory]
    @Binding var selectedCategory: String?
    let favoritesCount: Int
    let onCategorySelected: (String?) -> Void

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var animation

    // MARK: - Body

    var body: some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            glassContent
                .glassEffect(.regular, in: .rect(cornerRadius: AppGlass.cornerRadius))
        } else {
            glassContent
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius))
        }
    }

    // MARK: - Glass Content

    private var glassContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if #available(iOS 26, macOS 26, tvOS 26, *) {
                GlassEffectContainer(spacing: 8) {
                    chipsStack
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                chipsStack
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Chips Stack

    private var chipsStack: some View {
        HStack(spacing: 8) {
            // All categories chip
            GlassCategoryChip(
                title: "All",
                icon: "tv",
                count: nil,
                isSelected: selectedCategory == nil
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedCategory = nil
                    onCategorySelected(nil)
                }
            }

            // Favorites chip (only if favorites exist)
            if favoritesCount > 0 {
                GlassCategoryChip(
                    title: "Favorites",
                    icon: "star.fill",
                    count: favoritesCount,
                    isSelected: selectedCategory == "favorites"
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = "favorites"
                        onCategorySelected("favorites")
                    }
                }
            }

            // Category chips
            ForEach(categories) { category in
                GlassCategoryChip(
                    title: category.categoryName,
                    icon: categoryIcon(for: category.categoryId),
                    count: nil,
                    isSelected: selectedCategory == category.categoryId
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = category.categoryId
                        onCategorySelected(category.categoryId)
                    }
                }
            }
        }
    }

    // MARK: - Category Icons

    private func categoryIcon(for categoryId: String?) -> String? {
        guard let id = categoryId else { return nil }
        let icons: [String: String] = [
            "145": "megaphone.fill",    // Anuncios
            "147": "sportssoccer",      // Deportes
            "148": "newspaper",         // Noticias
            "149": "tv",                // Entretenimiento
            "150": "globe",             // Internacional
            "151": "music.note",        // Música
            "152": "figure.and.child.holdinghands",  // Infantil
            "153": "book",              // Documentales
            "154": "film"               // Películas
        ]
        return icons[id] ?? "tv"
    }
}

// MARK: - Glass Category Chip

/// Individual category chip with Liquid Glass styling.
struct GlassCategoryChip: View {
    let title: String
    let icon: String?
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.medium))
                }

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassChipStyle(isSelected: isSelected)
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Glass Chip Style Extension

private extension View {
    @ViewBuilder
    func glassChipStyle(isSelected: Bool) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            if isSelected {
                self.glassEffect(.prominent.tint(AppColors.accent.opacity(0.3)).interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            if isSelected {
                self.background(Capsule().fill(Color.accentColor))
            } else {
                self.background(.ultraThinMaterial.opacity(0.6), in: Capsule())
            }
        }
    }
}

// MARK: - Previews

#Preview {
    VStack {
        GlassCategoryFilterBar(
            categories: [
                LiveChannelCategory(categoryId: "147", categoryName: "Deportes", parentId: 0),
                LiveChannelCategory(categoryId: "148", categoryName: "Noticias", parentId: 0),
                LiveChannelCategory(categoryId: "149", categoryName: "Entretenimiento", parentId: 0),
            ],
            selectedCategory: .constant(nil),
            favoritesCount: 5,
            onCategorySelected: { _ in }
        )

        GlassCategoryFilterBar(
            categories: [
                LiveChannelCategory(categoryId: "147", categoryName: "Deportes", parentId: 0),
            ],
            selectedCategory: .constant("147"),
            favoritesCount: 0,
            onCategorySelected: { _ in }
        )
    }
    .padding()
}
