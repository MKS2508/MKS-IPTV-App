import SwiftUI
import Combine

#if os(macOS)
import AppKit

struct TouchBarAccessor: NSViewRepresentable {
    @ObservedObject var touchBarManager: TouchBarManager
    
    func makeNSView(context: Context) -> NSView {
        MKSLog.app.debug("TouchBar: Creating TouchBarAccessor NSView")
        return TouchBarHostingView(touchBarManager: touchBarManager)
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let hostingView = nsView as? TouchBarHostingView {
            hostingView.touchBarManager = touchBarManager
        }
    }
}

class TouchBarHostingView: NSView {
    var touchBarManager: TouchBarManager {
        didSet {
            // Force TouchBar update when manager changes
            updateTouchBar()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init(touchBarManager: TouchBarManager) {
        MKSLog.app.debug("TouchBar: Initializing TouchBarHostingView")
        self.touchBarManager = touchBarManager
        super.init(frame: .zero)
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        // Merge all state-change publishers into one stream and debounce so that
        // a burst of rapid property changes (e.g. categories loading at startup)
        // collapses into a single TouchBar rebuild instead of one per change.
        let voidPublishers: [AnyPublisher<Void, Never>] = [
            touchBarManager.$currentContext.map { _ in () }.eraseToAnyPublisher(),
            touchBarManager.$availableCategories.map { _ in () }.eraseToAnyPublisher(),
            touchBarManager.$availableChannels.map { _ in () }.eraseToAnyPublisher(),
            touchBarManager.$isRefreshing.map { _ in () }.eraseToAnyPublisher(),
            touchBarManager.$activeDownloads.map { _ in () }.eraseToAnyPublisher(),
            touchBarManager.$selectedCategories.map { _ in () }.eraseToAnyPublisher(),
            touchBarManager.$estimatedTimeRemaining.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(voidPublishers)
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTouchBar()
            }
            .store(in: &cancellables)
    }
    
    private func updateTouchBar() {
        self.touchBar = makeTouchBar()

        // Force the window to update its TouchBar
        if let window = self.window {
            window.touchBar = self.touchBar
            NSApp.touchBar = self.touchBar
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = self.window else {
            MKSLog.app.debug("TouchBar: No window found")
            return
        }
        
        MKSLog.app.debug("TouchBar: View moved to window")
        
        // Ensure the view can become first responder
        DispatchQueue.main.async {
            // Make window key and set first responder
            window.makeKey()
            if window.makeFirstResponder(self) {
                MKSLog.app.debug("TouchBar: Successfully became first responder")
            } else {
                MKSLog.app.debug("TouchBar: Failed to become first responder")
            }
            
            // Force TouchBar update
            self.updateTouchBar()
            if self.touchBar != nil {
                MKSLog.app.debug("TouchBar: TouchBar created successfully")
            } else {
                MKSLog.app.debug("TouchBar: Failed to create TouchBar")
            }
        }
    }
    
    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.delegate = self

        // Configure TouchBar items based on current context
        switch touchBarManager.currentContext {
        case .downloads:
            if touchBarManager.activeDownloads > 0 {
                touchBar.defaultItemIdentifiers = [.fullWidthDownloadBar]
            } else {
                touchBar.defaultItemIdentifiers = [.flexibleSpace, .refreshButton]
            }
        case .mediaList:
            if touchBarManager.availableCategories.isEmpty {
                touchBar.defaultItemIdentifiers = [.mediaListLoadingView]
            } else {
                touchBar.defaultItemIdentifiers = [.mediaListFullView]
            }
        case .liveTV:
            if touchBarManager.availableChannels.isEmpty {
                touchBar.defaultItemIdentifiers = [.flexibleSpace, .refreshButton]
            } else {
                touchBar.defaultItemIdentifiers = [
                    .playPauseButton, .volumeSlider, .flexibleSpace, .channelPicker
                ]
            }
        case .movieDetail, .serieDetail:
            touchBar.defaultItemIdentifiers = [
                .playButton, .downloadButton, .flexibleSpace, .ratingDisplay
            ]
        }
        return touchBar
    }
}

extension TouchBarHostingView: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        // print("TouchBar: Making item for identifier: \(identifier.rawValue)")
        
        switch identifier {
        // Test button
        case .testButton:
            return makeTestButton()
        // Downloads context items
        case .fullWidthDownloadBar:
            return makeFullWidthDownloadBar()
        case .downloadProgress:
            return makeProgressItem()
        case .pauseResumeButton:
            return makePauseResumeButton()
        case .cancelButton:
            return makeCancelButton()
        case .downloadStats:
            return makeDownloadStatsItem()
            
        // Media list context items
        case .mediaListFullView:
            return makeMediaListFullView()
        case .mediaListLoadingView:
            return makeMediaListLoadingView()
        case .searchField:
            return makeSearchField()
        case .categoryFilter:
            return makeCategoryFilterButton()
        case .sortOptions:
            return makeSortOptionsButton()
        case .refreshButton:
            return makeRefreshButton()
            
        // Live TV context items
        case .playPauseButton:
            return makePlayPauseButton()
        case .volumeSlider:
            return makeVolumeSlider()
        case .channelPicker:
            return makeChannelPicker()
            
        // Movie/Serie detail context items
        case .playButton:
            return makePlayButton()
        case .downloadButton:
            return makeDownloadButton()
        case .ratingDisplay:
            return makeRatingDisplay()
            
        case .fixedSpaceSmall:
            return makeFixedSpaceSmall()
            
        case .downloadSpeed:
            return makeDownloadSpeedItem()
            
        case .downloadETA:
            return makeDownloadETAItem()
            
        default:
            // Handle category items
            if identifier.rawValue.hasPrefix("category.") {
                return makeCategoryItem(for: identifier)
            }
            return nil
        }
    }
    
