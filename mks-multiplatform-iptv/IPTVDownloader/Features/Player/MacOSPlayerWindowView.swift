#if os(macOS)
import SwiftUI
import AppKit
import IPTVCore

struct MacOSPlayerWindowView: View {
    private let manager = PlayerWindowManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var toolbarVisible: Bool = true
    @State private var isHoveringToolbar: Bool = false
    @State private var toolbarHideTask: Task<Void, Never>?

    private var hasContent: Bool {
        manager.activePlayer != nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // VStack: toolbar is a SIBLING of the player, not overlapping.
            // This avoids the macOS bug where SwiftUI views in a ZStack above
            // an NSViewRepresentable block ALL mouse events to the NSView.
            VStack(spacing: 0) {
                if hasContent {
                    glassToolbarOverlay
                }

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear {
            manager.dismiss()
            toolbarHideTask?.cancel()
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
            controlsConfiguration: .native
        )
    }

    @ViewBuilder
    private var glassToolbarOverlay: some View {
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
        .frame(maxWidth: .infinity)
        .allowsHitTesting(toolbarVisible || isHoveringToolbar)
        .opacity(toolbarVisible || isHoveringToolbar ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: toolbarVisible)
        .animation(.easeInOut(duration: 0.2), value: isHoveringToolbar)
    }

    @ViewBuilder
    private var windowControlsSpacer: some View {
        // Reserve space for window traffic light buttons.
        // Height must be explicit — Color.clear is greedy and would
        // expand the HStack to fill all available vertical space.
        Color.clear
            .frame(width: 70, height: 1)
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
#endif
