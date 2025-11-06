//
//  DownloadSwipeActions.swift
//  mks-iptv-downloader
//
//  Created by Marcos Asensio on 3/11/24.
//

import SwiftUI

struct DownloadSwipeActions: View {
    let download: DownloadItem
    let downloadManager: DownloadManager
    
    var body: some View {
        Group {
            if download.status == .downloading {
                Button {
                    downloadManager.pauseDownload(id: download.id)
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                }
                .tint(.yellow)
                
                Button(role: .destructive) {
                    downloadManager.cancelDownload(id: download.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            } else if download.status == .paused {
                Button {
                    downloadManager.resumeDownload(id: download.id)
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                .tint(.green)
                
                Button(role: .destructive) {
                    downloadManager.cancelDownload(id: download.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            }
        }
    }
}
