import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    #if os(macOS)
    @EnvironmentObject private var touchBarManager: TouchBarManager
    #endif

    var body: some View {
        VStack {  // Usamos VStack para apilar verticalmente
            if downloadManager.downloads.isEmpty {
                emptyStateView
            } else {
                downloadsList
            }
        }
        .navigationTitle("Downloads")
        .background(VisualEffect().edgesIgnoringSafeArea(.all))
        #if os(macOS)
        .onAppear {
            updateTouchBarProgress()
        }
        .onReceive(downloadManager.$downloads) { downloads in
            updateTouchBarProgress()
        }
        .onReceive(downloadManager.objectWillChange) { _ in
            // Update TouchBar whenever download manager changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                updateTouchBarProgress()
            }
        }
        #endif
    }
    

    private var downloadsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(downloadManager.downloads) { download in
                    DownloadRowView(item: download, progress: download.progress)
                        .background(.background)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
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
                .onDelete(perform: deleteDownloads)
            }
        }
        .background(VisualEffect().edgesIgnoringSafeArea(.all))
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No Downloads")
                .font(.title2)
                .foregroundColor(.primary)
            
            Text("Your downloads will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffect().edgesIgnoringSafeArea(.all))
    }
    
    private func deleteDownloads(at offsets: IndexSet) {
        offsets.forEach { index in
            let download = downloadManager.downloads[index]
            downloadManager.cancelDownload(id: download.id)
        }
    }
    
    #if os(macOS)
    private func updateTouchBarProgress() {
        let activeDownloads = downloadManager.downloads.filter { $0.status == .downloading }
        // Convert progress from percentage (0-100) to decimal (0-1)
        let totalProgress = activeDownloads.isEmpty ? 0.0 : 
            activeDownloads.map { $0.progress / 100.0 }.reduce(0, +) / Double(activeDownloads.count)
        
        let totalSpeed = activeDownloads.map { $0.speed }.reduce(0, +)
        
        // Calculate average ETA from active downloads
        let averageETA = activeDownloads.isEmpty ? 0.0 : 
            activeDownloads.map { $0.eta }.reduce(0, +) / Double(activeDownloads.count)
        
        touchBarManager.updateDownloadProgress(
            active: activeDownloads.count,
            progress: totalProgress,
            speed: totalSpeed,
            eta: averageETA
        )
        
        touchBarManager.isPaused = downloadManager.downloads.contains { $0.status == .paused }
    }
    #endif
}


#if DEBUG
struct DownloadsView_Previews: PreviewProvider {
    static var previews: some View {
        let previewDownloadManager = DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
        
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "1", title: "Not Started", type: .movie, status: .notStarted, totalBytes: 100_000_000, bytesDownloaded: 0, progress: 0, speed: 0, eta: 0))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "2", title: "Downloading", type: .movie, status: .downloading, totalBytes: 100_000_000, bytesDownloaded: 45_000_000, progress: 45, speed: 2.5, eta: 120))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "3", title: "Paused", type: .movie, status: .paused, totalBytes: 100_000_000, bytesDownloaded: 60_000_000, progress: 60, speed: 0, eta: 0))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "4", title: "Completed", type: .movie, status: .completed, totalBytes: 100_000_000, bytesDownloaded: 100_000_000, progress: 100, speed: 0, eta: 0))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "5", title: "Cancelled", type: .movie, status: .cancelled, totalBytes: 100_000_000, bytesDownloaded: 30_000_000, progress: 30, speed: 0, eta: 0))
        previewDownloadManager.addDownload(DownloadItem(id: UUID(), vodID: "6", title: "Failed", type: .movie, status: .failed, totalBytes: 100_000_000, bytesDownloaded: 80_000_000, progress: 80, speed: 0, eta: 0, error: NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection error"]) as Error))
        
        return Group {
                DownloadsView()
                    .environmentObject(previewDownloadManager)
                    .previewDisplayName("With Downloads")
            
            NavigationView {
                DownloadsView()
                    .environmentObject(DownloadManager(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test")))
            }
            .previewDisplayName("Empty State")
        }
    }
}
#endif
