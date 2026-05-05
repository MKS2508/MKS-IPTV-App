//
//  FocusableCardModifier.swift
//  mks-multiplataforma-tvos-iptv
//
//  Parallax 3D card focus: scale + lift + shadow depth + optional glass overlay.
//  Usa .modifier(FocusableCard()) en cualquier card.
//

import SwiftUI

// MARK: - FocusableCardModifier

struct FocusableCard: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var liftOnFocus: CGFloat = 8
    var scaleOnFocus: CGFloat = 1.06
    var shadowRadiusFocused: CGFloat = 32
    var shadowRadiusUnfocused: CGFloat = 10
    var shadowYFocused: CGFloat = 20
    var shadowYUnfocused: CGFloat = 5
    var shadowOpacityFocused: Double = 0.7
    var shadowOpacityUnfocused: Double = 0.3
    var onFocusChanged: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFocused && !reduceMotion ? scaleOnFocus : 1.0)
            .offset(y: isFocused && !reduceMotion ? -liftOnFocus : 0)
            .shadow(
                color: .black.opacity(isFocused ? shadowOpacityFocused : shadowOpacityUnfocused),
                radius: isFocused ? shadowRadiusFocused : shadowRadiusUnfocused,
                x: 0,
                y: isFocused ? shadowYFocused : shadowYUnfocused
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .onChange(of: isFocused) { _, focused in
                onFocusChanged?(focused)
            }
    }
}

extension View {
    func tvFocusableCard(
        liftOnFocus: CGFloat = 8,
        scaleOnFocus: CGFloat = 1.06,
        onFocusChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        modifier(FocusableCard(
            liftOnFocus: liftOnFocus,
            scaleOnFocus: scaleOnFocus,
            onFocusChanged: onFocusChanged
        ))
    }
}

// MARK: - CardButtonStyle

struct CardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var cardWidth: CGFloat = 320
    var cardHeight: CGFloat = 480

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Glass Badge (tvOS 26+)

struct GlassBadge: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
            }
            Text(text)
                .font(.caption.weight(.heavy))
                .tracking(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassify()
    }
}

extension View {
    @ViewBuilder
    func glassify() -> some View {
        if #available(tvOS 26, *) {
            self.glassEffect(.regular.tint(.black.opacity(0.15)), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .clipShape(Capsule())
        }
    }
}

// MARK: - Glass Metadata Pill

struct GlassPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassify()
    }
}

// MARK: - Glass Overlay Modifier

struct GlassOverlayModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.white.opacity(isFocused ? 0.08 : 0))
            )
    }
}

extension View {
    func glassOverlay() -> some View {
        modifier(GlassOverlayModifier())
    }
}

// MARK: - Glass Prominent Button Style

struct GlassProminentCompatButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(playButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .opacity(configuration.isPressed && !reduceMotion ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private var playButtonBackground: some View {
        if #available(tvOS 26, *) {
            RoundedRectangle(cornerRadius: 12)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
        } else {
            Color.white
        }
    }
}

// MARK: - Focus Tracking View (detects focus changes on any view)

struct FocusTrackingView<Content: View>: View {
    let content: Content
    let onFocusChanged: (Bool) -> Void

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        content
            .onChange(of: isFocused) { _, focused in
                onFocusChanged(focused)
            }
    }
}

extension View {
    func onFocusChanged(_ handler: @escaping (Bool) -> Void) -> some View {
        FocusTrackingView(content: self, onFocusChanged: handler)
    }
}

// MARK: - Parallax Offset Modifier

struct ParallaxOffsetModifier: ViewModifier {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var maxOffset: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .offset(
                x: isFocused && !reduceMotion ? maxOffset : 0,
                y: isFocused && !reduceMotion ? maxOffset * 0.5 : 0
            )
            .animation(.easeInOut(duration: 0.25), value: isFocused)
    }
}

extension View {
    func tvParallax(maxOffset: CGFloat = 12) -> some View {
        modifier(ParallaxOffsetModifier(maxOffset: maxOffset))
    }
}
