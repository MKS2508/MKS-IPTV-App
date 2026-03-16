import SwiftUI
import Combine

struct MetadataOverlayView: View {
    let metadata: MetadataResult
    var useGlassStyle: Bool = false
    
    var body: some View {
        if useGlassStyle {
            glassStyleBody
        } else {
            legacyStyleBody
        }
    }
    
    @ViewBuilder
    private var legacyStyleBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection
            detailsSection
            plotSection
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
    
    @ViewBuilder
    private var glassStyleBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            glassHeaderSection
            glassDetailsSection
            glassPlotSection
        }
        .padding(14)
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: AppGlass.cornerRadius), fallbackOpacity: 0.75)
    }
    
    @ViewBuilder
    private var headerSection: some View {
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
            
            if let rating = metadata.rating {
                ratingBadge(rating: rating, useGlass: false)
            }
        }
    }
    
    @ViewBuilder
    private var glassHeaderSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(metadata.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if let year = metadata.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            
            Spacer()
            
            if let rating = metadata.rating {
                ratingBadge(rating: rating, useGlass: true)
            }
        }
    }
    
    @ViewBuilder
    private func ratingBadge(rating: Double, useGlass: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundColor(.yellow)
            Text(String(format: "%.1f", rating))
                .font(useGlass ? .caption.weight(.semibold) : .caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, useGlass ? 10 : 8)
        .padding(.vertical, useGlass ? 6 : 4)
        .if(useGlass) { view in
            view.adaptiveGlass(in: Capsule(), fallbackOpacity: 0.5)
        }
        .if(!useGlass) { view in
            view.background(Color.white.opacity(0.2))
                .cornerRadius(6)
        }
    }
    
    @ViewBuilder
    private var detailsSection: some View {
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
    }
    
    @ViewBuilder
    private var glassDetailsSection: some View {
        HStack(spacing: 12) {
            if let director = metadata.director, !director.isEmpty {
                Label(director, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            
            if !metadata.genre.isEmpty {
                HStack(spacing: 4) {
                    ForEach(metadata.genre.prefix(3), id: \.self) { genre in
                        Text(genre)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .adaptiveGlass(in: Capsule(), fallbackOpacity: 0.3)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var plotSection: some View {
        if let plot = metadata.plot, !plot.isEmpty {
            Text(plot)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
        }
    }
    
    @ViewBuilder
    private var glassPlotSection: some View {
        if let plot = metadata.plot, !plot.isEmpty {
            Text(plot)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
        }
    }
}

#Preview("Legacy Style") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VStack {
            Spacer()
            MetadataOverlayView(
                metadata: MetadataResult(
                    title: "The Matrix",
                    year: 1999,
                    genre: ["Action", "Sci-Fi"],
                    plot: "A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.",
                    director: "The Wachowskis",
                    providerName: "Preview",
                    confidence: 1.0,
                    mediaType: .movie
                )
            )
            .padding()
        }
    }
}

#Preview("Glass Style") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            MetadataOverlayView(
                metadata: MetadataResult(
                    title: "The Matrix",
                    year: 1999,
                    genre: ["Action", "Sci-Fi"],
                    plot: "A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.",
                    director: "The Wachowskis",
                    providerName: "Preview",
                    confidence: 1.0,
                    mediaType: .movie
                ),
                useGlassStyle: true
            )
            .padding()
        }
    }
}
