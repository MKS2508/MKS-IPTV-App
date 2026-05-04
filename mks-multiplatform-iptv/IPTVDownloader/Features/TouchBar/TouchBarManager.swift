import SwiftUI
import Combine
import IPTVCore

#if os(macOS)
class TouchBarManager: ObservableObject {
    // MARK: - Context
    enum Context {
        case downloads
        case mediaList
        case liveTV
        case movieDetail
        case serieDetail
    }
    
    enum SortOption: String, CaseIterable {
        case nameAsc = "Name A-Z"
        case nameDesc = "Name Z-A"
        case dateAsc = "Oldest First"
        case dateDesc = "Newest First"
        case rating = "Rating"
    }
    
    // MARK: - Published Properties
    @Published var currentContext: Context = .mediaList
    
    // Downloads properties
    @Published var progress: Double = 0.0
    @Published var overallProgress: Double = 0.0
    @Published var activeDownloads: Int = 0
    @Published var downloadSpeed: Double = 0.0
    @Published var isPaused: Bool = false
    @Published var estimatedTimeRemaining: TimeInterval = 0.0
    
    // Media list properties
    @Published var searchText: String = ""
    @Published var selectedCategories: Set<String> = []
    @Published var selectedCategoryIDs: Set<String> = [] // Store category IDs for filtering
    @Published var availableCategories: [String] = []
    @Published var currentSortOption: SortOption = .nameAsc
    @Published var isRefreshing: Bool = false
    
    // Live TV properties
    @Published var isPlaying: Bool = false
    @Published var volume: Float = 1.0
    @Published var currentChannel: String = ""
    @Published var availableChannels: [String] = []
    
    // Movie/Serie detail properties
    @Published var currentRating: String = "N/A"
    @Published var currentMediaTitle: String = ""
    
    // MARK: - Actions
    var onPlayPause: (() -> Void)?
    var onDownload: (() -> Void)?
    var onCancelDownloads: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onSearchTextChange: ((String) -> Void)?
    var onCategoryToggle: ((String) -> Void)?
    var onSortChange: ((SortOption) -> Void)?
    var onVolumeChange: ((Float) -> Void)?
    var onChannelChange: ((String) -> Void)?
    
    // MARK: - Computed Properties
    var formattedSpeed: String {
        if downloadSpeed < 1024 {
            return String(format: "%.0f B/s", downloadSpeed)
        } else if downloadSpeed < 1024 * 1024 {
            return String(format: "%.1f KB/s", downloadSpeed / 1024)
        } else {
            return String(format: "%.1f MB/s", downloadSpeed / (1024 * 1024))
        }
    }
    
    // MARK: - Methods
    func togglePauseResume() {
        isPaused.toggle()
        onPlayPause?()
    }
    
    func cancelAllDownloads() {
        onCancelDownloads?()
    }
    
    func refresh() {
        isRefreshing = true
        onRefresh?()
        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isRefreshing = false
        }
    }
    
    func toggleCategory(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        onCategoryToggle?(category)
    }
    
    func selectCategory(_ category: String) {
        // Clear current selection and select only this category
        selectedCategories.removeAll()
        selectedCategories.insert(category)
        onCategoryToggle?(category)
    }
    
    func togglePlayPause() {
        isPlaying.toggle()
        onPlayPause?()
    }
    
    func playMedia() {
        isPlaying = true
        onPlayPause?()
    }
    
    func downloadMedia() {
        onDownload?()
    }
    
    func updateSearchText(_ text: String) {
        searchText = text
        onSearchTextChange?(text)
    }
    
    func updateSortOption(_ option: SortOption) {
        currentSortOption = option
        onSortChange?(option)
    }
    
    func updateVolume(_ newVolume: Float) {
        volume = newVolume
        onVolumeChange?(newVolume)
    }
    
    func selectChannel(_ channel: String) {
        currentChannel = channel
        onChannelChange?(channel)
    }
    
    // MARK: - Context Management
    func switchToContext(_ context: Context) {
        MKSLog.app.debug("TouchBarManager: Switching context from \(currentContext) to \(context)")
        currentContext = context
    }
    
    // MARK: - Download Progress Tracking
    func updateDownloadProgress(active: Int, progress: Double, speed: Double, eta: TimeInterval = 0.0) {
        activeDownloads = active
        overallProgress = progress
        downloadSpeed = speed
        estimatedTimeRemaining = eta
    }
    
    func updateCategories(_ categories: [String]) {
        MKSLog.app.debug("TouchBarManager: Updating categories to: \(categories)")
        availableCategories = categories
    }
    
    func updateChannels(_ channels: [String]) {
        availableChannels = channels
    }
    
    func updateMediaDetails(title: String, rating: String) {
        currentMediaTitle = title
        currentRating = rating
    }
}
#endif
