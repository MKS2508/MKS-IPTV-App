//
//  GlassCategoryChip.swift
//  mks-multiplatform-iptv
//
//  Glass-styled category filter chips with interactive glass effects
//  Includes GlassCategoryChipsContainer for horizontal scrolling
//

import SwiftUI

// MARK: - Glass Category Chip

/// A glass-styled chip for displaying and removing selected category filters
struct GlassCategoryChip: View {
    // MARK: - Properties

    let categoryId: String
    let categoryName: String
    let onRemove: () -> Void

    // MARK: - Body

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 4) {
                Text(categoryName)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.2))
            )
            .overlay(
                Capsule()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .adaptiveGlassInteractive(in: Capsule(), fallbackOpacity: 0.6)
    }
}

// MARK: - Glass Category Chips Container

/// A horizontally scrolling container for glass category chips
struct GlassCategoryChipsContainer: View {
    // MARK: - Properties

    let categories: Set<String>
    let categoryNameProvider: (String) -> String
    let onRemoveCategory: (String) -> Void

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(categories), id: \.self) { categoryId in
                    GlassCategoryChip(
                        categoryId: categoryId,
                        categoryName: categoryNameProvider(categoryId),
                        onRemove: { onRemoveCategory(categoryId) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall), fallbackOpacity: 0.25)
    }
}

// MARK: - Preview

#Preview("Glass Category Chips") {
    struct PreviewWrapper: View {
        @State private var selectedCategories: Set<String> = ["Action", "Sci-Fi", "Drama"]

        var body: some View {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()

                VStack(spacing: 20) {
                    GlassCategoryChipsContainer(
                        categories: selectedCategories,
                        categoryNameProvider: { $0 },
                        onRemoveCategory: { category in
                            selectedCategories.remove(category)
                        }
                    )
                    .padding()

                    Text("Selected: \(selectedCategories.sorted().joined(separator: ", "))")
                        .foregroundColor(.white)
                        .padding()
                }
            }
        }
    }

    return PreviewWrapper()
}
