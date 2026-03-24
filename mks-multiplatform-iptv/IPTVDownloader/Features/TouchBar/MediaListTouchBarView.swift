import SwiftUI

#if os(macOS)
import AppKit

struct MediaListTouchBarView: View {
    let searchText: String
    let availableCategories: [String]
    let selectedCategories: Set<String>
    let isRefreshing: Bool
    let contentType: MediaContentType
    
    let onSearchChange: (String) -> Void
    let onCategoryToggle: (String) -> Void
    let onRefresh: () -> Void
    
    enum MediaContentType {
        case all
        case movies
        case series
        
        var displayName: String {
            switch self {
            case .all: return "All Media"
            case .movies: return "Movies"
            case .series: return "Series"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Search field
            searchField
                .frame(width: 200)
            
            // Categories scroll view
            if !availableCategories.isEmpty {
                categoriesScrollView
                    .frame(maxWidth: 400)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                sortButton
                refreshButton
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
        )
    }
    
    // MARK: - Components
    
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            TextField("Search \(contentType.displayName.lowercased())...", text: .constant(searchText))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .disabled(true) // Visual representation only for preview
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.2))
        )
    }
    
    private var categoriesScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" button
                categoryButton(
                    title: "All",
                    isSelected: selectedCategories.isEmpty,
                    action: { onCategoryToggle("") }
                )
                
                // Category buttons
                ForEach(availableCategories.prefix(20), id: \.self) { category in
                    categoryButton(
                        title: category,
                        isSelected: selectedCategories.contains(category),
                        action: { onCategoryToggle(category) }
                    )
                }
                
                if availableCategories.count > 20 {
                    Text("...")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 8)
        }
    }
    
    private func categoryButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    private var sortButton: some View {
        Button(action: {
            // Sort action placeholder
        }) {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 16))
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
        .help("Sort options")
    }
    
    private var refreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: isRefreshing ? "arrow.clockwise" : "arrow.clockwise")
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isRefreshing
                )
        }
        .buttonStyle(.plain)
        .help("Refresh content")
        .disabled(isRefreshing)
    }
}

// MARK: - Native TouchBar Implementation

extension MediaListTouchBarView {
    static func createNativeTouchBar(
        availableCategories: [String],
        selectedCategories: Set<String>,
        isRefreshing: Bool,
        onCategoryToggle: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onSearchChange: @escaping (String) -> Void
    ) -> NSTouchBar {
        let touchBar = NSTouchBar()
        touchBar.defaultItemIdentifiers = [
            .mediaListSearchField,
            .mediaListCategoriesScrollView,
            .flexibleSpace,
            .mediaListSortButton,
            .mediaListRefreshButton
        ]
        
        // Create delegate that handles the touch bar items
        let delegate = MediaListTouchBarDelegate(
            availableCategories: availableCategories,
            selectedCategories: selectedCategories,
            isRefreshing: isRefreshing,
            onCategoryToggle: onCategoryToggle,
            onRefresh: onRefresh,
            onSearchChange: onSearchChange
        )
        
        touchBar.delegate = delegate
        return touchBar
    }
}

class MediaListTouchBarDelegate: NSObject, NSTouchBarDelegate {
    let availableCategories: [String]
    let selectedCategories: Set<String>
    let isRefreshing: Bool
    let onCategoryToggle: (String) -> Void
    let onRefresh: () -> Void
    let onSearchChange: (String) -> Void
    
    init(
        availableCategories: [String],
        selectedCategories: Set<String>,
        isRefreshing: Bool,
        onCategoryToggle: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onSearchChange: @escaping (String) -> Void
    ) {
        self.availableCategories = availableCategories
        self.selectedCategories = selectedCategories
        self.isRefreshing = isRefreshing
        self.onCategoryToggle = onCategoryToggle
        self.onRefresh = onRefresh
        self.onSearchChange = onSearchChange
        super.init()
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case .mediaListSearchField:
            return makeSearchField()
        case .mediaListCategoriesScrollView:
            return makeCategoriesScrollView()
        case .mediaListSortButton:
            return makeSortButton()
        case .mediaListRefreshButton:
            return makeRefreshButton()
        default:
            return nil
        }
    }
    
    private func makeSearchField() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .mediaListSearchField)
        let searchField = NSSearchField()
        searchField.placeholderString = "Search media..."
        searchField.target = self
        searchField.action = #selector(handleSearch(_:))
        item.view = searchField
        return item
    }
    
    private func makeCategoriesScrollView() -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: .mediaListCategoriesScrollView)
        
        // Create scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        
        // Create container for buttons
        let containerView = NSView()
        var xOffset: CGFloat = 8
        let buttonHeight: CGFloat = 20
        
        // "All" button
        let allButton = NSButton()
        allButton.title = "All"
        allButton.bezelStyle = .rounded
        allButton.isBordered = true
        allButton.target = self
        allButton.action = #selector(selectAllCategories)
        allButton.frame = NSRect(x: xOffset, y: 5, width: 40, height: buttonHeight)
        allButton.bezelColor = selectedCategories.isEmpty ? .controlAccentColor : .clear
        containerView.addSubview(allButton)
        xOffset += 48
        
        // Category buttons
        for (index, category) in availableCategories.enumerated() {
            let button = NSButton()
            button.title = category
            button.bezelStyle = .rounded
            button.isBordered = true
            button.target = self
            button.action = #selector(selectCategory(_:))
            button.tag = index
            
            let buttonWidth = max(60, category.count * 8 + 16)
            button.frame = NSRect(x: xOffset, y: 5, width: CGFloat(buttonWidth), height: buttonHeight)
            button.bezelColor = selectedCategories.contains(category) ? .controlAccentColor : .clear
            
            containerView.addSubview(button)
            xOffset += CGFloat(buttonWidth) + 8
        }
        
        // Set container size
        containerView.frame = NSRect(x: 0, y: 0, width: xOffset, height: 30)
        
        // Configure scroll view
        scrollView.documentView = containerView
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 30)
        
        item.view = scrollView
        return item
    }
    
    private func makeSortButton() -> NSTouchBarItem {
        let item = NSButtonTouchBarItem(identifier: .mediaListSortButton)
        item.image = NSImage(systemSymbolName: "arrow.up.arrow.down.circle", accessibilityDescription: "Sort")
        item.target = self
        item.action = #selector(showSortOptions)
        return item
    }
    
    private func makeRefreshButton() -> NSTouchBarItem {
        let item = NSButtonTouchBarItem(identifier: .mediaListRefreshButton)
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        item.target = self
        item.action = #selector(refreshContent)
        item.isEnabled = !isRefreshing
        return item
    }
    
    // MARK: - Actions
    
    @objc private func handleSearch(_ sender: NSSearchField) {
        onSearchChange(sender.stringValue)
    }
    
    @objc private func selectAllCategories() {
        onCategoryToggle("")
    }
    
    @objc private func selectCategory(_ sender: NSButton) {
        let categoryIndex = sender.tag
        if categoryIndex < availableCategories.count {
            let category = availableCategories[categoryIndex]
            onCategoryToggle(category)
        }
    }
    
    @objc private func showSortOptions() {
        // Sort options implementation
        MKSLog.app.debug("Show sort options")
    }
    
    @objc private func refreshContent() {
        onRefresh()
    }
}

