import SwiftUI

// MARK: - Main Views for AddDownloadView

struct DownloadViews {
    
    static func loadingView() -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Cargando detalles...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    static func errorView(error: Error, onRetry: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            
            Text("Error al cargar detalles")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text(error.localizedDescription)
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Reintentar") {
                onRetry()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    static func contentView(geometry: GeometryProxy, movieDetail: MovieDetail, profile: IPTVProfile, onPlay: @escaping () -> Void, onDownload: @escaping () -> Void, onCopyURL: @escaping () -> Void, onOptions: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            // Main content area
            HStack(spacing: 0) {
                // Left column: Movie poster and basic info
                VStack(spacing: 20) {
                    MovieInfoViews.moviePosterView(movieDetail: movieDetail)
                    MovieInfoViews.movieBasicInfoView(movieDetail: movieDetail)
                }
                .frame(width: geometry.size.width * 0.35)
                .padding()
                
                // Right column: Detailed info
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        MovieInfoViews.movieDetailedInfoView(movieDetail: movieDetail)
                    }
                    .padding()
                }
                .frame(width: geometry.size.width * 0.65)
            }
            
            // Action buttons at the bottom
            ActionButtonsView(
                movieDetail: movieDetail,
                profile: profile,
                onPlay: onPlay,
                onDownload: onDownload,
                onCopyURL: onCopyURL,
                onOptions: onOptions,
                onCancel: onCancel
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}