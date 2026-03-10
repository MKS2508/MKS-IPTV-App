//
//  UIComponents.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 20/3/25.
//


// UIComponents.swift - A dedicated file for reusable UI components

import SwiftUI
import AVKit
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Reusable UI Components

// 1. Primero, crea un modificador de vista para el fondo
struct BackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Image("backgroundPattern")  // Nombre del archivo de imagen en Assets.xcassets
                    .resizable(resizingMode: .tile)  // Usar modo tile para patrones repetitivos
                    .ignoresSafeArea()
            )
    }
}

// 2. Extiende View para facilitar su uso
extension View {
    func withAppBackground() -> some View {
        self.modifier(BackgroundModifier())
    }
}

#if os(iOS)
struct EnhancedInfoPill2: View {
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let emoji: String
    
    // Add animation state properties
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            // Create a more sophisticated pill shape with gradient and inner shadow
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                
                // Add subtle gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        backgroundColor.opacity(1.2),
                        backgroundColor.opacity(0.8)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Add subtle inner shadow for depth
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .blur(radius: 0.5)
                    .mask(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.black, Color.clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )
            }
        )
        // Add a slight shadow for depth
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
        // Add a subtle scale animation on hover/tap (for iOS 15+)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        // Detect press on iOS
        .onTapGesture {
            withAnimation {
                isHovered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation {
                        isHovered = false
                    }
                }
            }
        }
    }
}
#elseif os(macOS)
struct EnhancedInfoPill2: View {
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let emoji: String
    
    // Add animation state properties
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            // Create a more sophisticated pill shape with gradient and inner shadow
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                
                // Add subtle gradient overlay
                LinearGradient(
                    gradient: Gradient(colors: [
                        backgroundColor.opacity(1.2),
                        backgroundColor.opacity(0.8)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Add subtle inner shadow for depth
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .blur(radius: 0.5)
                    .mask(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.black, Color.clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    )
            }
        )
        // Add a slight shadow for depth
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
        // Add a subtle scale animation on hover
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        // Detect hover on macOS
        .onHover { hovering in
            isHovered = hovering
        }
        // Also handle click for consistency
        .onTapGesture {
            withAnimation {
                isHovered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation {
                        isHovered = false
                    }
                }
            }
        }
    }
}
#endif

#if os(iOS)
struct EnhancedInfoPill: View {
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let emoji: String
    let action: () -> Void
    
    // Estados unificados con valores por defecto
    @State private var interactionState: InteractionState = .normal
    
    // Enumeración para manejar estados de interacción
    private enum InteractionState {
        case normal, hovered, pressed
        
        var scale: CGFloat {
            switch self {
            case .normal: return 1.0
            case .hovered: return 1.02
            case .pressed: return 0.97
            }
        }
        
        var yOffset: CGFloat {
            switch self {
            case .normal: return 0
            case .hovered: return -0.5
            case .pressed: return 1
            }
        }
        
        var shadowRadius: CGFloat {
            switch self {
            case .normal: return 3
            case .hovered: return 4
            case .pressed: return 2
            }
        }
        
        var shadowYOffset: CGFloat {
            switch self {
            case .normal, .hovered: return 2
            case .pressed: return 1
            }
        }
    }
    
    // Constructor con valor por defecto para action
    init(
        text: String,
        backgroundColor: Color,
        textColor: Color,
        emoji: String,
        action: @escaping () -> Void = {}
    ) {
        self.text = text
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.emoji = emoji
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(pillBackground)
        .shadow(
            color: backgroundColor.opacity(0.3),
            radius: interactionState.shadowRadius,
            x: 0,
            y: interactionState.shadowYOffset
        )
        .scaleEffect(interactionState.scale)
        .offset(y: interactionState.yOffset)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: interactionState)
        // Gestos optimizados
        .onTapGesture {
            hapticFeedback(style: .light)
            withAnimation {
                interactionState = .pressed
                
                // Reestablecer estado con retraso
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        interactionState = .normal
                        action()
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation {
                interactionState = hovering ? .hovered : .normal
            }
        }
    }
    