// MARK: - TouchBar Item Identifiers Extension

extension NSTouchBarItem.Identifier {
    static let mediaListSearchField = NSTouchBarItem.Identifier("com.mks.iptv.mediaList.searchField")
    static let mediaListCategoriesScrollView = NSTouchBarItem.Identifier("com.mks.iptv.mediaList.categoriesScrollView")
    static let mediaListSortButton = NSTouchBarItem.Identifier("com.mks.iptv.mediaList.sortButton")
    static let mediaListRefreshButton = NSTouchBarItem.Identifier("com.mks.iptv.mediaList.refreshButton")
}

// MARK: - Preview

struct MediaListTouchBarView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Media list with categories
            MediaListTouchBarView(
                searchText: "",
                availableCategories: [
                    "Action", "Adventure", "Animation", "Comedy", "Crime", 
                    "Documentary", "Drama", "Family", "Fantasy", "Horror",
                    "Music", "Mystery", "Romance", "Sci-Fi", "Thriller"
                ],
                selectedCategories: [],
                isRefreshing: false,
                contentType: .all,
                onSearchChange: { _ in print("Search changed") },
                onCategoryToggle: { _ in print("Category toggled") },
                onRefresh: { print("Refresh tapped") }
            )
            .previewDisplayName("All Categories")
            
            // With selected categories
            MediaListTouchBarView(
                searchText: "Marvel",
                availableCategories: [
                    "Action", "Adventure", "Animation", "Comedy", "Crime", 
                    "Documentary", "Drama", "Family", "Fantasy", "Horror"
                ],
                selectedCategories: ["Action", "Adventure"],
                isRefreshing: false,
                contentType: .movies,
                onSearchChange: { _ in print("Search changed") },
                onCategoryToggle: { _ in print("Category toggled") },
                onRefresh: { print("Refresh tapped") }
            )
            .previewDisplayName("Selected Categories")
            
            // Refreshing state
            MediaListTouchBarView(
                searchText: "",
                availableCategories: ["Drama", "Comedy", "Action"],
                selectedCategories: [],
                isRefreshing: true,
                contentType: .series,
                onSearchChange: { _ in print("Search changed") },
                onCategoryToggle: { _ in print("Category toggled") },
                onRefresh: { print("Refresh tapped") }
            )
            .previewDisplayName("Refreshing")
            
            // Empty categories
            MediaListTouchBarView(
                searchText: "",
                availableCategories: [],
                selectedCategories: [],
                isRefreshing: false,
                contentType: .all,
                onSearchChange: { _ in print("Search changed") },
                onCategoryToggle: { _ in print("Category toggled") },
                onRefresh: { print("Refresh tapped") }
            )
            .previewDisplayName("Loading Categories")
            
            // Many categories (scroll test)
            MediaListTouchBarView(
                searchText: "",
                availableCategories: [
                    "Action", "Adventure", "Animation", "Biography", "Comedy", "Crime",
                    "Documentary", "Drama", "Family", "Fantasy", "Film-Noir", "History",
                    "Horror", "Music", "Musical", "Mystery", "News", "Romance",
                    "Sci-Fi", "Short", "Sport", "Thriller", "War", "Western"
                ],
                selectedCategories: ["Action", "Sci-Fi", "Thriller"],
                isRefreshing: false,
                contentType: .all,
                onSearchChange: { _ in print("Search changed") },
                onCategoryToggle: { _ in print("Category toggled") },
                onRefresh: { print("Refresh tapped") }
            )
            .previewDisplayName("Many Categories")
        }
        .frame(width: 750, height: 30)
        .background(Color.black.opacity(0.8))
    }
}
#endif
