//
//  PlatformSpecificAddDownloadViewMovie.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 20/3/25.
//


//
//  PlatformSpecificAddDownloadViewMovie.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 20/3/25.
//

import SwiftUI

struct PlatformSpecificAddDownloadViewMovie: View {
    @Binding var selectedView: String?
    let movieDetail: MovieDetail
    var onDismiss: () -> Void
    
    var body: some View {
        #if os(iOS)
        AddDownloadMediaViewiOS(
            selectedView: $selectedView,
            mediaItem: movieDetail,
            onDismiss: onDismiss
        )
        #else
        AddDownloadView(
            selectedView: $selectedView,
            movieDetail: movieDetail,
            onDismiss: onDismiss
        )
        #endif
    }
}
