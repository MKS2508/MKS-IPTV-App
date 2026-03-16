import SwiftUI
import AVFoundation

struct GlassVolumeControl: View {
    @Binding var volume: Float
    var isMuted: Bool = false
    var onMuteToggle: (() -> Void)?
    
    @State private var isDragging = false
    @GestureState private var dragOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 8) {
            muteButton
            volumeSlider
        }
    }
    
    @ViewBuilder
    private var muteButton: some View {
        Button {
            onMuteToggle?()
            triggerHaptic()
        } label: {
            Image(systemName: volumeIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(isMuted ? 0.5 : 1))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var volumeSlider: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                trackView(width: geometry.size.width)
                progressView(width: geometry.size.width)
                thumbView(width: geometry.size.width)
            }
            .frame(height: 4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        volume = Float(fraction)
                    }
                    .onEnded { _ in
                        isDragging = false
                        triggerHaptic()
                    }
            )
            .onTapGesture { location in
                let fraction = max(0, min(1, location.x / geometry.size.width))
                volume = Float(fraction)
                triggerHaptic()
            }
        }
        .frame(width: 80, height: 24)
    }
    
    @ViewBuilder
    private func trackView(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.2))
            .frame(width: width, height: 4)
    }
    
    @ViewBuilder
    private func progressView(width: CGFloat) -> some View {
        Capsule()
            .fill(AppColors.accent)
            .frame(width: width * CGFloat(volume), height: 4)
    }
    
    @ViewBuilder
    private func thumbView(width: CGFloat) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 6, height: 6)
            )
            .offset(x: width * CGFloat(volume) - 5)
            .scaleEffect(isDragging ? 1.3 : 1.0)
            .animation(.spring(response: 0.15), value: isDragging)
    }
    
    private var volumeIcon: String {
        if isMuted || volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        if UserDefaults.standard.bool(forKey: "PlayerHapticFeedback") {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        #endif
    }
}

struct GlassSpeedControl: View {
    @Binding var speed: Float
    var options: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    var onSpeedChange: ((Float) -> Void)?
    
    @State private var showPicker: Bool = false
    
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    speed = option
                    onSpeedChange?(option)
                    triggerHaptic()
                } label: {
                    HStack {
                        Text(formatSpeed(option))
                        if speed == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            speedLabel
        }
        .menuStyle(.borderlessButton)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
    }
    
    @ViewBuilder
    private var speedLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "speedometer")
                .font(.system(size: 12, weight: .medium))
            Text(formatSpeed(speed))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(speed == 1.0 ? .white.opacity(0.7) : AppColors.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .adaptiveGlassInteractive(in: Capsule(), fallbackOpacity: 0.6)
    }
    
    private func formatSpeed(_ value: Float) -> String {
        if value == 1.0 { return "1x" }
        if value < 1.0 { return String(format: "%.2gx", value) }
        return String(format: "%.1gx", value)
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        if UserDefaults.standard.bool(forKey: "PlayerHapticFeedback") {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        #endif
    }
}

struct GlassVideoGravityControl: View {
    @Binding var gravity: PlayerVideoGravity
    var onGravityChange: ((PlayerVideoGravity) -> Void)?
    
    var body: some View {
        Menu {
            ForEach(PlayerVideoGravity.allCases, id: \.self) { option in
                Button {
                    gravity = option
                    onGravityChange?(option)
                    triggerHaptic()
                } label: {
                    HStack {
                        Label(option.displayName, systemImage: option.icon)
                        if gravity == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: gravity.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 32, height: 32)
                .adaptiveGlassInteractive(in: Circle(), fallbackOpacity: 0.5)
        }
        .menuStyle(.borderlessButton)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
    }
    
    private func triggerHaptic() {
        #if os(iOS)
        if UserDefaults.standard.bool(forKey: "PlayerHapticFeedback") {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        #endif
    }
}

#Preview("Volume Control") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        GlassVolumeControl(volume: .constant(0.65), isMuted: false)
            .padding()
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: 12))
            .padding()
    }
}

#Preview("Speed Control") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack(spacing: 20) {
            GlassSpeedControl(speed: .constant(1.0))
            GlassSpeedControl(speed: .constant(1.5))
            GlassSpeedControl(speed: .constant(2.0))
        }
        .padding()
    }
}
