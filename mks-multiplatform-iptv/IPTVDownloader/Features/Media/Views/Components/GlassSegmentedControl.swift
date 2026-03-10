//
//  GlassSegmentedControl.swift
//  mks-multiplatform-iptv
//
//  Reusable glass-styled segmented control for content type filtering
//  Uses native glassEffect with fallback to ultraThinMaterial on older OS versions
//

import SwiftUI

// MARK: - Glass Segmented Control

/// A glass-styled segmented control that adapts to iOS 26+/macOS 26+ Liquid Glass API
/// with graceful fallback to ultraThinMaterial on older versions.
struct GlassSegmentedControl<Option: Hashable & Identifiable>: View where Option: Equatable {
    // MARK: - Properties

    @Binding var selectedOption: Option
    let options: [Option]
    let titleForKeyPath: KeyPath<Option, String>
    let systemImageForKeyPath: KeyPath<Option, String>?

    // MARK: - Initialization

    /// Creates a glass segmented control
    /// - Parameters:
    ///   - selectedOption: Binding to the currently selected option
    ///   - options: Array of options to display
    ///   - titleForKeyPath: KeyPath to the title string for each option
    ///   - systemImageForKeyPath: Optional KeyPath to SF Symbol name for each option
    init(
        selectedOption: Binding<Option>,
        options: [Option],
        titleForKeyPath: KeyPath<Option, String>,
        systemImageForKeyPath: KeyPath<Option, String>? = nil
    ) {
        self._selectedOption = selectedOption
        self.options = options
        self.titleForKeyPath = titleForKeyPath
        self.systemImageForKeyPath = systemImageForKeyPath
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                GlassSegmentButton(
                    title: option[keyPath: titleForKeyPath],
                    systemImage: systemImageForKeyPath.map { option[keyPath: $0] },
                    isSelected: selectedOption == option
                ) {
                    selectOption(option)
                }
            }
        }
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppGlass.cornerRadius)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Private Methods

    private func selectOption(_ option: Option) {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            selectedOption = option
        }
    }
}

// MARK: - Glass Segment Button

/// Individual button within the glass segmented control
private struct GlassSegmentButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .fontWeight(.semibold)
                .frame(minWidth: 80)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color.accentColor)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 3)
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(GlassScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Glass Scale Button Style

/// Custom button style with scale effect for glass segmented controls
private struct GlassScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Glass Segmented Control") {
    struct PreviewWrapper: View {
        enum ContentType: String, CaseIterable, Identifiable {
            case all = "All"
            case movies = "Movies"
            case series = "Series"

            var id: String { rawValue }
            var title: String { rawValue }
            var systemImage: String {
                switch self {
                case .all: return "play.rectangle.on.rectangle.fill"
                case .movies: return "film.fill"
                case .series: return "tv.fill"
                }
            }
        }

        @State private var selectedOption: ContentType = .all

        var body: some View {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()

                VStack(spacing: 20) {
                    GlassSegmentedControl(
                        selectedOption: $selectedOption,
                        options: ContentType.allCases,
                        titleForKeyPath: \.title,
                        systemImageForKeyPath: \.systemImage
                    )

                    Text("Selected: \(selectedOption.title)")
                        .foregroundColor(.white)
                }
                .padding()
            }
        }
    }

    return PreviewWrapper()
}
