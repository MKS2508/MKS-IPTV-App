//
//  MediaListView+CardHelpers.swift
//  mks-multiplatform-iptv
//
//  Card helper methods for MediaListView
//

import SwiftUI

extension MediaListView {
    // MARK: - Card Helper Methods
    
    @ViewBuilder
    func mediaItemCard(for item: any MediaIndexItem) -> some View {
        if let movie = item as? Movie {
            PlatformSpecificMovieCardViewAdvanced(
                movie: movie,
                namespace: animation,
                onViewDetails: {
                    showMovieDetail(for: movie.streamId)
                }
            )
            .onTapGesture {
                showMovieDetail(for: movie.streamId)
            }
        } else if let serie = item as? Serie {
            PlatformSpecificSerieCardViewAdvanced(
                serie: serie,
                namespace: animation,
                onViewDetails: {
                    showSerieDetail(for: serie)
                }
            )
            .onTapGesture {
                showSerieDetail(for: serie)
            }
        }
    }
}
