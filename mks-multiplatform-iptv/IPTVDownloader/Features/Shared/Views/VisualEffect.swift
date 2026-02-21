//
//  VisualEffect.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 22/3/25.
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Enhanced Cross-Platform Visual Effect Background
struct VisualEffect: View {
    // Common properties that work cross-platform
    var blurStyle: BlurStyle
    var vibrancy: Bool
    var cornerRadius: CGFloat
    var opacity: Double
    
    // Initialize with default values
    init(
        blurStyle: BlurStyle = .systemMaterial,
        vibrancy: Bool = false,
        cornerRadius: CGFloat = 0,
        opacity: Double = 1.0
    ) {
        self.blurStyle = blurStyle
        self.vibrancy = vibrancy
        self.cornerRadius = cornerRadius
        self.opacity = opacity
    }
    
    // Cross-platform blur styles
    enum BlurStyle {
        case systemMaterial
        case systemThinMaterial
        case systemThickMaterial
        case systemUltraThinMaterial
        case systemUltraThickMaterial
        case dark
        case light
        case extraLight
        
        #if os(macOS)
        // Convert to macOS material
        var macOSMaterial: NSVisualEffectView.Material {
            switch self {
            case .systemMaterial, .systemThinMaterial:
                return .windowBackground
            case .systemThickMaterial, .systemUltraThickMaterial:
                return .fullScreenUI
            case .systemUltraThinMaterial:
                return .menu
            case .dark:
#if os (iOS)

                return .darkAqua
                #else
                return .titlebar
#endif
            case .light, .extraLight:
#if os (iOS)

                return .aqua
#else
                return .titlebar
#endif

            }
        }
        #else
        // Convert to iOS blur style
        var iOSBlurStyle: UIBlurEffect.Style {
            switch self {
            case .systemMaterial:
                return .systemMaterial
            case .systemThinMaterial:
                return .systemThinMaterial
            case .systemThickMaterial:
                return .systemThickMaterial
            case .systemUltraThinMaterial:
                return .systemUltraThinMaterial
            case .systemUltraThickMaterial:
                return .systemUltraThinMaterial
            case .dark:
                return .dark
            case .light:
                return .light
            case .extraLight:
                return .extraLight
            }
        }
        #endif
    }
    
    var body: some View {
        #if os(macOS)
        MacVisualEffect(
            material: blurStyle.macOSMaterial,
            vibrancy: vibrancy,
            cornerRadius: cornerRadius,
            opacity: opacity
        )
        #else
        iOSVisualEffect(
            style: blurStyle.iOSBlurStyle,
            vibrancy: vibrancy,
            cornerRadius: cornerRadius,
            opacity: opacity
        )
        #endif
    }
}

// Enhanced macOS Version
#if os(macOS)
struct MacVisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var vibrancy: Bool
    var cornerRadius: CGFloat
    var opacity: Double
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = vibrancy ? .withinWindow : .behindWindow
        
        if cornerRadius > 0 {
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.masksToBounds = true
        }
        
        view.alphaValue = opacity
        
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = vibrancy ? .withinWindow : .behindWindow
        
        if cornerRadius > 0 {
            nsView.layer?.cornerRadius = cornerRadius
        }
        
        nsView.alphaValue = opacity
    }
}
#endif

// Enhanced iOS Version
#if os(iOS)
struct iOSVisualEffect: UIViewRepresentable {
    var style: UIBlurEffect.Style
    var vibrancy: Bool
    var cornerRadius: CGFloat
    var opacity: Double
    
