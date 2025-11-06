import Foundation
import Combine

class DownloadManager: ObservableObject {
    @Published private(set) var downloads: [DownloadItem] = []
    
    private var downloaders: [UUID: VideoDownloader] = [:]
    private var progressSubscriptions: [UUID: AnyCancellable] = [:]
    private let profile: IPTVProfile
    
    init(profile: IPTVProfile) {
        self.profile = profile
    }
    
    func addDownload(_ download: DownloadItem) {
        DispatchQueue.main.async {
            self.downloads.append(download)
        }
    }
    
    func cancelDownload(id: UUID) {
        guard let downloader = downloaders[id] else { return }
        downloader.cancel()
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
        
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .cancelled
        }
        
        // Clean up
        downloaders[id] = nil
    }
    
    func pauseDownload(id: UUID) {
        guard let downloader = downloaders[id] else { return }
        downloader.pause()
        
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].status = .paused
        }
    }
    
    func cancelAllDownloads() {
        for download in downloads where download.status == .downloading || download.status == .paused {
            cancelDownload(id: download.id)
        }
    }
    
    func togglePauseResumeAll() {
        let activeDownloads = downloads.filter { $0.status == .downloading }
        let pausedDownloads = downloads.filter { $0.status == .paused }
        
        if !activeDownloads.isEmpty {
            // Pause all active downloads
            for download in activeDownloads {
                pauseDownload(id: download.id)
            }
        } else if !pausedDownloads.isEmpty {
            // Resume all paused downloads
            for download in pausedDownloads {
                resumeDownload(id: download.id)
            }
        }
    }
    
    func startDownload(vodID: String, title: String, type: MediaType, vodExtension: String, shouldConvertToMOV: Bool, downloadPathParam: String) {
        let download = DownloadItem(
            id: UUID(),
            vodID: vodID,
            title: title,
            type: type,
            status: .notStarted
        )
        
        DispatchQueue.main.async {
            self.downloads.append(download)
        }
        
        // Create a new downloader for this download
        let downloader = VideoDownloader(profile: profile)
        downloader.shouldConvertToMOV = true
        downloaders[download.id] = downloader
        
        // Set up a new progress subscription for this download
        let progressSubscription = downloader.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.handleCompletion(for: download.id, completion: completion)
            }, receiveValue: { [weak self] progress in
                self?.updateProgress(for: download.id, progress: progress)
            })
        progressSubscriptions[download.id] = progressSubscription
        
        Task {
            do {
                var downloadPath = ""
                // Usa la ruta definida en las configuraciones, o un valor por defecto si no está configurada
                if (downloadPathParam != "") {
                    downloadPath = downloadPathParam
                } else {
                    downloadPath = UserDefaults.downloadPath
                }
                
                let destinationPath = URL(fileURLWithPath: downloadPath)
                    .appendingPathComponent("\(title).\(vodExtension)")
                    .path
                
                if type == .movie {
                    try await downloader.downloadMovie(vodID: vodID, to: destinationPath, vodExtension: vodExtension)
                } else {
                    try await downloader.downloadSerie(vodID: vodID, to: destinationPath, vodExtension: vodExtension)
                }
                
                // Mark as completed when the download function completes
                await MainActor.run {
                    if let index = self.downloads.firstIndex(where: { $0.id == download.id }) {
                        self.downloads[index].status = .completed
                        self.downloads[index].progress = 100.0
                        
                        // Clean up
                        self.downloaders[download.id] = nil
                        self.progressSubscriptions[download.id]?.cancel()
                        self.progressSubscriptions[download.id] = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(for: download.id, error: error)
                }
            }
        }
    }
    
    func resumeDownload(id: UUID) {
        guard let download = downloads.first(where: { $0.id == id }),
              download.status == .paused,
              let downloader = downloaders[id] else {
            return
        }
        
        // Set up new progress subscription for resumed download
        progressSubscriptions[id]?.cancel()
        let progressSubscription = downloader.progressPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.handleCompletion(for: id, completion: completion)
            }, receiveValue: { [weak self] progress in
                self?.updateProgress(for: id, progress: progress)
            })
        progressSubscriptions[id] = progressSubscription
        
        Task {
            do {
                try await downloader.resume()
                
                await MainActor.run {
                    if let index = downloads.firstIndex(where: { $0.id == id }) {
                        downloads[index].status = .downloading
                    }
                }
            } catch {
                await MainActor.run {
                    self.handleError(for: id, error: error)
                }
            }
        }
    }
    
    private func handleCompletion(for id: UUID, completion: Subscribers.Completion<Never>) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        // Only .finished is possible since Failure is Never
        if downloads[index].status != .paused && downloads[index].status != .cancelled {
            downloads[index].status = .completed
            downloads[index].progress = 100.0
        }
        
        // Clean up
        downloaders[id] = nil
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
    }
    
    private func updateProgress(for id: UUID, progress: VideoDownloader.DownloadProgress) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        var updatedDownload = downloads[index]
        if updatedDownload.status != .paused && updatedDownload.status != .cancelled {
            updatedDownload.status = .downloading
        }
        updatedDownload.progress = progress.percentComplete
        updatedDownload.speed = progress.speed
        updatedDownload.eta = progress.eta
        updatedDownload.totalBytes = progress.totalBytes > 0 ? progress.totalBytes : updatedDownload.totalBytes
        updatedDownload.bytesDownloaded = progress.bytesDownloaded
        downloads[index] = updatedDownload
        
        // Check if download is at 100% and update status if needed
        if progress.percentComplete >= 100.0 && updatedDownload.status == .downloading {
            // Manually trigger completion handling
            handleCompletion(for: id, completion: .finished)
        }
    }
    
    private func handleError(for id: UUID, error: Error) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            if let downloadError = error as? VideoDownloader.DownloadError {
                switch downloadError {
                case .downloadPaused:
                    downloads[index].status = .paused
                case .downloadCancelled:
                    downloads[index].status = .cancelled
                default:
                    downloads[index].status = .failed
                    downloads[index].error = error
                }
            } else {
                downloads[index].status = .failed
                downloads[index].error = error
            }
        }
        
        // Clean up
        downloaders[id] = nil
        progressSubscriptions[id]?.cancel()
        progressSubscriptions[id] = nil
    }
}

class PreviewDownloadManager: DownloadManager {
    init() {
        super.init(profile: IPTVProfile(name: "Preview", baseURL: "http://preview.com", username: "test", password: "test"))
    }
    
    override func cancelDownload(id: UUID) {
        print("Cancelling download with ID: \(id)")
    }
    
    override func pauseDownload(id: UUID) {
        print("Pausing download with ID: \(id)")
    }
    
    override func resumeDownload(id: UUID) {
        print("Resuming download with ID: \(id)")
    }
}
