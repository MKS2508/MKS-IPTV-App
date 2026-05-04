//
//  MediaDetailSheetWithProgress.swift
//  mks-multiplatform-iptv
//
//  Progressive loading wrapper for MediaDetailSheet.
//  Displays preview data from grid immediately while fetching full details.
//

import SwiftUI
import IPTVCore

/// Wrapper view that provides progressive loading for media details.
/// Shows preview data (from grid) immediately while fetching full details.
struct MediaDetailSheetWithProgress: View {
    /// The ViewModel containing both preview and full detail data
    @Bindable var viewModel: MediaDetailViewModel
    
    let onDismiss: () -> Void
    @Binding var selectedView: String?
    
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var profile: IPTVProfile
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if let detail = viewModel.movieDetail {
                // Full movie detail available
                MediaDetailSheet(
                    detail: detail,
                    onDismiss: onDismiss,
                    selectedView: $selectedView
                )
            } else if let detail = viewModel.serieDetail {
                // Full serie detail available
                MediaDetailSheet(
                    detail: detail,
                    onDismiss: onDismiss,
                    selectedView: $selectedView
                )
            } else if let preview = viewModel.moviePreview {
                // Movie preview - show with loading state
                previewDetailSheet(for: preview)
            } else if let preview = viewModel.seriePreview {
                // Serie preview - show with loading state
                previewDetailSheet(for: preview)
            } else if viewModel.isLoading {
                // Loading without preview
                loadingPlaceholder
            } else if let error = viewModel.error {
                // Error state
                errorView(error)
            }
        }
    }
    
    // MARK: - Preview Detail Sheet (Movie)
    
    @ViewBuilder
    private func previewDetailSheet(for movie: Movie) -> some View {
        MediaDetailSheet(
            detail: MoviePreviewWrapper(movie: movie),
            onDismiss: onDismiss,
            selectedView: $selectedView
        )
    }
    
    // MARK: - Preview Detail Sheet (Serie)
    
    @ViewBuilder
    private func previewDetailSheet(for serie: Serie) -> some View {
        MediaDetailSheet(
            detail: SeriePreviewWrapper(serie: serie),
            onDismiss: onDismiss,
            selectedView: $selectedView
        )
    }
    
    // MARK: - Loading Placeholder
    
    private var loadingPlaceholder: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .tint(AppColors.accent)
                Text("Loading...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Error View
    
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.red)
            Text("Failed to load details")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Close", action: onDismiss)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

// MARK: - Preview Wrappers

/// Wrapper to make Movie conform to MediaDetailItem for preview display
struct MoviePreviewWrapper: MediaDetailItem {
    let movie: Movie
    
    // TitleParseable
    var name: String { movie.name }
    
    // MediaLibraryItem
    var streamId: Int { movie.streamId }
    var categoryId: String { movie.categoryId }
    var coverImage: String? { movie.streamIcon }
    var displayRating: String { movie.rating ?? "0" }
    var displayRating5Based: Double { movie.rating5Based ?? 0 }
    var added: String? { movie.added }
    var mediaType: MediaType { .movie }
    var tmdbIdInt: Int? { movie.tmdbId.flatMap { Int($0) } }
    
    // MediaDetailItem - using available preview data
    var detailPlot: String { "" }
    var detailGenre: String { "" }
    var detailCast: [String] { [] }
    var detailDirector: String? { nil }
    var detailBackdropPaths: [String] { [] }
    var detailYoutubeTrailer: String? { nil }
    var detailDurationSeconds: Int { 0 }
    var detailReleaseDate: String { "" }
    var detailPosterURL: String? { movie.streamIcon }
}

/// Wrapper to make Serie conform to MediaDetailItem for preview display
struct SeriePreviewWrapper: MediaDetailItem {
    let serie: Serie
    
    // TitleParseable
    var name: String { serie.name }
    
    // MediaLibraryItem
    var streamId: Int { serie.seriesId }
    var categoryId: String { serie.categoryId }
    var coverImage: String? { serie.cover }
    var displayRating: String { serie.rating }
    var displayRating5Based: Double { serie.rating5Based }
    var added: String? { serie.lastModified }
    var mediaType: MediaType { .series }
    var tmdbIdInt: Int? { nil }
    
    // MediaDetailItem - Serie already has more preview data
    var detailPlot: String { serie.plot }
    var detailGenre: String { serie.genre }
    var detailCast: [String] {
        serie.cast.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    var detailDirector: String? { serie.director }
    var detailBackdropPaths: [String] { serie.backdropPath }
    var detailYoutubeTrailer: String? { serie.youtubeTrailer }
    var detailDurationSeconds: Int { 0 }
    var detailReleaseDate: String { serie.releaseDate }
    var detailPosterURL: String? { serie.cover }
}
