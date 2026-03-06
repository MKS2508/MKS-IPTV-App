import SwiftUI

/// Universal grid container that properly handles overflow across iOS and macOS
/// Follows Apple's recommended patterns for LazyVGrid implementation with dynamic sizing
struct GridLayoutContainer<Content: View>: View {
    let content: () -> Content

    // Platform-optimized configuration
    #if os(iOS)
    private let cardMinWidth: CGFloat = 140
    private let cardMaxWidth: CGFloat = 200
    private let gridSpacing: CGFloat = 14
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 16
    #else
    private let cardMinWidth: CGFloat = 150
    private let cardMaxWidth: CGFloat = 220
    private let gridSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 20
    #endif

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cardMinWidth, maximum: cardMaxWidth), spacing: gridSpacing, alignment: .top)],
                spacing: gridSpacing
            ) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .scrollIndicators(.automatic)
    }
}

/// Specialized grid container for media content (Movies/Series/Live TV)
struct MediaGridContainer<Content: View>: View {
    let content: () -> Content
    let isEmpty: Bool
    let isLoading: Bool
    let error: Error?
    let onRetry: (() -> Void)?

    var body: some View {
        Group {
            if isLoading {
                glassLoadingState
            } else if let error = error {
                glassErrorState(error: error)
            } else if isEmpty {
                glassEmptyState
            } else {
                GridLayoutContainer(content: content)
            }
        }
    }

    // MARK: - Glass-Styled State Views

    private var glassLoadingState: some View {
        VStack(spacing: 16) {
            if #available(iOS 26, macOS 26, tvOS 26, *) {
                ProgressView()
                    .scaleEffect(1.5)
                    .glassEffect(.regular, in: Circle())
            } else {
                ProgressView()
                    .scaleEffect(1.5)
            }
            Text("Loading...")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func glassErrorState(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Error Loading Content")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let onRetry = onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.appGlassProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glassEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No Content Available")
                .font(.headline)

            Text("No items match your current filters")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview
struct GridLayoutContainer_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MediaGridContainer(
                content: {
                    ForEach(0..<20, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue.gradient)
                            .frame(height: 120)
                            .overlay(
                                Text("Item \(index + 1)")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            )
                    }
                },
                isEmpty: false,
                isLoading: false,
                error: nil,
                onRetry: nil
            )
            .navigationTitle("Grid Preview")
        }
        .previewDisplayName("Working Grid")
        
        NavigationView {
            MediaGridContainer(
                content: { EmptyView() },
                isEmpty: true,
                isLoading: false,
                error: nil,
                onRetry: nil
            )
            .navigationTitle("Empty State")
        }
        .previewDisplayName("Empty State")
    }
}