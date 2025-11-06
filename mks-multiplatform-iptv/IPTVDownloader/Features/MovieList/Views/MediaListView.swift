import SwiftUI
#if os(iOS)
import UIKit
#endif


struct MediaListView: View {
    // MARK: - Properties
    
    @ObservedObject var viewModel: MediaListViewModel
    @State private var movieDetailViewModel: MovieDetailViewModel?
    @State private var serieDetailViewModel: SerieDetailViewModel?
    
    // Computed services based on environment profile
    private var movieService: MovieService {
        MovieService(profile: profile)
    }
    
    @EnvironmentObject private var profile: IPTVProfile
    @State private var searchText = ""
    @State private var selectedMediaItemId: Int?
    @Binding var selectedView: String?
    @State private var selectedCategories: Set<String> = []
    @State private var sortOption: MediaListViewModel.SortOption = .addedDesc
    @State private var contentTypeFilter: MediaListViewModel.ContentType = .all
    @State private var showingFullScreenDetail = false
    @State private var isLoadingDetail = false
    @State private var showFilterMenu = false
    
    
    #if os(macOS)
    @EnvironmentObject var touchBarManager: TouchBarManager
    #endif
    
    let movieCategories: [MovieCategory]
    let seriesCategories: [SeriesCategory]
    let showContentTypeSelector: Bool
    
    @Namespace private var animation
    
    // Platform-specific layout constants
    #if os(iOS)
    private let cardMinWidth: CGFloat = 150
    private let cardMaxWidth: CGFloat = 190
    private let gridSpacing: CGFloat = 16
    private let categoryChipMinWidth: CGFloat = 100
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 8
    #else
    private let cardMinWidth: CGFloat = 160
    private let cardMaxWidth: CGFloat = 220
    private let gridSpacing: CGFloat = 20
    private let categoryChipMinWidth: CGFloat = 150
    private let horizontalPadding: CGFloat = 24
    private let verticalPadding: CGFloat = 16
    #endif
    
    
    // MARK: - Initialization
    
    init(viewModel: MediaListViewModel,
         selectedView: Binding<String?>,
         movieCategories: [MovieCategory] = [],
         seriesCategories: [SeriesCategory] = [],
         initialContentType: MediaListViewModel.ContentType = .all,
         showContentTypeSelector: Bool = true) {
        self.viewModel = viewModel
        self._selectedView = selectedView
        self.movieCategories = movieCategories
        self.seriesCategories = seriesCategories
        self._contentTypeFilter = State(initialValue: initialContentType)
        self.showContentTypeSelector = showContentTypeSelector
    }
    
    // MARK: - View Components para el Body
    
    // Background View
    private var backgroundView: some View {
        ZStack {
            Image("backgroundPattern")
                .resizable()            .aspectRatio(contentMode: .fill)  // This will make it fill the space while maintaining aspect ratio
                .ignoresSafeArea()
                
                
            VisualEffect(blurStyle: .dark,
                         vibrancy: true, cornerRadius: 0,
                         opacity: 0.35).ignoresSafeArea(edges: .all)
        }
    }
    
    // Main Content Container
    private var mainContentContainer: some View {
        VStack(spacing: 0) {
            #if os(macOS)
            // Add spacer to push content below toolbar on macOS
            Color.clear
                .frame(height: 100)
            #endif
            
            // Categories indicator section
            categoriesIndicatorSection
            
            // Content type selector section
            contentTypeSelectorSection
            
            // Main content or state views
            mainContentOrStateViews
        }
        #if os(macOS)
        .frame(maxHeight: .infinity)
        #endif
    }
    
