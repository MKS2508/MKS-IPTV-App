import SwiftUI
import IPTVCore

/// Netflix-style countdown overlay for auto-playing the next episode.
///
/// Appears in the bottom-right corner above player controls when an episode
/// completes and the next episode is available. Shows a 10-second countdown
/// with circular progress ring, "Play Now" and "Cancel" buttons.
struct AutoPlayNextOverlay: View {
    let info: NextEpisodeInfo
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    @State private var countdown: Int = 10
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()
                cardContent
                    .padding(.trailing, 20)
                    .padding(.bottom, 80) // Above player controls
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .onAppear { startCountdown() }
        .onDisappear { timerTask?.cancel() }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                // Countdown ring
                countdownRing
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT EPISODE")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.6))

                    Text(info.showTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Episode info
            HStack(spacing: 10) {
                // Mini poster
                if let posterStr = info.posterURL, let url = URL(string: posterStr) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 32)
                                .clipped()
                        default:
                            episodePlaceholder
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    episodePlaceholder
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("S\(String(format: "%02d", info.episode.season))E\(String(format: "%02d", info.episode.episodeNum))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppColors.accent)
                    Text(info.episode.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    timerTask?.cancel()
                    onPlayNow()
                } label: {
                    Label("Play Now", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)

                Button {
                    timerTask?.cancel()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(16)
        .frame(width: 280)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall), fallbackOpacity: 0.85)
        .shadow(color: .black.opacity(0.4), radius: 20)
    }

    // MARK: - Countdown Ring

    private var countdownRing: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)

            // Progress ring
            Circle()
                .trim(from: 0, to: CGFloat(countdown) / 10.0)
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: countdown)

            // Number
            Text("\(countdown)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Timer

    private func startCountdown() {
        timerTask = Task { @MainActor in
            while countdown > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
            guard !Task.isCancelled, countdown == 0 else { return }
            onPlayNow()
        }
    }

    // MARK: - Placeholder

    private var episodePlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(AppColors.surface)
            .frame(width: 56, height: 32)
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
    }
}