    // Extracción del fondo a una propiedad computada para mejorar legibilidad
    private var pillBackground: some View {
        ZStack {
            // Capa base con color de fondo
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
            
            // Gradiente sutil optimizado
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [backgroundColor.opacity(0.85), backgroundColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            
            // Borde sutil
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.black.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
    
    // Función para retroalimentación háptica
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
#elseif os(macOS)
struct EnhancedInfoPill: View {
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let emoji: String
    let action: () -> Void
    
    // Estados unificados con valores por defecto
    @State private var interactionState: InteractionState = .normal
    
    // Enumeración para manejar estados de interacción
    private enum InteractionState {
        case normal, hovered, pressed
        
        var scale: CGFloat {
            switch self {
            case .normal: return 1.0
            case .hovered: return 1.02
            case .pressed: return 0.97
            }
        }
        
        var yOffset: CGFloat {
            switch self {
            case .normal: return 0
            case .hovered: return -0.5
            case .pressed: return 1
            }
        }
        
        var shadowRadius: CGFloat {
            switch self {
            case .normal: return 3
            case .hovered: return 4
            case .pressed: return 2
            }
        }
        
        var shadowYOffset: CGFloat {
            switch self {
            case .normal, .hovered: return 2
            case .pressed: return 1
            }
        }
    }
    
    // Constructor con valor por defecto para action
    init(
        text: String,
        backgroundColor: Color,
        textColor: Color,
        emoji: String,
        action: @escaping () -> Void = {}
    ) {
        self.text = text
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.emoji = emoji
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(pillBackground)
        .shadow(
            color: backgroundColor.opacity(0.3),
            radius: interactionState.shadowRadius,
            x: 0,
            y: interactionState.shadowYOffset
        )
        .scaleEffect(interactionState.scale)
        .offset(y: interactionState.yOffset)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: interactionState)
        // Gestos optimizados para macOS
        .onTapGesture {
            withAnimation {
                interactionState = .pressed
                
                // Reestablecer estado con retraso
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        interactionState = .normal
                        action()
                    }
                }
            }
        }
        .onHover { hovering in
            withAnimation {
                interactionState = hovering ? .hovered : .normal
            }
        }
    }
    
    // Extracción del fondo a una propiedad computada para mejorar legibilidad
    private var pillBackground: some View {
        ZStack {
            // Capa base con color de fondo
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
            
            // Gradiente sutil optimizado
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [backgroundColor.opacity(0.85), backgroundColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Borde sutil
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.black.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
    
    // Función para retroalimentación háptica - vacía para macOS
    private func hapticFeedback(style: FeedbackStyle) {
        // No hay equivalente directo para macOS
    }
    
    // Enum para mantener compatibilidad con iOS
    private enum FeedbackStyle {
        case light, medium, heavy
    }
}
#endif

#if os(iOS)
struct MediaBadge: View {
    let icon: String      // Emoji o SF Symbol
    let text: String
    let backgroundColor: Color
    let textColor: Color = .white
    
    @State private var isPressed: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.system(size: 14))
                .foregroundColor(textColor)
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                // Capa base con color principal
                Capsule()
                    .fill(backgroundColor)
                
                // Gradiente base sutilmente más oscuro en la parte inferior
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: backgroundColor, location: 0.0),
                                .init(color: backgroundColor.opacity(0.7), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Efecto de brillo superior pronunciado (shine)
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.7), location: 0.0),
                                .init(color: Color.white.opacity(0.0), location: 0.5)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(CGSize(width: 1.0, height: 0.4))
                    .offset(y: -5)
                
                // Borde interior superior sutil
                Capsule()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.6), location: 0.0),
                                .init(color: Color.white.opacity(0.1), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .scaleEffect(0.98)
                
                // Simulación de "borde exterior" para efecto 3D
                Capsule()
                    .stroke(
                        Color.black.opacity(0.3),
                        lineWidth: 1
                    )
            }
        )
        // Efecto de sombra exterior
        .shadow(
            color: backgroundColor.opacity(0.7),
            radius: 4,
            x: 0,
            y: 2
        )
        // Sombra adicional para mayor profundidad
        .shadow(
            color: Color.black.opacity(0.2),
            radius: 2,
            x: 0,
            y: 1
        )
        // Animación al presionar
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
        .onTapGesture {
            withAnimation {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        isPressed = false
                    }
                }
            }
        }
    }
}
#elseif os(macOS)
struct MediaBadge: View {
    let icon: String      // Emoji o SF Symbol
    let text: String
    let backgroundColor: Color
    let textColor: Color = .white
    
