#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Minimal view shown when app launches in standalone player mode (Open With).
/// Auto-opens player window and closes the main window.
struct StandaloneLauncherView: View {
    let fileURL: URL
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text("Opening \(fileURL.deletingPathExtension().lastPathComponent)...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            launchPlayer()
        }
    }
    
    private func launchPlayer() {
        let title = fileURL.deletingPathExtension().lastPathComponent
        let player = PlayerFactory.shared.createPlayer(for: fileURL)
        
        PlayerWindowManager.shared.present(
            player: player,
            title: title,
            metadata: nil
        )
        
        player.load(url: fileURL)
        player.play()
        
        openWindow(id: "player")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            closeMainWindow()
        }
    }
    
    private func closeMainWindow() {
        for window in NSApplication.shared.windows {
            if let identifier = window.identifier?.rawValue,
               !identifier.contains("player") {
                window.close()
                break
            }
        }
    }
}
#endif
