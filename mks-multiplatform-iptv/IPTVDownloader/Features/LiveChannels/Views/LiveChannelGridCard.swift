import SwiftUI

/// Optimized compact card for Live TV grid display - designed for mass viewing of 571+ channels
struct LiveChannelGridCard: View {
    let channel: LiveChannel
    @EnvironmentObject var profile: IPTVProfile
    @State private var isHovered = false
    
    // Optimized dimensions for grid
    #if os(iOS)
    private let cardHeight: CGFloat = 120
    private let iconSize: CGFloat = 32
    private let titleFont: Font = .system(size: 12, weight: .semibold)
    private let badgeFont: Font = .system(size: 9, weight: .bold)
    #else
    private let cardHeight: CGFloat = 140
    private let iconSize: CGFloat = 36
    private let titleFont: Font = .system(size: 13, weight: .semibold)
    private let badgeFont: Font = .system(size: 10, weight: .bold)
    #endif
    
    private var categoryBadgeColor: Color {
        let colors: [String: Color] = [
            "145": .orange,   // Anuncios
            "147": .blue,     // Deportes  
            "148": .green,    // Noticias
            "149": .purple,   // Entretenimiento
            "150": .cyan,     // Internacional
            "151": .pink,     // Música
            "152": .yellow,   // Infantil
            "153": .brown,    // Documentales
            "154": .red       // Películas
        ]
        
        return colors[channel.categoryId ?? "0"] ?? .gray
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Icon and Play Overlay
            ZStack {
                // Channel Icon
                CachedAsyncImage(url: URL(string: channel.streamIcon ?? "")) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: iconSize + 16, height: iconSize + 8)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.7)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: iconSize + 16, height: iconSize + 8)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(categoryBadgeColor.opacity(0.3))
                            .frame(width: iconSize + 16, height: iconSize + 8)
                            .overlay(
                                Image(systemName: "tv")
                                    .font(.system(size: iconSize * 0.6))
                                    .foregroundColor(categoryBadgeColor)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                
                // VLC Button Only (no native play button)
                if isHovered {
                    // Compact VLC Button
                    OpenInVLCButton(urlProvider: {
                        return IPTVConfiguration.buildLiveChannelURL(profile: profile, channelID: channel.streamId)
                    }, label: "VLC")
                    .scaleEffect(0.7) // Make it compact for grid
                    .transition(.opacity)
                }
            }
            .frame(height: iconSize + 12)
            
            // Channel Info
            VStack(spacing: 3) {
                // Channel Name
                Text(channel.name)
                    .font(titleFont)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                
                // Category Badge
                Text("Cat \(channel.categoryId ?? "")")
                    .font(badgeFont)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(categoryBadgeColor))
            }
            
            Spacer()
        }
        .frame(height: cardHeight)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Previews
struct LiveChannelGridCard_Previews: PreviewProvider {
    static var previews: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 140, maximum: .infinity), spacing: 12, alignment: .top)
        ], spacing: 12) {
            ForEach(0..<12) { index in
                LiveChannelGridCard(
                    channel: LiveChannel(
                        num: index + 1,
                        name: "Channel \(index + 1)",
                        streamType: "live",
                        streamId: index + 1,
                        streamIcon: "https://example.com/icon.jpg",
                        epgChannelId: nil,
                        added: "1620000000",
                        isAdult: "0",
                        categoryId: ["145", "147", "148", "149"].randomElement() ?? "145",
                        customSid: nil,
                        tvArchive: 0,
                        directSource: nil,
                        tvArchiveDuration: 0
                    )
                )
            }
        }
        .environmentObject(IPTVProfile(name: "Test", baseURL: "http://test.com", username: "test", password: "test"))
        .padding()
        .previewLayout(.sizeThatFits)
    }
}