    @State private var isPressed: Bool = false
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.system(size: 14))
                .foregroundColor(textColor)
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                // Capa base con color principal
                Capsule()
                    .fill(backgroundColor)
                
                // Gradiente base sutilmente más oscuro en la parte inferior
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: backgroundColor, location: 0.0),
                                .init(color: backgroundColor.opacity(0.7), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Efecto de brillo superior pronunciado (shine)
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.7), location: 0.0),
                                .init(color: Color.white.opacity(0.0), location: 0.5)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(CGSize(width: 1.0, height: 0.4))
                    .offset(y: -5)
                
                // Borde interior superior sutil
                Capsule()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.6), location: 0.0),
                                .init(color: Color.white.opacity(0.1), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .scaleEffect(0.98)
                
                // Simulación de "borde exterior" para efecto 3D
                Capsule()
                    .stroke(
                        Color.black.opacity(0.3),
                        lineWidth: 1
                    )
            }
        )
        // Efecto de sombra exterior
        .shadow(
            color: backgroundColor.opacity(0.7),
            radius: 4,
            x: 0,
            y: 2
        )
        // Sombra adicional para mayor profundidad
        .shadow(
            color: Color.black.opacity(0.2),
            radius: 2,
            x: 0,
            y: 1
        )
        // Animación al presionar/hover para macOS
        .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.02 : 1.0))
        .animation(.spring(response: 0.2), value: isPressed)
        .animation(.spring(response: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            withAnimation {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        isPressed = false
                    }
                }
            }
        }
    }
}
#endif

#if os(iOS)
// Versión con efecto de neomorfismo (alternativa)
struct EnhancedInfoPill3: View {
    let text: String
    let emoji: String
    var baseColor: Color = Color(UIColor.systemGray5)
    var textColor: Color = .primary
    
    @State private var isPressed: Bool = false
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(baseColor)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 2, y: 2)
                    .shadow(color: Color.white.opacity(0.7), radius: 2, x: -2, y: -2)
            }
        )
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
        .onTapGesture {
            withAnimation {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        isPressed = false
                    }
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
#elseif os(macOS)
// Versión con efecto de neomorfismo para macOS
struct EnhancedInfoPill3: View {
    let text: String
    let emoji: String
    var baseColor: Color = Color.gray.opacity(0.2) // Equivalente macOS para systemGray5
    var textColor: Color = .primary
    
    @State private var isPressed: Bool = false
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(baseColor)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 2, y: 2)
                    .shadow(color: Color.white.opacity(0.7), radius: 2, x: -2, y: -2)
            }
        )
        .scaleEffect(isPressed ? 0.97 : (isHovered ? 1.02 : 1.0))
        .animation(.spring(response: 0.2), value: isPressed)
        .animation(.spring(response: 0.2), value: isHovered)
        .onTapGesture {
            withAnimation {
                isPressed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        isPressed = false
                    }
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
#endif

#if os(iOS)
struct EpisodeCard: View {
    let episode: SerieDetail.Episode
    let downloadAction: () -> Void
    let playAction: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Subviews
    private var imageSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: episode.info.movieImage)) { phase in
                imageContent(for: phase)
            }
            
            episodeNumberBadge
            durationBadge
            gradientOverlay
        }
        .frame(height: 140)
        .cornerRadius(16)
    }
    
    private var episodeNumberBadge: some View {
        Text("Episodio \(episode.episodeNum)")
            .badgeStyle(backgroundColor: .red, foregroundColor: .white)
            .padding(12)
    }
    
    private var durationBadge: some View {
        HStack {
            Spacer()
            Text(episode.info.duration)
                .badgeStyle(backgroundColor: .black.opacity(0.6), foregroundColor: .white)
                .padding(12)
        }
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .clear,
                .black.opacity(0.3),
                .black.opacity(0.5)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: playAction) {
                buttonContent(
                    icon: "play.fill",
                    label: "Reproducir",
                    style: .primary
                )
            }
            
            Button(action: downloadAction) {
                buttonContent(
                    icon: "arrow.down",
                    label: "Descargar",
                    style: .secondary
                )
            }
        }
        .padding(.top, 5)
    }
    
    // MARK: - Main Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            
            VStack(alignment: .leading, spacing: 10) {
                Text(episode.title)
                    .font(.headline).bold()
                    .lineLimit(1)
                
                if !episode.info.plot.isEmpty {
                    Text(episode.info.plot)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                actionButtons
            }
            .padding(16)
        }
        .cardStyle(isHovered: isHovered, colorScheme: colorScheme)
        .hoverEffect(isHovered: $isHovered)
    }
}
#elseif os(macOS)
struct EpisodeCard: View {
    let episode: SerieDetail.Episode
    let downloadAction: () -> Void
    let playAction: () -> Void
    
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Subviews
    private var imageSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: episode.info.movieImage)) { phase in
                imageContent(for: phase)
            }
            
            episodeNumberBadge
            durationBadge
            gradientOverlay
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var episodeNumberBadge: some View {
        Text("Episodio \(episode.episodeNum)")
            .badgeStyle(backgroundColor: .red, foregroundColor: .white)
            .padding(12)
    }
    
    private var durationBadge: some View {
        HStack {
            Spacer()
            Text(episode.info.duration)
                .badgeStyle(backgroundColor: .black.opacity(0.6), foregroundColor: .white)
                .padding(12)
        }
    }
    
    private var gradientOverlay: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .clear,
                .black.opacity(0.3),
                .black.opacity(0.5)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: playAction) {
                buttonContent(
                    icon: "play.fill",
                    label: "Reproducir",
                    style: .primary
                )
            }
            
            Button(action: downloadAction) {
                buttonContent(
                    icon: "arrow.down",
                    label: "Descargar",
                    style: .secondary
                )
            }
        }
        .padding(.top, 5)
    }
    
    // MARK: - Main Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageSection
            
            VStack(alignment: .leading, spacing: 10) {
                Text(episode.title)
                    .font(.headline).bold()
                    .lineLimit(1)
                
                if !episode.info.plot.isEmpty {
                    Text(episode.info.plot)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                actionButtons
            }
            .padding(16)
        }
        .cardStyle(isHovered: isHovered, colorScheme: colorScheme)
        .hoverEffect(isHovered: $isHovered)
    }
}
#endif