    // MARK: - Test Items
    
    private func makeTestButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .testButton)
        let button = Button(action: {
            MKSLog.app.debug("TouchBar: Test button tapped!")
        }) {
            HStack {
                Image(systemName: "star.fill")
                Text("Test")
            }
            .font(.system(size: 14))
        }
        .frame(width: 80)
        
        item.viewController = NSHostingController(rootView: button)
        return item
    }
    
    private func makeCategoryItem(for identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSButtonTouchBarItem(identifier: identifier)
        
        // Handle "All" category
        if identifier.rawValue == "category.all" {
            item.title = "All"
            item.target = self
            item.action = #selector(selectAllCategories(_:))
            item.bezelColor = touchBarManager.selectedCategories.isEmpty ? .controlAccentColor : nil
            return item
        }
        
        // Extract category index from identifier
        guard let indexString = identifier.rawValue.components(separatedBy: ".").last,
              let index = Int(indexString),
              index < touchBarManager.availableCategories.count else {
            return nil
        }
        
        let categoryName = touchBarManager.availableCategories[index]
        item.title = categoryName
        item.target = self
        item.action = #selector(selectCategory(_:))
        
        // Highlight selected categories
        let isSelected = touchBarManager.selectedCategories.contains(categoryName)
        item.bezelColor = isSelected ? .controlAccentColor : nil
        
        return item
    }
    
    @objc private func selectAllCategories(_ sender: NSButtonTouchBarItem) {
        touchBarManager.selectedCategories.removeAll()
        touchBarManager.onCategoryToggle?("")
        MKSLog.app.debug("TouchBar: All categories selected")
    }
    
    @objc private func selectCategory(_ sender: NSButtonTouchBarItem) {
        let title = sender.title
        MKSLog.app.debug("TouchBar: Category selected: \(title)")
        touchBarManager.selectCategory(title)
    }
    
    // MARK: - Downloads Items
    
    private func makeFullWidthDownloadBar() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .fullWidthDownloadBar)

        let activeDownloads = touchBarManager.activeDownloads
        let progress = touchBarManager.overallProgress
        let speedText = touchBarManager.formattedSpeed
        let eta = touchBarManager.estimatedTimeRemaining
        let etaText = eta > 0 ? formatETA(eta) : "--:--"

        let downloadsTouchBarView = DownloadsTouchBarView(
            activeDownloads: activeDownloads,
            progress: progress,
            speedText: speedText,
            etaText: etaText,
            isPaused: touchBarManager.isPaused,
            onPauseResume: {
                self.touchBarManager.togglePauseResume()
            },
            onCancel: {
                self.touchBarManager.cancelAllDownloads()
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        let hostingController = NSHostingController(rootView: downloadsTouchBarView)
        
        // 👇 Aquí forzamos el ancho máximo del Touch Bar
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        // Removed fixed width to allow natural layout
        // Removed fixed height to allow adaptive layout
        
        item.viewController = hostingController
        return item
    }
    private func makeProgressItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .downloadProgress)
        let progressView = VStack(spacing: 4) {
            HStack {
                Text("Progress")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(Int(touchBarManager.overallProgress * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            
            ProgressView(value: touchBarManager.overallProgress)
                .progressViewStyle(.linear)
                .scaleEffect(y: 1.5) // Make progress bar thicker
        }
        .frame(width: 180, height: 40)
        .padding(.horizontal, 8)
        
        item.viewController = NSHostingController(rootView: progressView)
        return item
    }
    
    private func makePauseResumeButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .pauseResumeButton)
        let button = VStack(spacing: 2) {
            Button(action: {
                self.touchBarManager.togglePauseResume()
            }) {
                Image(systemName: touchBarManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(touchBarManager.isPaused ? Color.green : Color.orange)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Text(touchBarManager.isPaused ? "Resume" : "Pause")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 60, height: 40)
        .disabled(touchBarManager.activeDownloads == 0)
        
        item.viewController = NSHostingController(rootView: button)
        return item
    }
    
    @objc private func pauseResumeDownloads(_ sender: NSButtonTouchBarItem) {
        touchBarManager.togglePauseResume()
        // Update button image
        sender.image = NSImage(systemSymbolName: touchBarManager.isPaused ? "play.fill" : "pause.fill", accessibilityDescription: touchBarManager.isPaused ? "Resume" : "Pause")
    }
    
    private func makeCancelButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .cancelButton)
        let button = VStack(spacing: 2) {
            Button(action: {
                self.touchBarManager.cancelAllDownloads()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            Text("Cancel")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 60, height: 40)
        .disabled(touchBarManager.activeDownloads == 0)
        
        item.viewController = NSHostingController(rootView: button)
        return item
    }
    
    @objc private func cancelAllDownloads(_ sender: NSButtonTouchBarItem) {
        touchBarManager.cancelAllDownloads()
    }
    
    private func makeDownloadStatsItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .downloadStats)
        let activeDownloads = touchBarManager.activeDownloads
        
        let statsView = VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text("\(activeDownloads)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Text(activeDownloads == 1 ? "download" : "downloads")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Text("Active")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 120, height: 40)
        .padding(.horizontal, 8)
        
        item.viewController = NSHostingController(rootView: statsView)
        return item
    }
    
    private func formatETA(_ eta: TimeInterval) -> String {
        let totalSeconds = Int(eta)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    // MARK: - Media List Items
    
    private func makeMediaListFullView() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .mediaListFullView)
        
        // Use native TouchBar implementation for better scrolling
        let _ = MediaListTouchBarView.createNativeTouchBar(
            availableCategories: touchBarManager.availableCategories,
            selectedCategories: touchBarManager.selectedCategories,
            isRefreshing: touchBarManager.isRefreshing,
            onCategoryToggle: { category in
                if category.isEmpty {
                    self.touchBarManager.selectedCategories.removeAll()
                } else {
                    self.touchBarManager.selectCategory(category)
                }
                self.touchBarManager.onCategoryToggle?(category)
            },
            onRefresh: {
                self.touchBarManager.refresh()
            },
            onSearchChange: { text in
                self.touchBarManager.searchText = text
                self.touchBarManager.onSearchTextChange?(text)
            }
        )
        
        // Create a container view for the native touch bar
        let containerView = NSView()
        containerView.frame = NSRect(x: 0, y: 0, width: 750, height: 30)
        
        // We'll return the native touchbar directly instead of embedding it
        // For now, let's use a SwiftUI fallback
        let mediaListView = MediaListTouchBarView(
            searchText: touchBarManager.searchText,
            availableCategories: touchBarManager.availableCategories,
            selectedCategories: touchBarManager.selectedCategories,
            isRefreshing: touchBarManager.isRefreshing,
            contentType: .all,
            onSearchChange: { text in
                self.touchBarManager.searchText = text
                self.touchBarManager.onSearchTextChange?(text)
            },
            onCategoryToggle: { category in
                if category.isEmpty {
                    self.touchBarManager.selectedCategories.removeAll()
                } else {
                    self.touchBarManager.selectCategory(category)
                }
                self.touchBarManager.onCategoryToggle?(category)
            },
            onRefresh: {
                self.touchBarManager.refresh()
            }
        )
        .frame(width: 750, height: 30)
        
        item.viewController = NSHostingController(rootView: mediaListView)
        return item
    }
    
    private func makeMediaListLoadingView() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .mediaListLoadingView)
        
        let loadingView = HStack(spacing: 12) {
            // Search field (disabled while loading)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Text("Search media...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.2))
            )
            .frame(width: 200)
            
            // Loading indicator
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(.white)
                
                Text("Loading categories...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Refresh button
            Button(action: {
                self.touchBarManager.refresh()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 750, height: 30)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
        )
        
        item.viewController = NSHostingController(rootView: loadingView)
        return item
    }
    
    private func makeSearchField() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .searchField)
        let searchField = NSSearchField()
        searchField.placeholderString = "Search media..."
        searchField.target = self
        searchField.action = #selector(handleSearch(_:))
        item.view = searchField
        return item
    }
    
    @objc private func handleSearch(_ sender: NSSearchField) {
        touchBarManager.searchText = sender.stringValue
        touchBarManager.onSearchTextChange?(sender.stringValue)
    }
    
    private func makeCategoryFilterButton() -> NSTouchBarItem {
        let item = NSPopoverTouchBarItem(identifier: .categoryFilter)
        item.collapsedRepresentationLabel = "Categories"
        item.collapsedRepresentationImage = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: nil)
        
        // Create a scrollable popover touch bar with items
        let popoverTouchBar = NSTouchBar()
        popoverTouchBar.delegate = self
        
        // Create identifiers for categories in a scrollable container
        var identifiers: [NSTouchBarItem.Identifier] = []
        
        // Add "All" category first
        identifiers.append(NSTouchBarItem.Identifier("category.all"))
        
        // Add all categories
        for (index, _) in touchBarManager.availableCategories.enumerated() {
            identifiers.append(NSTouchBarItem.Identifier("category.\(index)"))
        }
        
        // All categories in popover (TouchBar handles scrolling automatically)
        popoverTouchBar.defaultItemIdentifiers = identifiers
        item.popoverTouchBar = popoverTouchBar
        
        return item
    }
    
    private func makeSortOptionsButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .sortOptions)
        let sortButton = Menu {
            ForEach(TouchBarManager.SortOption.allCases, id: \.self) { option in
                Button(action: {
                    self.touchBarManager.currentSortOption = option
                }) {
                    HStack {
                        Text(option.rawValue)
                        if self.touchBarManager.currentSortOption == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 16))
        }
        .frame(width: 40)
        
        item.viewController = NSHostingController(rootView: sortButton)
        return item
    }
    
    private func makeRefreshButton() -> NSTouchBarItem {
        let item = NSButtonTouchBarItem(identifier: .refreshButton)
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        item.target = self
        item.action = #selector(refreshContent(_:))
        item.isEnabled = !touchBarManager.isRefreshing
        return item
    }
    
    @objc private func refreshContent(_ sender: NSButtonTouchBarItem) {
        touchBarManager.refresh()
    }
    
    // MARK: - Live TV Items
    
    private func makePlayPauseButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .playPauseButton)
        let button = Button(action: {
            self.touchBarManager.togglePlayPause()
        }) {
            Image(systemName: touchBarManager.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16))
        }
        .frame(width: 40)
        
        item.viewController = NSHostingController(rootView: button)
        return item
    }
    
    private func makeVolumeSlider() -> NSTouchBarItem {
        let item = NSSliderTouchBarItem(identifier: .volumeSlider)
        item.slider.minValue = 0
        item.slider.maxValue = 1
        item.slider.doubleValue = Double(touchBarManager.volume)
        item.target = self
        item.action = #selector(volumeChanged(_:))
        item.label = "Volume"
        return item
    }
    
    @objc private func volumeChanged(_ sender: NSSlider) {
        touchBarManager.volume = Float(sender.doubleValue)
    }
    
    private func makeChannelPicker() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .channelPicker)
        
        if touchBarManager.availableChannels.isEmpty {
            let loadingView = HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading...")
                    .font(.system(size: 11))
            }
            .frame(width: 100)
            
            item.viewController = NSHostingController(rootView: loadingView)
        } else {
            let channelView = Menu {
                ForEach(Array(touchBarManager.availableChannels.prefix(10)), id: \.self) { channel in
                    Button(action: {
                        self.touchBarManager.selectChannel(channel)
                    }) {
                        Text(channel)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "tv")
                        .font(.system(size: 12))
                    Text(touchBarManager.currentChannel.isEmpty ? "Select" : touchBarManager.currentChannel)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 120)
            
            item.viewController = NSHostingController(rootView: channelView)
        }
        
        return item
    }
    
    // MARK: - Movie/Serie Detail Items
    
    private func makePlayButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .playButton)
        let button = Button(action: {
            self.touchBarManager.playMedia()
        }) {
            HStack {
                Image(systemName: "play.fill")
                Text("Play")
            }
            .font(.system(size: 14))
        }
        .frame(width: 80)
        
        item.viewController = NSHostingController(rootView: button)
        return item
    }
    
    private func makeDownloadButton() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .downloadButton)
        let button = Button(action: {
            self.touchBarManager.downloadMedia()
        }) {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text("Download")
            }
            .font(.system(size: 14))
        }
        .frame(width: 100)
        
        item.viewController = NSHostingController(rootView: button)
        return item
    }
    
    private func makeRatingDisplay() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .ratingDisplay)
        let ratingView = HStack {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
            Text(touchBarManager.currentRating)
                .font(.system(size: 14, weight: .semibold))
        }
        .frame(width: 60)
        
        item.viewController = NSHostingController(rootView: ratingView)
        return item
    }
    
    // MARK: - Layout Helpers
    
    private func makeFixedSpaceSmall() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .fixedSpaceSmall)
        let spacer = Spacer()
            .frame(width: 8)
        
        item.viewController = NSHostingController(rootView: spacer)
        return item
    }
    
    private func makeDownloadSpeedItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .downloadSpeed)
        let speedView = VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(touchBarManager.formattedSpeed)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Text("Speed")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 120, height: 40)
        .padding(.horizontal, 8)
        
        item.viewController = NSHostingController(rootView: speedView)
        return item
    }
    
    private func makeDownloadETAItem() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .downloadETA)
        let eta = touchBarManager.estimatedTimeRemaining
        let etaText = eta > 0 ? formatETA(eta) : "--:--"
        
        let etaView = VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                Text(etaText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Text("ETA")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 100, height: 40)
        .padding(.horizontal, 8)
        
        item.viewController = NSHostingController(rootView: etaView)
        return item
    }
    
}

