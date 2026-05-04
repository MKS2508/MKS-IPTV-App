//
//  ChannelDetailView.swift
//  mks-multiplataforma-tvos-iptv
//
//  Channel detail with mock EPG schedule (past / now / upcoming).
//

import SwiftUI
import IPTVCore

struct ChannelDetailView: View {
    let channel: LiveChannel

    @EnvironmentObject private var profileStore: ProfileStore
    @State private var schedule: [MockProgramme] = []
    @State private var playingItem: PlayableItem?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if !schedule.isEmpty {
                    scheduleSection
                }
                Spacer(minLength: 80)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .onAppear {
            schedule = MockEPG.schedule(for: channel)
        }
        .fullScreenCover(item: $playingItem) { item in
            TVPlayerView(item: item) { playingItem = nil }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            backdropImage
                .frame(height: 600)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 600)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Circle().fill(.red).frame(width: 14, height: 14)
                    Text("LIVE")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                        .tracking(2)
                }

                Text(channel.name)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let current = MockEPG.currentProgramme(for: channel) {
                    Text(current.title)
                        .font(.title.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))

                    HStack(spacing: 14) {
                        Text(timeRange(current))
                        ProgressView(value: current.progress)
                            .progressViewStyle(.linear)
                            .tint(.red)
                            .frame(width: 320, height: 6)
                        Text("\(Int(current.progress * 100))%")
                    }
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                }

                Button(action: playLive) {
                    HStack(spacing: 12) {
                        Image(systemName: "play.fill")
                        Text("Watch Live")
                    }
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 12)
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 60)
        }
        .frame(height: 600)
    }

    @ViewBuilder
    private var backdropImage: some View {
        if let urlString = channel.streamIcon, let url = URL(string: urlString) {
            CachedHTTPImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30)
                        .opacity(0.5)
                case .failure, .empty:
                    backdropPlaceholder
                @unknown default:
                    backdropPlaceholder
                }
            }
        } else {
            backdropPlaceholder
        }
    }

    private var backdropPlaceholder: some View {
        LinearGradient(
            colors: [.red.opacity(0.45), .black, .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Today's Schedule")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 80)

            LazyVStack(spacing: 14) {
                ForEach(schedule) { programme in
                    EPGRow(programme: programme)
                        .padding(.horizontal, 80)
                }
            }
        }
        .padding(.top, 40)
    }

    private func playLive() {
        guard let profile = profileStore.profile,
              let item = PlayableItem.live(channel, profile: profile) else {
            MKSLog.player.error("Could not build PlayableItem for channel streamId=\(channel.streamId)")
            return
        }
        MKSLog.player.info("Channel play streamId=\(channel.streamId)")
        playingItem = item
    }

    private func timeRange(_ p: MockProgramme) -> String {
        "\(timeString(p.start)) – \(timeString(p.end))"
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: - EPGRow

private struct EPGRow: View {
    let programme: MockProgramme

    @Environment(\.isFocused) private var isFocused

    private var status: Status {
        let now = Date()
        if now < programme.start { return .upcoming }
        if now < programme.end { return .live }
        return .past
    }

    private enum Status { case past, live, upcoming }

    var body: some View {
        HStack(spacing: 24) {
            timeBlock
                .frame(width: 180, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(programme.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                    if status == .live {
                        liveBadge
                    }
                }

                if status == .live {
                    ProgressView(value: programme.progress)
                        .progressViewStyle(.linear)
                        .tint(.red)
                        .frame(height: 4)
                        .frame(maxWidth: 480)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(rowBackground)
        )
    }

    private var timeBlock: some View {
        HStack(spacing: 8) {
            Text(timeString(programme.start))
                .font(.title3.weight(.semibold))
                .foregroundStyle(textColor)
            Text("→")
                .foregroundStyle(.white.opacity(0.4))
            Text(timeString(programme.end))
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text("LIVE")
                .font(.caption2.weight(.heavy))
                .tracking(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.red.opacity(0.18), in: Capsule())
        .foregroundStyle(.white)
    }

    private var textColor: Color {
        switch status {
        case .past:     return .white.opacity(0.45)
        case .live:     return .white
        case .upcoming: return .white.opacity(0.85)
        }
    }

    private var rowBackground: Color {
        switch status {
        case .live: return .red.opacity(0.12)
        case .past: return .white.opacity(0.02)
        case .upcoming: return .white.opacity(0.04)
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