#if os(iOS)
// BadgeBackgroundView mejorado con efectos 3D más pronunciados
struct BadgeBackgroundView: View {
    let imageURL: String?
    let depth: Double // Parámetro para controlar la profundidad del efecto 3D
    
    var body: some View {
        ZStack {
            // Capa de sombra profunda para efecto 3D
            Capsule()
                .fill(Color.black.opacity(0.6))
                .blur(radius: 6)
                .offset(y: 4 * depth)
                .scaleEffect(0.97)
            
            // Imagen de fondo
            AsyncImage(url: URL(string: imageURL ?? "")) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 40)
                        .clipShape(Capsule())
                        .blur(radius: 0.5)
                } else {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                }
            }
            
            // Overlay para mejor visibilidad del texto
            Capsule()
                .fill(Color.black.opacity(0.3))
            
            // Efecto de borde elevado
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // Efecto de brillo superior (highlight)
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .scaleEffect(x: 0.95, y: 0.6)
                .offset(y: -8 * depth)
            
            // Efecto de reflejo lateral
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .scaleEffect(x: 0.1, y: 0.8)
                .offset(x: -15)
        }
        .padding(.horizontal, -8)
        // Sombra exterior para efecto de elevación
        .shadow(color: .black.opacity(0.6), radius: 8 * depth, x: 0, y: 4 * depth)
        // Sombra interior sutil
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.3), lineWidth: 2)
                .blur(radius: 2)
                .offset(x: 0, y: 1)
                .mask(Capsule().fill(LinearGradient(
                    gradient: Gradient(colors: [.black, .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )))
        )
    }
}
#elseif os(macOS)
struct BadgeBackgroundView: View {
    let imageURL: String?
    let depth: Double // Parámetro para controlar la profundidad del efecto 3D
    
    var body: some View {
        ZStack {
            // Capa de sombra profunda para efecto 3D
            Capsule()
                .fill(Color.black.opacity(0.6))
                .blur(radius: 6)
                .offset(y: 4 * depth)
                .scaleEffect(0.97)
            
            // Imagen de fondo
            AsyncImage(url: URL(string: imageURL ?? "")) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 40)
                        .clipShape(Capsule())
                        .blur(radius: 0.5)
                } else {
                    Capsule()
                        .fill(Color.black.opacity(0.4))
                }
            }
            
            // Overlay para mejor visibilidad del texto
            Capsule()
                .fill(Color.black.opacity(0.3))
            
            // Efecto de borde elevado
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // Efecto de brillo superior (highlight)
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.05)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
                .scaleEffect(x: 0.95, y: 0.6)
                .offset(y: -8 * depth)
            
            // Efecto de reflejo lateral
            Capsule()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.2),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .scaleEffect(x: 0.1, y: 0.8)
                .offset(x: -15)
        }
        .padding(.horizontal, -8)
        // Sombra exterior para efecto de elevación
        .shadow(color: .black.opacity(0.6), radius: 8 * depth, x: 0, y: 4 * depth)
        // Sombra interior sutil
        .overlay(
            Capsule()
                .stroke(Color.black.opacity(0.3), lineWidth: 2)
                .blur(radius: 2)
                .offset(x: 0, y: 1)
                .mask(Capsule().fill(LinearGradient(
                    gradient: Gradient(colors: [.black, .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )))
        )
    }
}
#endif

