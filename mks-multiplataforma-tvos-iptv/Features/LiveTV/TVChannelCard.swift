//
//  TVChannelCard.swift
//  mks-multiplataforma-tvos-iptv
//
//  Live channel card with LIVE badge, current programme + progress.
//  Use as NavigationLink label with .buttonStyle(.card).
//

import SwiftUI
import IPTVCore

struct TVChannelCard: View {
    let channel: LiveChannel

    private let cardWidth: CGFloat = 360
    private let cardHeight: CGFloat = 220

    private var current: MockProgramme? { MockEPG.currentProgramme(for: channel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            footer
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(channel.name)
        .accessibilityHint(Text("Opens live channel"))
    }

    private var header: some View {
        HStack(spacing: 14) {
            iconView
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let quality = channel.quality {
                    Text(quality.uppercased())
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            liveBadge
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            if let current {
                Text(current.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(timeString(current.start))
                    Text("–")
                    Text(timeString(current.end))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

                ProgressView(value: current.progress)
                    .progressViewStyle(.linear)
                    .tint(.red)
                    .frame(height: 4)
            } else {
                Text("Live channel")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var iconView: some View {
        if let urlString = channel.streamIcon, let url = URL(string: urlString) {
            CachedHTTPImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                        .padding(6)
                case .failure, .empty:
                    iconPlaceholder
                @unknown default:
                    iconPlaceholder
                }
            }
            .background(.white.opacity(0.08))
        } else {
            iconPlaceholder
        }
    }

    private var iconPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.1)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
            Text("LIVE")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.white)
                .tracking(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(.red.opacity(0.5), lineWidth: 1))
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}
