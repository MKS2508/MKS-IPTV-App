//
//  PlatformSpecificAddDownloadViewSerie.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 20/3/25.
//

import SwiftUI

struct PlatformSpecificAddDownloadViewSerie: View {
    @Binding var selectedView: String?
    let seriesDetail: SerieDetail
    let seriesId: Int?
    var onDismiss: () -> Void
    
    // Convenience initializer for backwards compatibility
    init(selectedView: Binding<String?>, seriesDetail: SerieDetail, onDismiss: @escaping () -> Void) {
        self._selectedView = selectedView
        self.seriesDetail = seriesDetail
        self.seriesId = nil
        self.onDismiss = onDismiss
    }
    
    // Full initializer with seriesId
    init(selectedView: Binding<String?>, seriesDetail: SerieDetail, seriesId: Int?, onDismiss: @escaping () -> Void) {
        self._selectedView = selectedView
        self.seriesDetail = seriesDetail
        self.seriesId = seriesId
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        #if os(iOS)
        AddDownloadMediaViewiOS(selectedView: $selectedView, mediaItem: seriesDetail, onDismiss: onDismiss)
        #else
        AddDownloadViewSerie(selectedView: $selectedView, seriesDetail: seriesDetail, seriesId: seriesId, onDismiss: onDismiss)
        #endif
    }
}
