import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct LiveChannelCardView: View {
    let liveChannel: LiveChannel
    @State private var isHovered = false
    @State private var showInlinePlayer = false
    @State private var player: AVPlayer?
    
    @EnvironmentObject var profile: IPTVProfile

    private let streamManager = StreamManager()
    var namespace: Namespace.ID

    private var iconView: some View {
        CachedAsyncImage(url: URL(string: liveChannel.streamIcon ?? "")) { phase in
            switch phase {
            case .empty:
                SkeletonLoader()
                    .frame(width: 50, height: 50)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .failure:
                Image(systemName: "tv")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundColor(.gray)
            @unknown default:
                EmptyView()
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Channel Header
            HStack(alignment: .center, spacing: 12) {
                iconView
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.gray.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(liveChannel.name)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                        .matchedGeometryEffect(id: "\(liveChannel.id)-name", in: namespace)

                    HStack(spacing: 6) {
                        // Only show LIVE badge - HD is redundant for most streams
                        Text("LIVE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    // Primary play button
                    Button(action: togglePlayback) {
                        Image(systemName: showInlinePlayer ? "stop.fill" : "play.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(showInlinePlayer ? .red : .accentColor)
                    }
                    .buttonStyle(BorderlessButtonStyle())

                    // Copy URL button
                    Button(action: copyChannelURL) {
                        Image(systemName: "link")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Copiar URL del canal")

                    // VLC button (more compact)
                    OpenInVLCButton(urlProvider: {
                        return IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: liveChannel.streamId)
                    }, label: "VLC")
                    .buttonStyle(BorderlessButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.windowBackground)
                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            )

            // Player
            if showInlinePlayer {
                VStack {
                    if let player = player {
                        VideoPlayer(player: player)
                            .frame(height: 300)
                            .cornerRadius(8)
                            .padding()
                    } else {
                        VStack {
                            ProgressView()
                                .padding(.bottom, 8)
                            Text("Configurando reproductor...")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }

                    Button(action: closePlayer) {
                        Text("Cerrar Stream")
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .transition(.slide)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .cornerRadius(24)
        .shadow(color: Color.accentColor.opacity(0.3), radius: 12, x: 0, y: 6)
        .onDisappear(perform: cleanUpPlayer)
    }

    // MARK: - Main Functions
    private func togglePlayback() {
        LiveLogger.debug("Toggle Playback: \(showInlinePlayer ? "Stopping" : "Starting") stream")
        showInlinePlayer ? closePlayer() : initializeStreamPlayback()
    }

    private func toggleFavorite() {
        LiveLogger.debug("Favorite toggled for \(liveChannel.name)")
    }

    private func cleanUpPlayer() {
        streamManager.cleanUpPlayer()
        showInlinePlayer = false
    }

    private func initializeStreamPlayback() {
        LiveLogger.debug("Initializing stream for channel: \(liveChannel.name)")

        guard let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: liveChannel.streamId)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let originalUrl = URL(string: urlString) else {
            LiveLogger.error("Failed to generate valid stream URL")
            return
        }

        LiveLogger.debug("Initial Stream URL: \(originalUrl.absoluteString)")

        streamManager.resolveStreamURL(from: originalUrl) { resolvedUrl in
            guard let resolvedUrl = resolvedUrl else {
                LiveLogger.error("Failed to resolve stream URL")
                return
            }

            streamManager.setupStreamPlayer(with: resolvedUrl) { player in
                DispatchQueue.main.async {
                    if let player = player {
                        self.player = player
                        self.showInlinePlayer = true
                        player.play()
                    } else {
                        LiveLogger.error("Failed to set up player")
                        self.closePlayer()
                    }
                }
            }
        }
    }

    private func closePlayer() {
        LiveLogger.debug("Stopping stream playback")
        streamManager.cleanUpPlayer()
        player = nil
        showInlinePlayer = false
    }
    
    private func copyChannelURL() {
        let urlString = IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: liveChannel.streamId)
        
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
        #else
        UIPasteboard.general.string = urlString
        #endif
        
        LiveLogger.debug("URL del canal copiada al portapapeles: \(urlString)")
    }
}

// MARK: - Previews
struct LiveChannelCardView_Previews: PreviewProvider {
    @Namespace static var previewNamespace

    static var previews: some View {
        LiveChannelCardView(
            liveChannel: LiveChannel(
                num: 1,
                name: "Test Channel",
                streamType: "live",
                streamId: 1,
                streamIcon: "https://example.com/icon.jpg",
                epgChannelId: nil,
                added: "1620000000",
                isAdult: "0",
                categoryId: "1",
                customSid: nil,
                tvArchive: 0,
                directSource: nil,
                tvArchiveDuration: 0
            ),
            namespace: previewNamespace
        )
        .environmentObject(IPTVProfile(name: "Test", baseURL: "http://test.com", username: "test", password: "test"))
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
