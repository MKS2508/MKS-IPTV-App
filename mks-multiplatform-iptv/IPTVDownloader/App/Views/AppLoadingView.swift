//
//  AppLoadingView.swift
//  mks-multiplatform-iptv
//
//  Extracted from ContentView - Loading/Splash screen with animations
//

import SwiftUI

/// Animated loading view displayed while app initializes data
struct AppLoadingView: View {
    let loadingStatus: String

    // Animation states
    @State private var animatingScale = false
    @State private var animatingRotation = false
    @State private var animatingOpacity = false
    @State private var animatingDots = [false, false, false]

    // MARK: - Color Palette
    private let primaryRed = Color(red: 0.863, green: 0.165, blue: 0.157)
    private let darkRed = Color(red: 0.502, green: 0.000, blue: 0.000)

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading \(loadingStatus)")
        .onAppear {
            startAnimations()
        }
    }

    // MARK: - Background Layer

    private var backgroundLayer: some View {
        #if os(iOS)
        iosBackground
        #else
        macOSBackground
        #endif
    }

    #if os(iOS)
    private var iosBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.05, blue: 0.05),
                Color(red: 0.15, green: 0.05, blue: 0.05),
                Color(red: 0.1, green: 0.05, blue: 0.05)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(redGlowOverlay)
    }
    #endif

    #if os(macOS)
    private var macOSBackground: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05)
                .ignoresSafeArea()

            VisualEffect(blurStyle: .dark, vibrancy: true, opacity: 0.3)
                .ignoresSafeArea()

            redGlowOverlay
        }
    }
    #endif

    private var redGlowOverlay: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                primaryRed.opacity(0.15),
                Color.clear
            ]),
            center: .center,
            startRadius: 100,
            endRadius: 400
        )
        .ignoresSafeArea()
    }

    // MARK: - Content Layer

    private var contentLayer: some View {
        VStack(spacing: 30) {
            logoView
            statusView
        }
    }

    private var logoView: some View {
        ZStack {
            outerGlowCircle
            mainLogoCircle
            tvIcon
        }
        .shadow(color: primaryRed.opacity(0.6), radius: 30, x: 0, y: 15)
    }

    private var outerGlowCircle: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        primaryRed.opacity(0.3),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 80
                )
            )
            .frame(width: 140, height: 140)
            .blur(radius: 10)
    }

    private var mainLogoCircle: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [primaryRed, darkRed],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 100, height: 100)
            .overlay(circleStroke)
            .scaleEffect(animatingScale ? 1.1 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                value: animatingScale
            )
    }

    private var circleStroke: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.2, blue: 0.2).opacity(0.5),
                        Color(red: 0.3, green: 0.0, blue: 0.0).opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
    }

    private var tvIcon: some View {
        Image(systemName: "tv.fill")
            .font(.system(size: 50))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            .rotationEffect(.degrees(animatingRotation ? 5 : -5))
            .animation(
                Animation.easeInOut(duration: 2)
                    .repeatForever(autoreverses: true),
                value: animatingRotation
            )
    }

    private var statusView: some View {
        VStack(spacing: 12) {
            titleText
            statusText
            progressDots
        }
    }

    private var titleText: some View {
        Text("IPTV Player")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [.white, .white.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(animatingOpacity ? 1 : 0.7)
            .animation(
                Animation.easeInOut(duration: 1)
                    .repeatForever(autoreverses: true),
                value: animatingOpacity
            )
    }

    private var statusText: some View {
        Text(loadingStatus)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
    }

    private var progressDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [primaryRed, darkRed],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .scaleEffect(animatingDots[index] ? 1.5 : 0.8)
                    .opacity(animatingDots[index] ? 1.0 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animatingDots[index]
                    )
            }
        }
        .padding(.top, 10)
    }

    // MARK: - Animation Control

    private func startAnimations() {
        animatingScale = true
        animatingRotation = true
        animatingOpacity = true
        for index in 0..<3 {
            animatingDots[index] = true
        }
    }
}

// MARK: - Preview

#Preview {
    AppLoadingView(loadingStatus: "Connecting to server...")
}
