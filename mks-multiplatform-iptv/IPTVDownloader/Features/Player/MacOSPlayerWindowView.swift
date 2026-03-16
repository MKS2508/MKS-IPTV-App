#if os(macOS)
import SwiftUI
import AppKit

struct MacOSPlayerWindowView: View {
    private let manager = PlayerWindowManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings: Bool = false
    @State private var controlsMode: PlayerControlsMode = .native
    @State private var toolbarVisible: Bool = true
    @State private var isHoveringToolbar: Bool = false
    @State private var toolbarHideTask: Task<Void, Never>?
    
    private var hasContent: Bool {
        manager.activePlayer != nil
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if let player = manager.activePlayer {
                    playerContent(player: player)
                } else {
                    Color.clear
                        .onAppear {
                            closePlayerWindow()
                        }
                }
            }
            
            if hasContent {
                glassToolbarOverlay
            }
        }
        .onDisappear {
            manager.dismiss()
            toolbarHideTask?.cancel()
        }
        .sheet(isPresented: $showSettings) {
            PlayerSettingsView(controlsMode: $controlsMode)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHoveringToolbar = true
                showToolbar()
            case .ended:
                isHoveringToolbar = false
                scheduleToolbarHide()
            }
        }
        .onAppear {
            scheduleToolbarHide()
        }
    }
    
    @ViewBuilder
    private func playerContent(player: any VideoPlayerProtocol) -> some View {
        MKSPlayerView(
            player: player,
            title: manager.title,
            metadata: manager.metadata,
            presentationMode: .fullscreen,
            controlsConfiguration: PlayerControlsConfiguration(mode: controlsMode)
        )
    }
    
    @ViewBuilder
    private var glassToolbarOverlay: some View {
        VStack {
            HStack(spacing: 16) {
                windowControlsSpacer

                if !manager.title.isEmpty {
                    Text(manager.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }

                Spacer()

                controlsModePicker
                settingsButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.7),
                        Color.black.opacity(0.4),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Spacer()
                .allowsHitTesting(false)
        }
        .allowsHitTesting(toolbarVisible || isHoveringToolbar)
        .opacity(toolbarVisible || isHoveringToolbar ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: toolbarVisible)
        .animation(.easeInOut(duration: 0.2), value: isHoveringToolbar)
    }
    
    @ViewBuilder
    private var windowControlsSpacer: some View {
        Color.clear
            .frame(width: 70)
    }
    
    @ViewBuilder
    private var controlsModePicker: some View {
        Picker("Controls", selection: $controlsMode) {
            ForEach(PlayerControlsMode.allCases, id: \.self) { mode in
                Label(mode.displayName, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .tint(.white)
    }
    
    @ViewBuilder
    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(8)
        }
        .background(.ultraThinMaterial.opacity(0.6), in: Circle())
        .buttonStyle(.plain)
        .help("Player Settings")
    }
    
    private func scheduleToolbarHide() {
        toolbarHideTask?.cancel()
        toolbarHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                toolbarVisible = false
            }
        }
    }
    
    private func showToolbar() {
        toolbarVisible = true
        scheduleToolbarHide()
    }
    
    private func closePlayerWindow() {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                if window.identifier?.rawValue.contains("player") == true
                    || window.title == "Now Playing" {
                    window.close()
                    return
                }
            }
            dismiss()
        }
    }
}

struct PlayerSettingsView: View {
    @Binding var controlsMode: PlayerControlsMode
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("PlayerAutoHideControls") private var autoHideControls: Bool = true
    @AppStorage("PlayerAutoHideDelay") private var autoHideDelay: Double = 4.0
    @AppStorage("PlayerHapticFeedback") private var hapticFeedback: Bool = true
    @AppStorage("PlayerShowSeekBar") private var showSeekBar: Bool = true
    @AppStorage("PlayerShowVolumeControl") private var showVolumeControl: Bool = true
    @AppStorage("PlayerShowSpeedControl") private var showSpeedControl: Bool = true
    
    var body: some View {
        VStack(spacing: 24) {
            header
            
            Form {
                Section("Controls Style") {
                    Picker("Mode", selection: $controlsMode) {
                        ForEach(PlayerControlsMode.allCases, id: \.self) { mode in
                            Label(mode.displayName, systemImage: mode.icon)
                                .tag(mode)
                        }
                    }
                }
                
                Section("Display Options") {
                    Toggle("Show Seek Bar", isOn: $showSeekBar)
                    Toggle("Show Volume Control", isOn: $showVolumeControl)
                    Toggle("Show Speed Control", isOn: $showSpeedControl)
                }
                
                Section("Behavior") {
                    Toggle("Auto-hide Controls", isOn: $autoHideControls)
                    
                    if autoHideControls {
                        HStack {
                            Text("Hide Delay")
                            Slider(value: $autoHideDelay, in: 2...10, step: 1)
                            Text("\(Int(autoHideDelay))s")
                                .monospacedDigit()
                                .frame(width: 30)
                        }
                    }
                    
                    Toggle("Haptic Feedback", isOn: $hapticFeedback)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 480)
    }
    
    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.accent)
            
            Text("Player Settings")
                .font(.title2.weight(.semibold))
            
            Text("Customize your playback experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
}

#Preview {
    PlayerSettingsView(controlsMode: .constant(.native))
}
#endif