    // Categories Indicator Section
    private var categoriesIndicatorSection: some View {
        Group {
            if !selectedCategories.isEmpty {
                selectedCategoriesIndicator
                    .padding(.horizontal)
                    .padding(.top, 4) // Reduce top padding
                    .padding(.bottom, 2) // Reduce bottom padding
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // Content Type Selector Section
    private var contentTypeSelectorSection: some View {
        Group {
            if showContentTypeSelector {
                contentTypeSelector
                    .background(
                        VisualEffect(blurStyle: .dark, vibrancy: true, cornerRadius: 16, opacity: 0.9)
                    )
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
    }
    
    // Main Content or State Views
    private var mainContentOrStateViews: some View {
        Group {
            if !viewModel.isLoading && viewModel.error == nil && !filteredContent.isEmpty {
                contentScrollView
            } else {
                stateViews
            }
        }
    }
    
    // Content using universal grid container
    private var contentScrollView: some View {
        MediaGridContainer(
            content: {
                Group {
                    // Movie cards
                    if contentTypeFilter == .all || contentTypeFilter == .movies {
                        moviesContent
                    }
                    
                    // Series cards  
                    if contentTypeFilter == .all || contentTypeFilter == .series {
                        seriesContent
                    }
                }
            },
            isEmpty: filteredContent.isEmpty,
            isLoading: viewModel.isLoading,
            error: viewModel.error,
            onRetry: {
                Task {
                    await viewModel.refreshMedia(contentType: contentTypeFilter)
                }
            }
        )
        .refreshable {
            await viewModel.refreshMedia(contentType: contentTypeFilter)
        }
    }
    
    
    // Corregir las propiedades computadas moviesContent y seriesContent para macOS
    // Asegurarse de que estas modificaciones reemplacen el código existente

    // Propiedad computada para el contenido de películas
    private var moviesContent: some View {
        ForEach(filteredMovies) { movie in
            #if os(iOS)
            PlatformSpecificMovieCardViewAdvanced(
                movie: movie,
                namespace: animation,
                onViewDetails: {
                    showMovieDetail(for: movie.streamId)
                }
            )
            .matchedGeometryEffect(id: "movie-\(movie.id)", in: animation)
            .accessibilityLabel("\(movie.name), Rating: \(movie.rating5Based?.formatted() ?? "N/A")")
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
            #else
            // macOS: Agregar un gesto de clic explícito
            PlatformSpecificMovieCardViewAdvanced(
                movie: movie,
                namespace: animation,
                onViewDetails: {
                    showMovieDetail(for: movie.streamId)
                }
            )
            .matchedGeometryEffect(id: "movie-\(movie.id)", in: animation)
            .accessibilityLabel("\(movie.name), Rating: \(movie.rating5Based?.formatted() ?? "N/A")")
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
            .onTapGesture {
                // Asegurarnos de que en macOS también se llame a showMovieDetail
                showMovieDetail(for: movie.streamId)
            }
            #endif
        }
    }

    // Propiedad computada para el contenido de series
    private var seriesContent: some View {
        ForEach(filteredSeries) { serie in
            #if os(iOS)
            PlatformSpecificSerieCardViewAdvanced(
                serie: serie,
                onViewDetails: {
                    showSerieDetail(for: serie)
                }
            )
            .matchedGeometryEffect(id: "serie-\(serie.id)", in: animation)
            .accessibilityLabel("\(serie.name), Category: \(serie.categoryId)")
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
            #else
            // macOS: Agregar un gesto de clic explícito
            PlatformSpecificSerieCardViewAdvanced(
                serie: serie,
                onViewDetails: {
                    showSerieDetail(for: serie)
                }
            )
            .matchedGeometryEffect(id: "serie-\(serie.id)", in: animation)
            .accessibilityLabel("\(serie.name), Category: \(serie.categoryId)")
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity),
                removal: .opacity
            ))
            .onTapGesture {
                // Asegurarnos de que en macOS también se llame a showSerieDetail
                showSerieDetail(for: serie)
            }
            #endif
        }
    }
    
    // State Views (Loading, Error, Empty)
    private var stateViews: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.error {
                errorView(error: error)
            } else if filteredContent.isEmpty {
                emptyStateView
            }
        }
        .transition(.opacity)
    }
    
    // Loading Detail Overlay
    private var detailLoadingOverlay: some View {
        Group {
            if isLoadingDetail && !showingFullScreenDetail {
                loadingDetailOverlay
                    .zIndex(200)
            }
        }
    }
    
