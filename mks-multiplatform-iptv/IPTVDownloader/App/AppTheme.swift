//
//  AppTheme.swift
//  mks-multiplatform-iptv
//
//  Global theme configuration for Liquid Glass design system
//  Target: iOS 26+, macOS 26+ - Native Liquid Glass API
//

import SwiftUI

// MARK: - Liquid Glass Availability Detection

/// Detects native Liquid Glass API availability for iOS 26+ / macOS 26+
///
/// **Important**: For gating `.glassEffect()` or `GlassEffectContainer` calls,
/// use `if #available(iOS 26, macOS 26, tvOS 26, *)` directly — the compiler
/// requires a compile-time availability check, not a runtime Bool.
/// This enum is kept for non-API checks (e.g., choosing layout strategies).
enum LiquidGlassAvailability {
    /// Returns true if running on iOS 26+ or macOS 26+ with native Liquid Glass support
    static var isAvailable: Bool {
        #if os(iOS)
        if #available(iOS 26, *) { return true }
        #elseif os(macOS)
        if #available(macOS 26, *) { return true }
        #elseif os(tvOS)
        if #available(tvOS 26, *) { return true }
        #endif
        return false
    }
}

// MARK: - App Colors

/// Global color palette for the app
enum AppColors {
    // MARK: - Accent Colors (Red theme)

    /// Primary accent color - Vibrant red
    static let accent = Color(red: 0.863, green: 0.165, blue: 0.157)

    /// Dark accent - Deep red for gradients
    static let accentDark = Color(red: 0.502, green: 0.000, blue: 0.000)

    /// Light accent - Bright red for highlights
    static let accentLight = Color(red: 1.0, green: 0.3, blue: 0.3)

    // MARK: - Background Colors

    /// Primary background - Near black
    static let background = Color(red: 0.05, green: 0.05, blue: 0.05)

    /// Secondary background - Slightly lighter
    static let backgroundSecondary = Color(red: 0.08, green: 0.08, blue: 0.08)

    /// Elevated surface
    static let surface = Color(red: 0.12, green: 0.12, blue: 0.12)

    // MARK: - Text Colors

    /// Primary text
    static let textPrimary = Color.white

    /// Secondary text
    static let textSecondary = Color.white.opacity(0.7)

    /// Tertiary text
    static let textTertiary = Color.white.opacity(0.5)

    // MARK: - Glass Tint

    /// Glass tint color for liquid glass effects
    static let glassTint = Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.2)
}

// MARK: - Glass Configuration

/// Predefined glass configurations for the app
enum AppGlass {
    /// Standard corner radius for glass elements
    static let cornerRadius: CGFloat = 16

    /// Small corner radius for compact elements
    static let cornerRadiusSmall: CGFloat = 12

    /// Large corner radius for prominent elements
    static let cornerRadiusLarge: CGFloat = 24
}

// MARK: - View Extensions

extension View {
    /// Apply standard app glass effect with red tint (iOS 26+/macOS 26+ only)
    @available(iOS 26, macOS 26, tvOS 26, *)
    func appGlass(in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadius)) -> some View {
        self.glassEffect(.regular.tint(AppColors.glassTint), in: shape)
    }

    /// Apply interactive app glass effect (responds to touch/hover)
    @available(iOS 26, macOS 26, tvOS 26, *)
    func appGlassInteractive(in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadius)) -> some View {
        self.glassEffect(.regular.tint(AppColors.glassTint).interactive(), in: shape)
    }

    /// Apply prominent app glass effect (for featured content)
    @available(iOS 26, macOS 26, tvOS 26, *)
    func appGlassProminent(in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadiusLarge)) -> some View {
        self.glassEffect(.regular.tint(AppColors.accent.opacity(0.15)), in: shape)
    }

    // MARK: - Adaptive Glass (Backward Compatible)

    /// Apply adaptive glass effect with fallback to ultraThinMaterial on older OS versions
    /// - Parameters:
    ///   - shape: The shape to clip the glass effect to
    ///   - fallbackOpacity: Opacity for the fallback material (default 1.0)
    @ViewBuilder
    func adaptiveGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadius),
        fallbackOpacity: Double = 1.0
    ) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular.tint(AppColors.glassTint), in: shape)
        } else {
            self.background(.ultraThinMaterial.opacity(fallbackOpacity), in: shape)
        }
    }

    /// Apply adaptive interactive glass effect with fallback on older OS versions
    /// - Parameters:
    ///   - shape: The shape to clip the glass effect to
    ///   - fallbackOpacity: Opacity for the fallback material (default 1.0)
    @ViewBuilder
    func adaptiveGlassInteractive(
        in shape: some Shape = RoundedRectangle(cornerRadius: AppGlass.cornerRadius),
        fallbackOpacity: Double = 1.0
    ) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            self.glassEffect(.regular.tint(AppColors.glassTint).interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial.opacity(fallbackOpacity), in: shape)
        }
    }
}

// MARK: - Glass Effect Container Wrapper

/// Wraps content in a GlassEffectContainer on iOS 26+ / macOS 26+ for proper
/// glass blending between adjacent glass elements. Falls back to plain content on older OS.
struct AdaptiveGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, macOS 26, tvOS 26, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Button Styles

/// Custom glass button style with app accent — adaptive with fallback
struct AppGlassButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)

        if #available(iOS 26, macOS 26, tvOS 26, *) {
            label.glassEffect(
                isProminent
                    ? .regular.tint(AppColors.accent.opacity(0.15))
                    : .regular.tint(AppColors.glassTint).interactive(),
                in: .capsule
            )
        } else {
            label.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

extension ButtonStyle where Self == AppGlassButtonStyle {
    static var appGlass: AppGlassButtonStyle { AppGlassButtonStyle() }
    static var appGlassProminent: AppGlassButtonStyle { AppGlassButtonStyle(isProminent: true) }
}
