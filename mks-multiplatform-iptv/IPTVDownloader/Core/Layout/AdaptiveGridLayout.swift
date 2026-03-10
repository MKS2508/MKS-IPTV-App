//
//  AdaptiveGridLayout.swift
//  mks-multiplatform-iptv
//
//  Adaptive grid layout for media cards with platform-specific optimizations
//  Target: iOS 26+, macOS 26+
//

import SwiftUI

// MARK: - Adaptive Grid Configuration

/// Configuration for adaptive grid layouts
struct AdaptiveGridConfiguration {
    /// Minimum item width
    let minItemWidth: CGFloat

    /// Maximum item width
    let maxItemWidth: CGFloat

    /// Item height (aspect ratio based)
    let itemHeight: CGFloat

    /// Spacing between items
    let spacing: CGFloat

    /// Padding around the grid
    let edgePadding: CGFloat

    // MARK: - Platform Presets

    /// macOS configuration
    static let macOS = AdaptiveGridConfiguration(
        minItemWidth: 150,
        maxItemWidth: 220,
        itemHeight: 240,
        spacing: 16,
        edgePadding: 24
    )

    /// iPad configuration
    static let iPad = AdaptiveGridConfiguration(
        minItemWidth: 160,
        maxItemWidth: 200,
        itemHeight: 260,
        spacing: 16,
        edgePadding: 20
    )

    /// iPhone portrait configuration
    static let iPhonePortrait = AdaptiveGridConfiguration(
        minItemWidth: 140,
        maxItemWidth: 180,
        itemHeight: 220,
        spacing: 12,
        edgePadding: 16
    )

    /// iPhone landscape configuration
    static let iPhoneLandscape = AdaptiveGridConfiguration(
        minItemWidth: 140,
        maxItemWidth: 180,
        itemHeight: 200,
        spacing: 12,
        edgePadding: 16
    )

    /// tvOS configuration
    static let tvOS = AdaptiveGridConfiguration(
        minItemWidth: 250,
        maxItemWidth: 320,
        itemHeight: 380,
        spacing: 40,
        edgePadding: 60
    )

    // MARK: - Dynamic Configuration

    /// Get configuration based on current platform and size class
    static func current(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> AdaptiveGridConfiguration {
        #if os(macOS)
        return .macOS
        #elseif os(tvOS)
        return .tvOS
        #elseif os(iOS)
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let isLandscape = verticalSizeClass == .compact

        if isIPad {
            return .iPad
        } else {
            return isLandscape ? .iPhoneLandscape : .iPhonePortrait
        }
        #else
        return .macOS
        #endif
    }
}

// MARK: - Adaptive Grid View

/// A grid layout that adapts to platform and size class
struct AdaptiveGridView<Item: Identifiable, ItemView: View>: View {
    let items: [Item]
    @ViewBuilder let itemView: (Item) -> ItemView

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var gridConfiguration: AdaptiveGridConfiguration

    init(
        items: [Item],
        configuration: AdaptiveGridConfiguration? = nil,
        @ViewBuilder itemView: @escaping (Item) -> ItemView
    ) {
        self.items = items
        self._gridConfiguration = State(initialValue: configuration ?? .current(
            horizontalSizeClass: nil,
            verticalSizeClass: nil
        ))
        self.itemView = itemView
    }

    var body: some View {
        let columns = computeColumns()

        LazyVGrid(
            columns: columns,
            spacing: gridConfiguration.spacing
        ) {
            ForEach(items) { item in
                itemView(item)
                    .aspectRatio(
                        (gridConfiguration.minItemWidth + gridConfiguration.maxItemWidth) / 2 / gridConfiguration.itemHeight,
                        contentMode: .fit
                    )
            }
        }
        .padding(.horizontal, gridConfiguration.edgePadding)
        .padding(.vertical, gridConfiguration.spacing)
        .onAppear {
            updateConfiguration()
        }
        .onChange(of: horizontalSizeClass) { _, _ in
            updateConfiguration()
        }
        .onChange(of: verticalSizeClass) { _, _ in
            updateConfiguration()
        }
    }

    private func updateConfiguration() {
        gridConfiguration = .current(
            horizontalSizeClass: horizontalSizeClass,
            verticalSizeClass: verticalSizeClass
        )
    }

    private func computeColumns() -> [GridItem] {
        // Use adaptive grid item for responsive layout
        let adaptiveItem = GridItem(
            .adaptive(
                minimum: gridConfiguration.minItemWidth,
                maximum: gridConfiguration.maxItemWidth
            ),
            spacing: gridConfiguration.spacing
        )

        return [adaptiveItem]
    }
}

// MARK: - Flexible Grid Layout

/// More flexible grid that maintains consistent item sizes
struct FlexibleGridView<Item: Identifiable, ItemView: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let itemHeight: CGFloat
    let spacing: CGFloat
    let edgePadding: CGFloat
    @ViewBuilder let itemView: (Item) -> ItemView

    var body: some View {
        GeometryReader { geometry in
            let columns = max(1, Int((geometry.size.width - edgePadding * 2 + spacing) / (itemWidth + spacing)))
            let actualItemWidth = (geometry.size.width - edgePadding * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns)

            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(actualItemWidth), spacing: spacing),
                        count: columns
                    ),
                    spacing: spacing
                ) {
                    ForEach(items) { item in
                        itemView(item)
                            .frame(width: actualItemWidth, height: itemHeight)
                    }
                }
                .padding(.horizontal, edgePadding)
                .padding(.vertical, spacing)
            }
        }
    }
}

// MARK: - View Extension for Easy Access

extension View {
    /// Wrap in adaptive grid container
    func adaptiveGridFrame(
        configuration: AdaptiveGridConfiguration = .macOS
    ) -> some View {
        self.frame(
            minWidth: configuration.minItemWidth,
            maxWidth: configuration.maxItemWidth,
            minHeight: configuration.itemHeight * 0.8,
            maxHeight: configuration.itemHeight
        )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewItem: Identifiable {
        let id = UUID()
        let title: String
    }

    let items = (1...20).map { PreviewItem(title: "Item \($0)") }

    return AdaptiveGridView(items: items) { item in
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.3))
                .aspectRatio(2/3, contentMode: .fit)
            Text(item.title)
                .font(.caption)
        }
    }
    .background(Color.black)
}
