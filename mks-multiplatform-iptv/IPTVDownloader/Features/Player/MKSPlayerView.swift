import SwiftUI
import AVKit

// MARK: - MKSPlayerView

/// Unified player component used across the entire app.
///
/// Uses the player protocol's `playerView()` for all rendering — reactive for FFmpeg
/// (spinner → VideoPlayer transition via @ObservedObject), native for AVPlayer/KSPlayer/VLC.
/// On iOS 26+, `VideoPlayer(player:)` automatically uses Liquid Glass transport controls.
///
/// ## Usage
/// ```swift
/// MKSPlayerView(
///     player: player,
///     title: "Movie Title",
///     metadata: enrichedMetadata,
///     onDismiss: { player.stop() }
/// )
/// ```
struct MKSPlayerView: View {
    let player: any VideoPlayerProtocol
    var title: String = ""
    var metadata: MetadataResult? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var showMetadata = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Video surface — playerView() handles all state transitions reactively
            player.playerView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            // Metadata overlay (Liquid Glass on iOS 26+)
            if let metadata, showMetadata {
                VStack {
                    Spacer()
                    metadataOverlay(metadata)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Dismiss button (Liquid Glass on iOS 26+)
            if let onDismiss {
                dismissButton(action: onDismiss)
            }

            // Title bar (when no metadata but title provided)
            if metadata == nil, !title.isEmpty {
                VStack {
                    titleBar
                    Spacer()
                }
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .onTapGesture {
            if metadata != nil {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showMetadata.toggle()
                }
            }
        }
    }

    // MARK: - Title Bar

    @ViewBuilder
    private var titleBar: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let onDismiss {
                Button("Close", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Metadata Overlay

    @ViewBuilder
    private func metadataOverlay(_ metadata: MetadataResult) -> some View {
        MetadataOverlayView(metadata: metadata)
            .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius))
            .padding()
    }

    // MARK: - Dismiss Button

    @ViewBuilder
    private func dismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .adaptiveGlass(in: Circle())
        .padding()
    }
}
