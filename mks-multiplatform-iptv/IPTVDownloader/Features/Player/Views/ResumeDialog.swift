import SwiftUI
import IPTVCore

/// Apple TV+ style glass overlay asking the user whether to resume or start over.
///
/// Displayed when opening content with saved progress (2%–95%).
struct ResumeDialog: View {
    let entry: WatchHistoryEntry
    let onResume: () -> Void
    let onStartOver: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            dialogContent
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    private var dialogContent: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColors.accent)

                Text("Resume Playback?")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }

            // Content info
            HStack(spacing: 14) {
                // Mini poster
                if let posterStr = entry.posterURL, let url = URL(string: posterStr) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 90)
                                .clipped()
                        default:
                            posterPlaceholder
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    posterPlaceholder
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColors.accent)
                                .frame(width: geometry.size.width * entry.progress, height: 4)
                        }
                    }
                    .frame(height: 4)

                    if let remaining = entry.remainingTimeFormatted {
                        Text(remaining)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: AppGlass.cornerRadiusSmall)
                    .fill(Color.white.opacity(0.06))
            )

            // Action buttons
            VStack(spacing: 10) {
                Button {
                    onResume()
                } label: {
                    Label("Resume from \(entry.formattedPosition)", systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accent)

                Button {
                    onStartOver()
                } label: {
                    Label("Start from Beginning", systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button("Cancel", action: onCancel)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: 360)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius), fallbackOpacity: 0.9)
        .shadow(color: .black.opacity(0.4), radius: 30)
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(AppColors.surface)
            .frame(width: 60, height: 90)
            .overlay {
                Image(systemName: "film")
                    .foregroundStyle(AppColors.textTertiary)
            }
    }
}