// MARK: - Extensions
// MARK: - Color Extensions
extension Color {
    // Colores de fondo principales
    static var systemBackground: Self {
        #if os(iOS)
        return Color(UIColor.systemBackground)
        #elseif os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    static var secondarySystemBackground: Self {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #elseif os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var tertiarySystemBackground: Self {
        #if os(iOS)
        return Color(UIColor.tertiarySystemBackground)
        #elseif os(macOS)
        return Color(NSColor.textBackgroundColor)
        #endif
    }
    
    // Colores de capa grupales
    static var systemGroupedBackground: Self {
        #if os(iOS)
        return Color(UIColor.systemGroupedBackground)
        #elseif os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #endif
    }
    
    static var secondarySystemGroupedBackground: Self {
        #if os(iOS)
        return Color(UIColor.secondarySystemGroupedBackground)
        #elseif os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    // Colores de contenido
    static var cardBackground: Self {
        #if os(iOS)
        return Color(UIColor.systemGray6)
        #elseif os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
    static var searchBarBackground: Self {
        #if os(iOS)
        return Color(UIColor.systemGray6)
        #elseif os(macOS)
        return Color.gray.opacity(0.2)
        #endif
    }
    
    // Colores de gris del sistema
    static var systemGray: Self {
        #if os(iOS)
        return Color(UIColor.systemGray)
        #elseif os(macOS)
        return Color(NSColor.systemGray)
        #endif
    }
    
    static var systemGray2: Self {
        #if os(iOS)
        return Color(UIColor.systemGray2)
        #elseif os(macOS)
        return Color(NSColor.secondaryLabelColor)
        #endif
    }
    
    static var systemGray3: Self {
        #if os(iOS)
        return Color(UIColor.systemGray3)
        #elseif os(macOS)
        return Color(NSColor.tertiaryLabelColor)
        #endif
    }
    
    static var systemGray4: Self {
        #if os(iOS)
        return Color(UIColor.systemGray4)
        #elseif os(macOS)
        return Color(NSColor.quaternaryLabelColor)
        #endif
    }
    
    static var systemGray5: Self {
        #if os(iOS)
        return Color(UIColor.systemGray5)
        #elseif os(macOS)
        return Color(NSColor.lightGray).opacity(0.5)
        #endif
    }
    
    static var systemGray6: Self {
        #if os(iOS)
        return Color(UIColor.systemGray6)
        #elseif os(macOS)
        return Color(NSColor.lightGray).opacity(0.3)
        #endif
    }
    
    // Colores de etiquetas
    static var label: Self {
        #if os(iOS)
        return Color(UIColor.label)
        #elseif os(macOS)
        return Color(NSColor.labelColor)
        #endif
    }
    
    static var secondaryLabel: Self {
        #if os(iOS)
        return Color(UIColor.secondaryLabel)
        #elseif os(macOS)
        return Color(NSColor.secondaryLabelColor)
        #endif
    }
    
    static var tertiaryLabel: Self {
        #if os(iOS)
        return Color(UIColor.tertiaryLabel)
        #elseif os(macOS)
        return Color(NSColor.tertiaryLabelColor)
        #endif
    }
    
    static var quaternaryLabel: Self {
        #if os(iOS)
        return Color(UIColor.quaternaryLabel)
        #elseif os(macOS)
        return Color(NSColor.quaternaryLabelColor)
        #endif
    }
    
    // Colores de separadores
    static var separator: Self {
        #if os(iOS)
        return Color(UIColor.separator)
        #elseif os(macOS)
        return Color(NSColor.separatorColor)
        #endif
    }
    
    static var opaqueSeparator: Self {
        #if os(iOS)
        return Color(UIColor.opaqueSeparator)
        #elseif os(macOS)
        return Color(NSColor.separatorColor).opacity(1.0)
        #endif
    }
}

extension View {
    func scrollDisablesDrag(_ disables: Bool) -> some View {
        self.simultaneousGesture(DragGesture(minimumDistance: disables ? 10 : 0)
            .onChanged { _ in })
    }
}

// Alternatively, create a helper extension for better scroll handling
extension ScrollView {
    func improvedScrolling() -> some View {
        self.simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in })
            .highPriorityGesture(DragGesture(minimumDistance: 0).onEnded { _ in })
    }
}

// Add this extension for horizontal centering
extension View {
    func hCenter() -> some View {
        HStack {
            Spacer()
            self
            Spacer()
        }
    }
}

