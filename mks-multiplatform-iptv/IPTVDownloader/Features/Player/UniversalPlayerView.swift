import SwiftUI
import Combine

// MARK: - Metadata Overlay View

/// Collapsible info panel displayed over the player showing enriched metadata.
/// Used by MKSPlayerView and inline player views throughout the app.
struct MetadataOverlayView: View {
    let metadata: MetadataResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and year
            HStack {
                Text(metadata.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let year = metadata.year {
                    Text("(\(String(year)))")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                // Rating badge
                if let rating = metadata.rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
                }
            }

            // Director and genre
            HStack(spacing: 12) {
                if let director = metadata.director, !director.isEmpty {
                    Label(director, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }

                if !metadata.genre.isEmpty {
                    Text(metadata.genre.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            // Plot (first 2 lines)
            if let plot = metadata.plot, !plot.isEmpty {
                Text(plot)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.85), Color.black.opacity(0.6)],
                startPoint: .bottom,
                endPoint: .top
            )
        )
    }
}