    // iOS Toolbar Content - Liquid Glass Style
    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(navigationTitle)
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
        }
        
        ToolbarItemGroup(placement: .topBarTrailing) {
            // Sort button
            Menu {
                Button("Name A-Z") { 
                    applySortOption(.nameAsc)
                }
                Button("Name Z-A") { 
                    applySortOption(.nameDesc)
                }
                Button("Newest First") { 
                    applySortOption(.addedDesc)
                }
                Button("Oldest First") { 
                    applySortOption(.addedAsc)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            
            // Filter button
            Button(action: { showFilterMenu.toggle() }) {
                Image(systemName: selectedCategories.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            
            // Removed ToolbarSpacer() line as per instructions
            
            // Refresh button as special action
            Button(action: {
                Task {
                    await viewModel.refreshMedia(contentType: contentTypeFilter)
                }
            }) {
                Image(systemName: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(viewModel.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
            }
            .disabled(viewModel.isRefreshing || viewModel.isLoading)
        }
    }
    #endif
    
    // macOS Toolbar Content
    #if os(macOS)
    @ToolbarContentBuilder
    private var macOSToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(navigationTitle)
                .font(.headline.weight(.semibold))
                .foregroundColor(.primary)
        }
        
        ToolbarItemGroup(placement: .primaryAction) {
            // Sort button
            Menu {
                Button("Name A-Z") { 
                    applySortOption(.nameAsc)
                }
                Button("Name Z-A") { 
                    applySortOption(.nameDesc)
                }
                Button("Newest First") { 
                    applySortOption(.addedDesc)
                }
                Button("Oldest First") { 
                    applySortOption(.addedAsc)
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            
            // Filter button
            Menu {
                if !movieCategories.isEmpty {
                    Section("Movie Categories") {
                        ForEach(movieCategories, id: \.categoryId) { movieCategory in
                            Button(action: {
                                toggleCategory(movieCategory.categoryId)
                            }) {
                                HStack {
                                    Text(movieCategory.categoryName)
                                    if selectedCategories.contains(movieCategory.categoryId) {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                if !seriesCategories.isEmpty {
                    Section("Series Categories") {
                        ForEach(seriesCategories, id: \.categoryId) { seriesCategory in
                            Button(action: {
                                toggleCategory(seriesCategory.categoryId)
                            }) {
                                HStack {
                                    Text(seriesCategory.categoryName)
                                    if selectedCategories.contains(seriesCategory.categoryId) {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
                
                if !selectedCategories.isEmpty {
                    Divider()
                    Button("Clear All Filters") {
                        withAnimation {
                            selectedCategories.removeAll()
                        }
                    }
                }
            } label: {
                Image(systemName: selectedCategories.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            
            // Refresh button
            Button(action: {
                Task {
                    await viewModel.refreshMedia(contentType: contentTypeFilter)
                }
            }) {
                Image(systemName: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(viewModel.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isRefreshing)
            }
            .disabled(viewModel.isRefreshing || viewModel.isLoading)
        }
    }
    #endif
    
    // Filter Sheet Content
    #if os(iOS)
    private var filterSheet: some View {
        NavigationStack {
            List {
                if !movieCategories.isEmpty {
                    Section("Movie Categories") {
                        ForEach(movieCategories, id: \.categoryId) { movieCategory in
                            filterCategoryRow(
                                id: movieCategory.categoryId,
                                name: movieCategory.categoryName,
                                isSelected: selectedCategories.contains(movieCategory.categoryId)
                            )
                        }
                    }
                }
                if !seriesCategories.isEmpty {
                    Section("Series Categories") {
                        ForEach(seriesCategories, id: \.categoryId) { seriesCategory in
                            filterCategoryRow(
                                id: seriesCategory.categoryId,
                                name: seriesCategory.categoryName,
                                isSelected: selectedCategories.contains(seriesCategory.categoryId)
                            )
                        }
                    }
                }
                
                if !selectedCategories.isEmpty {
                    Section {
                        Button("Clear All Filters") {
                            withAnimation {
                                selectedCategories.removeAll()
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showFilterMenu = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func filterCategoryRow(id: String, name: String, isSelected: Bool) -> some View {
        Button(action: {
            toggleCategory(id)
        }) {
            HStack {
                Text(name)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
    #endif
    
    // Full Screen Cover Content
    #if os(iOS)
    private var fullScreenCoverContent: some View {
        Group {
            if selectedMediaItemId != nil {
                // Display movie detail
                if let movieDetailViewModel = movieDetailViewModel, 
                   let movieDetail = movieDetailViewModel.movieDetail {
                    PlatformSpecificAddDownloadViewMovie(
                        selectedView: $selectedView,
                        movieDetail: movieDetail,
                        onDismiss: dismissMediaDetail
                    )
                    .background(
                        VisualEffect(blurStyle: .systemUltraThinMaterial,
                                    cornerRadius: 0,
                                    opacity: 0.3).edgesIgnoringSafeArea(.all)
                    )
                }
                // Display serie detail
                else if let serieDetailViewModel = serieDetailViewModel,
                        let serieDetail = serieDetailViewModel.serieDetail {
                    PlatformSpecificAddDownloadViewSerie(
                        selectedView: $selectedView,
                        seriesDetail: serieDetail,
                        seriesId: selectedMediaItemId,
                        onDismiss: dismissMediaDetail
                    )
                    .background(
                        VisualEffect(blurStyle: .systemUltraThinMaterial,
                                    cornerRadius: 0,
                                    opacity: 0.3).edgesIgnoringSafeArea(.all)
                    )
                }
                // Fallback error view
                else {
                    errorDetailView
                }
            } else {
                errorDetailView
            }
        }
    }
    #endif
    #if os(macOS)
    private var macOSDetailContent: some View {
        Group {
            if selectedMediaItemId != nil {
                // Display movie detail
                if let movieDetailViewModel = movieDetailViewModel,
                   let movieDetail = movieDetailViewModel.movieDetail {
                PlatformSpecificAddDownloadViewMovie(
                    selectedView: $selectedView,
                    movieDetail: movieDetail,
                    onDismiss: dismissMediaDetail
                )
                .background(
                    VisualEffect(blurStyle: .dark,
                                 cornerRadius: 0,
                                 opacity: 0.3).edgesIgnoringSafeArea(.all)
                )
            }
            // Display serie detail
            else if let serieDetailViewModel = serieDetailViewModel,
                     let serieDetail = serieDetailViewModel.serieDetail {
                PlatformSpecificAddDownloadViewSerie(
                    selectedView: $selectedView,
                    seriesDetail: serieDetail,
                    seriesId: selectedMediaItemId,
                    onDismiss: dismissMediaDetail
                )
                .background(
                    VisualEffect(blurStyle: .dark,
                                 cornerRadius: 0,
                                 opacity: 0.3).edgesIgnoringSafeArea(.all)
                )
            }
            // Fallback error view
            else {
                errorDetailView
            }
        } else {
            errorDetailView
        }
    }
}
#endif

    // MARK: - Body
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            backgroundView
            
            // Main content
            mainContentContainer
            
            // Loading Details Overlay
            detailLoadingOverlay
        }
        #if os(iOS)
        // Native searchable modifier with Liquid Glass support
        .searchable(text: $searchText, prompt: "Search \(navigationPrompt)")
        // Liquid Glass toolbar - automatically adapts in iOS 26
        .toolbar {
            toolbarContent
        }
        #else
        // macOS toolbar configuration with search
        .searchable(text: $searchText, prompt: "Search \(navigationPrompt)")
        .toolbar {
            macOSToolbarContent
        }
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showingFullScreenDetail) {
            fullScreenCoverContent
        }
        .sheet(isPresented: $showFilterMenu) {
            filterSheet
        }
        #endif
#if os(macOS)
.sheet(isPresented: $showingFullScreenDetail) {
    macOSDetailContent
        .frame(minWidth: 800, minHeight: 600)
}
#endif
        #if os(macOS)
        // Sync internal changes to TouchBarManager
        .onChange(of: searchText) { newValue in
            print("[MediaListView] Internal searchText changed to: '\(newValue)'")
            touchBarManager.searchText = newValue
        }
        .onChange(of: selectedCategories) { newValue in
            print("[MediaListView] Internal selectedCategories changed to: \(newValue)")
            touchBarManager.selectedCategoryIDs = newValue
            // Update category names in TouchBarManager
            var categoryNames: Set<String> = []
            for categoryId in newValue {
                let name = getCategoryName(for: categoryId)
                categoryNames.insert(name)
            }
            touchBarManager.selectedCategories = categoryNames
        }
        // Sync TouchBarManager changes to internal state
        .onChange(of: touchBarManager.searchText) { newValue in
            print("[MediaListView] TouchBarManager searchText changed to: '\(newValue)'")
            if newValue != searchText {
                searchText = newValue
            }
        }
        .onChange(of: touchBarManager.selectedCategoryIDs) { newValue in
            print("[MediaListView] TouchBarManager selectedCategoryIDs changed to: \(newValue)")
            if newValue != selectedCategories {
                selectedCategories = newValue
            }
        }
        #endif
    }
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        switch contentTypeFilter {
        case .all: return "Media Library"
        case .movies: return "Movies"
        case .series: return "Series"
        }
    }
    
    private var navigationPrompt: String {
        switch contentTypeFilter {
        case .all: return "media"
        case .movies: return "movies"
        case .series: return "series"
        }
    }
    
    private var effectiveSearchText: String {
        return searchText
    }
    
    private var effectiveSelectedCategories: Set<String> {
        #if os(macOS)
        // Use TouchBar selected categories
        return touchBarManager.selectedCategoryIDs
        #else
        return selectedCategories
        #endif
    }
    
    private var filteredMovies: [Movie] {
        viewModel.filterMovies(searchText: effectiveSearchText, categoryIds: effectiveSelectedCategories)
    }
    
    private var filteredSeries: [Serie] {
        viewModel.filterSeries(searchText: effectiveSearchText, categoryIds: effectiveSelectedCategories)
    }
    
    private var filteredContent: [Any] {
        switch contentTypeFilter {
        case .all:
            return filteredMovies + filteredSeries
        case .movies:
            return filteredMovies
        case .series:
            return filteredSeries
        }
    }
    
    // Removed private var applicableCategories entirely per instructions

    // MARK: - View Components
    
    private var contentTypeSelector: some View {
        HStack(spacing: 0) {
            ContentTypeButton(
                title: "All",
                systemImage: "play.rectangle.on.rectangle.fill",
                isSelected: contentTypeFilter == .all,
                action: { selectContentType(.all) }
            )
            
            ContentTypeButton(
                title: "Movies",
                systemImage: "film.fill",
                isSelected: contentTypeFilter == .movies,
                action: { selectContentType(.movies) }
            )
            
            ContentTypeButton(
                title: "Series",
                systemImage: "tv.fill",
                isSelected: contentTypeFilter == .series,
                action: { selectContentType(.series) }
            )
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
    }

    // Visual indicator that shows which categories are selected
    private var selectedCategoriesIndicator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedCategories), id: \.self) { categoryId in
                    SelectedCategoryChip(
                        categoryId: categoryId,
                        categoryName: getCategoryName(for: categoryId),
                        onRemove: { toggleCategory(categoryId) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .background(
            VisualEffect(blurStyle: .dark, vibrancy: true, cornerRadius: 12, opacity: 0.25)
        )
    }

    // Chip component for selected categories
    private struct SelectedCategoryChip: View {
        let categoryId: String
        let categoryName: String
        let onRemove: () -> Void
        
        var body: some View {
            Button(action: onRemove) {
                HStack(spacing: 4) {
                    Text(categoryName)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.2))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // Helper function to get category name
    private func getCategoryName(for categoryId: String) -> String {
        if let category = movieCategories.first(where: { $0.categoryId == categoryId }) {
            return category.categoryName
        }
        if let category = seriesCategories.first(where: { $0.categoryId == categoryId }) {
            return category.categoryName
        }
        return categoryId
    }

    // MARK: - Loading and Error Views
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Loading \(navigationPrompt)...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2))
    }
    
    private func errorView(error: Error) -> some View {
        ErrorView(error: error, retryAction: {
            Task { await viewModel.refreshMedia(contentType: contentTypeFilter) }
        })
        .frame(maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: contentTypeFilter == .series ? "tv.slash" : "film.slash")
                .font(.system(size: 64))
                .foregroundColor(.white.opacity(0.7))
                .symbolEffect(.pulse)
            
            Text("No \(navigationTitle)")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            
            if !effectiveSearchText.isEmpty || !effectiveSelectedCategories.isEmpty {
                Text("Try adjusting your filters")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
                
                Button(action: {
                    searchText = ""
                    selectedCategories.removeAll()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Clear Filters")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.accentColor)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 20)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                }
                .padding(.top, 8)
            } else {
                Text("Your \(navigationPrompt) will appear here")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
    
    private var loadingDetailOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.8)
                    .tint(.white)
                
                Text("Loading details...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
    
    private var errorDetailView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
                
            Text("Failed to load details")
                .font(.title3.bold())
                .foregroundColor(.white)
                
            Text("There was a problem loading the content you requested.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Show error details if available
            if let movieError = movieDetailViewModel?.error {
                Text("Error: \(movieError.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            if let seriesError = serieDetailViewModel?.error {
                Text("Error: \(seriesError.localizedDescription)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Dismiss") {
                dismissMediaDetail()
            }
            .font(.headline)
            .foregroundColor(.black)
            .padding(.vertical, 12)
            .padding(.horizontal, 30)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        }
        .padding(40)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
    }
    
    // MARK: - Helper Methods
    
    private func showMovieDetail(for movieId: Int) {
        Task {
            await MainActor.run {
                selectedMediaItemId = movieId
                // Initialize ViewModels if needed
                initializeDetailViewModelsIfNeeded()
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoadingDetail = true
                }
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let movieDetailViewModel = movieDetailViewModel {
                await movieDetailViewModel.fetchMovieDetails(for: movieId)
            }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoadingDetail = false
                }
                
                // Show detail view even if there's an error (error view will be displayed)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingFullScreenDetail = true
                }
            }
        }
    }
    
    private func showSerieDetail(for serie: Serie) {
        Task {
            await MainActor.run {
                selectedMediaItemId = serie.id
                // Initialize ViewModels if needed
                initializeDetailViewModelsIfNeeded()
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoadingDetail = true
                }
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let serieDetailViewModel = serieDetailViewModel {
                await serieDetailViewModel.fetchSerieDetails(for: serie.id)
            }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isLoadingDetail = false
                }
                
                // Show detail view even if there's an error (error view will be displayed)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingFullScreenDetail = true
                }
            }
        }
    }
    
    @MainActor
    private func dismissMediaDetail() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            showingFullScreenDetail = false
            
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            selectedMediaItemId = nil
            isLoadingDetail = false
            movieDetailViewModel?.reset()
            serieDetailViewModel?.reset()
        }
    }
    
    private func selectContentType(_ type: MediaListViewModel.ContentType) {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            contentTypeFilter = type
            selectedCategories.removeAll()
            
            Task {
                await viewModel.loadMedia(contentType: type)
            }
        }
    }
    
    private func toggleCategory(_ categoryId: String) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedCategories.contains(categoryId) {
                selectedCategories.remove(categoryId)
            } else {
                selectedCategories.insert(categoryId)
            }
        }
    }
    
    private func applySortOption(_ option: MediaListViewModel.SortOption) {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sortOption = option
            viewModel.applySort(option, to: contentTypeFilter)
        }
    }
}

// MARK: - Supporting Components

extension MediaListView {
    struct ContentTypeButton: View {
        let title: String
        let systemImage: String
        let isSelected: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                .frame(minWidth: 80)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(
                    ZStack {
                        if isSelected {
                            Capsule()
                                .fill(Color.accentColor)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 5, x: 0, y: 3)
                        }
                    }
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                )
                .foregroundColor(isSelected ? .white : .primary)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }
    
    // Añadimos un estilo de botón personalizado para mejorar la respuesta táctil
    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
    
    // Modificador para efectos de símbolo
    struct SymbolEffectModifier: ViewModifier {
        let isSelected: Bool
        
        func body(content: Content) -> some View {
            if isSelected {
                content
                    .scaleEffect(1.2)
                    .animation(.easeInOut(duration: 0.2).repeatCount(1), value: UUID())
            } else {
                content
            }
        }
    }
    
    // MARK: - ViewModel Initialization
    
    @MainActor
    private func initializeDetailViewModelsIfNeeded() {
        if movieDetailViewModel == nil {
            movieDetailViewModel = MovieDetailViewModel(movieService: movieService)
        }
        if serieDetailViewModel == nil {
            serieDetailViewModel = SerieDetailViewModel(movieService: movieService)
        }
    }
}

// MARK: - Preview

// MARK: - Preview Support
// Note: MediaListView is too complex for SwiftUI previews due to app dependencies.
// Use the simulator or run on device for testing.