// MARK: - RoundedCorner Shape
#if os(iOS)
// Extension to create rounded corners for specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
#elseif os(macOS)
// Implementación macOS para cornerRadius con esquinas específicas
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerMac(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomRight = RectCorner(rawValue: 1 << 2)
    static let bottomLeft = RectCorner(rawValue: 1 << 3)
    
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCornerMac: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let topLeft = corners.contains(.topLeft)
        let topRight = corners.contains(.topRight)
        let bottomLeft = corners.contains(.bottomLeft)
        let bottomRight = corners.contains(.bottomRight)
        
        let width = rect.width
        let height = rect.height

        // Comenzar en la esquina superior izquierda
        path.move(to: CGPoint(x: topLeft ? radius : 0, y: 0))
        
        // Esquina superior derecha
        path.addLine(to: CGPoint(x: width - (topRight ? radius : 0), y: 0))
        if topRight {
            path.addArc(center: CGPoint(x: width - radius, y: radius),
                        radius: radius,
                        startAngle: Angle(degrees: -90),
                        endAngle: Angle(degrees: 0),
                        clockwise: false)
        }
        
        // Esquina inferior derecha
        path.addLine(to: CGPoint(x: width, y: height - (bottomRight ? radius : 0)))
        if bottomRight {
            path.addArc(center: CGPoint(x: width - radius, y: height - radius),
                        radius: radius,
                        startAngle: Angle(degrees: 0),
                        endAngle: Angle(degrees: 90),
                        clockwise: false)
        }
        
        // Esquina inferior izquierda
        path.addLine(to: CGPoint(x: bottomLeft ? radius : 0, y: height))
        if bottomLeft {
            path.addArc(center: CGPoint(x: radius, y: height - radius),
                        radius: radius,
                        startAngle: Angle(degrees: 90),
                        endAngle: Angle(degrees: 180),
                        clockwise: false)
        }
        
        // De vuelta a la esquina superior izquierda
        path.addLine(to: CGPoint(x: 0, y: topLeft ? radius : 0))
        if topLeft {
            path.addArc(center: CGPoint(x: radius, y: radius),
                        radius: radius,
                        startAngle: Angle(degrees: 180),
                        endAngle: Angle(degrees: 270),
                        clockwise: false)
        }
        
        path.closeSubpath()
        return path
    }
}
#endif

// MARK: - Scroll Offset Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // For our use case, we want to use the latest value
        value = nextValue()
    }
}

#if os(iOS)
// CollapsedTitleBadgeView mejorado con efectos 3D avanzados
struct CollapsedTitleBadgeView: View {
    let title: String
    let imageURL: String?
    let opacity: Double
    
    // Calcular la profundidad basada en la opacidad
    private var depth: Double {
        return opacity
    }
    
    // Calcular el ángulo de rotación basado en la opacidad
    private var rotationAngle: Double {
        return (1.0 - opacity) * 15.0
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Icono
            Image(systemName: "play.tv.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
            
            // Texto del título
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .shadow(color: Color.black.opacity(0.7), radius: 3, x: 0, y: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            BadgeBackgroundView(imageURL: imageURL, depth: depth)
        )
        .opacity(opacity)
        // Efectos 3D avanzados
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 1.0, y: 0.2, z: 0.0),
            anchor: .center,
            perspective: 0.3
        )
        // Efecto de escala para simular acercamiento/alejamiento
        .scaleEffect(0.9 + (0.1 * depth))
        // Efecto de elevación
        .offset(y: (1.0 - depth) * -5)
        // Transición suave
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: depth)
    }
}
#elseif os(macOS)
struct CollapsedTitleBadgeView: View {
    let title: String
    let imageURL: String?
    let opacity: Double
    
    // Calcular la profundidad basada en la opacidad
    private var depth: Double {
        return opacity
    }
    
    // Calcular el ángulo de rotación basado en la opacidad
    private var rotationAngle: Double {
        return (1.0 - opacity) * 15.0
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Icono
            Image(systemName: "play.tv.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
            
            // Texto del título
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .shadow(color: Color.black.opacity(0.7), radius: 3, x: 0, y: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            BadgeBackgroundView(imageURL: imageURL, depth: depth)
        )
        .opacity(opacity)
        // Efectos 3D avanzados
        .rotation3DEffect(
            .degrees(rotationAngle),
            axis: (x: 1.0, y: 0.2, z: 0.0),
            anchor: .center,
            perspective: 0.3
        )
        // Efecto de escala para simular acercamiento/alejamiento
        .scaleEffect(0.9 + (0.1 * depth))
        // Efecto de elevación
        .offset(y: (1.0 - depth) * -5)
        // Transición suave
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: depth)
    }
}
#endif
enum ButtonStyleType {
    case primary, secondary
}
func buttonContent(icon: String, label: String, style: ButtonStyleType) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 12))
        Text(label).font(.system(size: 13, weight: .semibold))
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity)
    .background(buttonBackground(for: style))
    .foregroundColor(style == .primary ? .white : .white.opacity(0.8))
}