// MARK: - TouchBar Item Identifiers

extension NSTouchBarItem.Identifier {
    // Test
    static let testButton = NSTouchBarItem.Identifier("com.mks.iptv.testButton")
    
    // Downloads
    static let fullWidthDownloadBar = NSTouchBarItem.Identifier("com.mks.iptv.fullWidthDownloadBar")
    static let downloadProgress = NSTouchBarItem.Identifier("com.mks.iptv.downloadProgress")
    static let pauseResumeButton = NSTouchBarItem.Identifier("com.mks.iptv.pauseResumeButton")
    static let cancelButton = NSTouchBarItem.Identifier("com.mks.iptv.cancelButton")
    static let downloadStats = NSTouchBarItem.Identifier("com.mks.iptv.downloadStats")
    
    // Media List
    static let mediaListFullView = NSTouchBarItem.Identifier("com.mks.iptv.mediaListFullView")
    static let mediaListLoadingView = NSTouchBarItem.Identifier("com.mks.iptv.mediaListLoadingView")
    static let searchField = NSTouchBarItem.Identifier("com.mks.iptv.searchField")
    static let categoryFilter = NSTouchBarItem.Identifier("com.mks.iptv.categoryFilter")
    static let sortOptions = NSTouchBarItem.Identifier("com.mks.iptv.sortOptions")
    static let refreshButton = NSTouchBarItem.Identifier("com.mks.iptv.refreshButton")
    
    // Live TV
    static let playPauseButton = NSTouchBarItem.Identifier("com.mks.iptv.playPauseButton")
    static let volumeSlider = NSTouchBarItem.Identifier("com.mks.iptv.volumeSlider")
    static let channelPicker = NSTouchBarItem.Identifier("com.mks.iptv.channelPicker")
    
    // Movie/Serie Detail
    static let playButton = NSTouchBarItem.Identifier("com.mks.iptv.playButton")
    static let downloadButton = NSTouchBarItem.Identifier("com.mks.iptv.downloadButton")
    static let ratingDisplay = NSTouchBarItem.Identifier("com.mks.iptv.ratingDisplay")
    
    // Layout helpers
    static let fixedSpaceSmall = NSTouchBarItem.Identifier("com.mks.iptv.fixedSpaceSmall")
    static let downloadSpeed = NSTouchBarItem.Identifier("com.mks.iptv.downloadSpeed")
    static let downloadETA = NSTouchBarItem.Identifier("com.mks.iptv.downloadETA")
}
#endif