    func makeUIView(context: Context) -> UIView {
        // Create container view to apply corner radius
        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .clear
        
        // Create the blur effect view
        let blurEffect = UIBlurEffect(style: style)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Add vibrancy if needed
        if vibrancy {
            let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
            let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
            vibrancyView.frame = blurView.bounds
            vibrancyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.contentView.addSubview(vibrancyView)
        }
        
        // Configure corner radius
        if cornerRadius > 0 {
            containerView.layer.cornerRadius = cornerRadius
            containerView.layer.masksToBounds = true
        }
        
        // Set up the hierarchy
        containerView.addSubview(blurView)
        blurView.frame = containerView.bounds
        
        // Apply opacity
        blurView.alpha = CGFloat(opacity)
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the blur effect and corner radius if needed
        guard let containerView = uiView as? UIView,
              let blurView = containerView.subviews.first as? UIVisualEffectView else { return }
        
        blurView.effect = UIBlurEffect(style: style)
        
        if cornerRadius > 0 {
            containerView.layer.cornerRadius = cornerRadius
        }
        
        blurView.alpha = CGFloat(opacity)
        
        // Update vibrancy if needed
        if vibrancy && blurView.contentView.subviews.isEmpty {
            if let blurEffect = blurView.effect as? UIBlurEffect {
                let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
                let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
                vibrancyView.frame = blurView.bounds
                vibrancyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                blurView.contentView.addSubview(vibrancyView)
            }
        } else if !vibrancy && !blurView.contentView.subviews.isEmpty {
            for subview in blurView.contentView.subviews {
                subview.removeFromSuperview()
            }
        }
    }
}
#endif

// Extension with common presets
extension VisualEffect {
    // Preset for card backgrounds
    static var card: VisualEffect {
        VisualEffect(
            blurStyle: .systemMaterial,
            vibrancy: false,
            cornerRadius: 16,
            opacity: 0.95
        )
    }
    
    // Preset for modal backgrounds
    static var modal: VisualEffect {
        VisualEffect(
            blurStyle: .systemThickMaterial,
            vibrancy: false,
            cornerRadius: 20,
            opacity: 1.0
        )
    }
    
    // Preset for full screen backgrounds
    static var fullScreen: VisualEffect {
        VisualEffect(
            blurStyle: .systemMaterial,
            vibrancy: false,
            cornerRadius: 0,
            opacity: 1.0
        )
    }
    
    // Preset for dark overlays
    static var darkOverlay: VisualEffect {
        VisualEffect(
            blurStyle: .dark,
            vibrancy: true,
            cornerRadius: 0,
            opacity: 0.85
        )
    }
}

// NUEVO: Modificador para soportar VisualEffect como background
struct VisualEffectModifier: ViewModifier {
    var blurStyle: VisualEffect.BlurStyle
    var vibrancy: Bool
    var cornerRadius: CGFloat
    var opacity: Double
    var ignoresSafeAreaEdges: Edge.Set
    
    func body(content: Content) -> some View {
        content
            .background(
                VisualEffect(
                    blurStyle: blurStyle,
                    vibrancy: vibrancy,
                    cornerRadius: cornerRadius,
                    opacity: opacity
                )
                .edgesIgnoringSafeArea(ignoresSafeAreaEdges)
            )
    }
}

// NUEVO: Extensión de View para usar VisualEffect como background
extension View {
    func visualEffectBackground(
        blurStyle: VisualEffect.BlurStyle = .systemMaterial,
        vibrancy: Bool = false,
        cornerRadius: CGFloat = 0,
        opacity: Double = 1.0,
        ignoresSafeAreaEdges: Edge.Set = []
    ) -> some View {
        self.modifier(
            VisualEffectModifier(
                blurStyle: blurStyle,
                vibrancy: vibrancy,
                cornerRadius: cornerRadius,
                opacity: opacity,
                ignoresSafeAreaEdges: ignoresSafeAreaEdges
            )
        )
    }
}

// NUEVO: Extensión para permitir usar VisualEffect en el método .background directamente
extension VisualEffect {
    func asBackgroundModifier(ignoresSafeAreaEdges: Edge.Set = []) -> some ViewModifier {
        VisualEffectModifier(
            blurStyle: self.blurStyle,
            vibrancy: self.vibrancy,
            cornerRadius: self.cornerRadius,
            opacity: self.opacity,
            ignoresSafeAreaEdges: ignoresSafeAreaEdges
        )
    }
}

// NUEVO: Ejemplo de uso
/*
// En lugar de:
.background(VisualEffect())

// Puedes usar:
.visualEffectBackground()

// O bien:
.background {
    VisualEffect()
}

// Con parámetros personalizados:
.visualEffectBackground(blurStyle: .dark, cornerRadius: 10, ignoresSafeAreaEdges: .all)

// Con presets:
.visualEffectBackground(
    blurStyle: .systemMaterial,
    cornerRadius: 16,
    opacity: 0.95
)
*/