func buttonBackground(for style: ButtonStyleType) -> some View {
    Group {
        if style == .primary {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red)
                .shadow(color: Color.red.opacity(0.3), radius: 3, x: 0, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
        }
    }
}
// MARK: - Helper Components for EpisodeCard
#if os(iOS)
private extension EpisodeCard {
    enum ButtonStyleType {
        case primary, secondary
    }
    
    @ViewBuilder
    func imageContent(for phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
        case .failure:
            Color(.systemGray5)
                .overlay(Image(systemName: "photo").font(.largeTitle))
        case .empty:
            ProgressView()
                .frame(width: 32, height: 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        @unknown default:
            EmptyView()
        }
    }
    

}
#elseif os(macOS)
private extension EpisodeCard {
    enum ButtonStyleType {
        case primary, secondary
    }
    
    @ViewBuilder
    func imageContent(for phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image):
            image
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
        case .failure:
            Color.gray.opacity(0.2) // Equivalente de systemGray5 en macOS
                .overlay(Image(systemName: "photo").font(.largeTitle))
        case .empty:
            ProgressView()
                .frame(width: 32, height: 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        @unknown default:
            EmptyView()
        }
    }
    
    func buttonContent(icon: String, label: String, style: ButtonStyleType) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12))
            Text(label).font(.system(size: 13, weight: .semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(buttonBackground(for: style))
        .foregroundColor(style == .primary ? .white : .red)
    }
    
    func buttonBackground(for style: ButtonStyleType) -> some View {
        Group {
            if style == .primary {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red)
                    .shadow(color: Color.red.opacity(0.3), radius: 3, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }
}
#endif

// MARK: - View Modifiers
extension View {
    func badgeStyle(backgroundColor: Color, foregroundColor: Color) -> some View {
        self
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
            )
            .foregroundColor(foregroundColor)
    }
    
    func cardStyle(isHovered: Bool, colorScheme: ColorScheme) -> some View {
        self
            .background(colorScheme == .dark ? Color.cardBackground : .white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 10, x: 0, y: 5)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
    }
    
    func hoverEffect(isHovered: Binding<Bool>) -> some View {
        self
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered.wrappedValue)
            #if os(iOS)
            .onTapGesture {
                withAnimation {
                    isHovered.wrappedValue = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            isHovered.wrappedValue = false
                        }
                    }
                }
            }
            #elseif os(macOS)
            .onHover { hovering in
                isHovered.wrappedValue = hovering
            }
            .onTapGesture {
                withAnimation {
                    isHovered.wrappedValue = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            isHovered.wrappedValue = false
                        }
                    }
                }
            }
            #endif
    }
}

#if os(iOS)
// MARK: - Search Bar Component
struct SearchBar: View {
    @Binding var text: String
    @State private var isEditing = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                
                TextField("Buscar episodios...", text: $text)
                    .padding(10)
                    .background(Color.clear)
                    .cornerRadius(8)
                    .padding(.horizontal, 5)
                    .onTapGesture {
                        isEditing = true
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .padding(.trailing, 8)
                    }
                }
            }
            .background(colorScheme == .dark ? Color.cardBackground : Color.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            if isEditing {
                Button(action: {
                    isEditing = false
                    text = ""
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }) {
                    Text("Cancelar")
                        .foregroundColor(.red)
                }
                .padding(.trailing, 10)
                .transition(.move(edge: .trailing))
                .animation(.default, value: isEditing)
            }
        }
    }
}
#elseif os(macOS)
// MARK: - Search Bar Component para macOS
struct SearchBar: View {
    @Binding var text: String
    @State private var isEditing = false
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                
                TextField("Buscar episodios...", text: $text)
                    .padding(10)
                    .background(Color.clear)
                    .cornerRadius(8)
                    .padding(.horizontal, 5)
                    .focused($isFocused)
                    .onTapGesture {
                        isEditing = true
                        isFocused = true
                    }
                
                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.systemGray6)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            if isEditing {
                Button(action: {
                    isEditing = false
                    text = ""
                    isFocused = false
                }) {
                    Text("Cancelar")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .transition(.move(edge: .trailing))
                .animation(.default, value: isEditing)
            }
        }
    }
}
#endif

#if os(iOS)
// MARK: - Neumorphic Button Style
struct NeumorphicButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 15)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color)
                        .shadow(color: colorScheme == .dark ?
                                Color.black.opacity(0.3) : Color.black.opacity(0.2),
                                radius: configuration.isPressed ? 2 : 5,
                                x: 0,
                                y: configuration.isPressed ? 1 : 3)
                    
                    // Subtle inner glow
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3),
                                    Color.white.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                        .padding(1)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .foregroundColor(color == .red ? .white : .primary)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
#elseif os(macOS)
// MARK: - Neumorphic Button Style para macOS
struct NeumorphicButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 15)
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color)
                        .shadow(color: colorScheme == .dark ?
                                Color.black.opacity(0.3) : Color.black.opacity(0.2),
                                radius: configuration.isPressed ? 2 : 5,
                                x: 0,
                                y: configuration.isPressed ? 1 : 3)
                    
                    // Subtle inner glow
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3),
                                    Color.white.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.overlay)
                        .padding(1)
                }
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .foregroundColor(color == .red ? .white : .primary)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
#endif

#if os(iOS)
// MARK: - Visual Effect Blur
struct VisualEffectBlur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemMaterial
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}
#elseif os(macOS)
// MARK: - Visual Effect Blur para macOS
struct VisualEffectBlur: View {
    var material: NSVisualEffectView.Material = .headerView
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    var body: some View {
        VisualEffectViewRepresentable(material: material, blendingMode: blendingMode)
    }
}

struct VisualEffectViewRepresentable: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
#endif

#if os(iOS)
// MARK: - Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var selectedFolder: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Use .folder content type to select folders
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Start accessing the security-scoped resource
            let securityScopedURL = url.startAccessingSecurityScopedResource()
            
            // Store the security-scoped URL
            parent.selectedFolder = url
            
            // Create bookmark for persistent access
            do {
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark,
                                                      includingResourceValuesForKeys: nil,
                                                      relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: "selectedFolderBookmark")
            } catch {
                print("Failed to create bookmark: \(error.localizedDescription)")
            }
            
            // Release the security-scoped resource when done
            if securityScopedURL {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("Document picker was cancelled")
        }
    }
}
#elseif os(macOS)
// MARK: - Document Picker para macOS
struct DocumentPicker: NSViewControllerRepresentable {
    @Binding var selectedFolder: URL
    
    func makeNSViewController(context: Context) -> NSViewController {
        let controller = NSViewController()
        return controller
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // No es necesario hacer nada aquí, ya que activamos el panel de forma manual
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSOpenSavePanelDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func openFolderPicker() {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.delegate = self
            
            if panel.runModal() == .OK {
                if let url = panel.url {
                    // Intentar acceder al recurso con scope de seguridad
                    let securityScopedAccess = url.startAccessingSecurityScopedResource()
                    
                    // Guardar la URL seleccionada
                    parent.selectedFolder = url
                    
                    // Crear bookmark para acceso persistente
                    do {
                        let bookmarkData = try url.bookmarkData(options: .minimalBookmark,
                                                              includingResourceValuesForKeys: nil,
                                                              relativeTo: nil)
                        UserDefaults.standard.set(bookmarkData, forKey: "selectedFolderBookmark")
                    } catch {
                        print("Error al crear bookmark: \(error.localizedDescription)")
                    }
                    
                    // Liberar el recurso cuando se termina
                    if securityScopedAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
            }
        }
    }
    
    // Función de ayuda para activar el selector de carpetas
    func selectFolder() {
        DispatchQueue.main.async {
            self.makeCoordinator().openFolderPicker()
        }
    }
}
#endif

#if os(iOS)
/// A reusable loading placeholder view that displays a progress indicator on a semi-transparent background
/// Use this component whenever content is being loaded asynchronously
struct LoadingPlaceholderView: View {
    /// Optional background opacity, defaults to 0.3
    var opacity: Double = 0.3
    
    var body: some View {
        ZStack {
            Color.gray.opacity(opacity)
            ProgressView()
                .frame(width: 32, height: 32)
        }
    }
}
#elseif os(macOS)
/// A reusable loading placeholder view that displays a progress indicator on a semi-transparent background
/// Use this component whenever content is being loaded asynchronously
struct LoadingPlaceholderView: View {
    /// Optional background opacity, defaults to 0.3
    var opacity: Double = 0.3
    
    var body: some View {
        ZStack {
            Color.gray.opacity(opacity)
            ProgressView()
                .frame(width: 32, height: 32)
        }
    }
}
#endif
