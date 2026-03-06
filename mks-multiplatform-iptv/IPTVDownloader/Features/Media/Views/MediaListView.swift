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
    @State var searchText = ""
    @State private var selectedMediaItemId: Int?
    @Binding var selectedView: String?
    @State var selectedCategories: Set<String> = []
    @State var sortOption: MediaListViewModel.SortOption = .addedDesc
    @State var contentTypeFilter: MediaListViewModel.ContentType = .all
    @State private var showingFullScreenDetail = false
    @State private var isLoadingDetail = false
    @State private var showFilterMenu = false
    
    
    #if os(macOS)
    @EnvironmentObject var touchBarManager: TouchBarManager
    #endif
    
    let movieCategories: [MovieCategory]
    let seriesCategories: [SeriesCategory]
    let showContentTypeSelector: Bool
    let sidebarCategoryFilter: String?
    
    @Namespace private var animation
    
    // Platform-specific layout constants
    #if os(iOS)
    let cardMinWidth: CGFloat = 150
    let cardMaxWidth: CGFloat = 190
    let gridSpacing: CGFloat = 16
    let categoryChipMinWidth: CGFloat = 100
    let horizontalPadding: CGFloat = 16
    let verticalPadding: CGFloat = 8
    #else
    let cardMinWidth: CGFloat = 160
    let cardMaxWidth: CGFloat = 220
    let gridSpacing: CGFloat = 20
    let categoryChipMinWidth: CGFloat = 150
    let horizontalPadding: CGFloat = 24
    let verticalPadding: CGFloat = 16
    #endif
    
    
    // MARK: - Initialization
    
    init(viewModel: MediaListViewModel,
         selectedView: Binding<String?>,
         movieCategories: [MovieCategory] = [],
         seriesCategories: [SeriesCategory] = [],
         initialContentType: MediaListViewModel.ContentType = .all,
         showContentTypeSelector: Bool = true,
         sidebarCategoryFilter: String? = nil) {
        self.viewModel = viewModel
        self._selectedView = selectedView
        self.movieCategories = movieCategories
        self.seriesCategories = seriesCategories
        self._contentTypeFilter = State(initialValue: initialContentType)
        self.showContentTypeSelector = showContentTypeSelector
        self.sidebarCategoryFilter = sidebarCategoryFilter
        // Sync sidebar category filter into selectedCategories at init
        if let categoryId = sidebarCategoryFilter {
            self._selectedCategories = State(initialValue: [categoryId])
        }
    }
    
    // MARK: - View Components para el Body
    
    // Background View - Native gradient (no pattern image)
    private var backgroundView: some View {
        ZStack {
            // Native dark gradient background
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.03, green: 0.01, blue: 0.01),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Subtle accent glow at center
            RadialGradient(
                colors: [
                    Color(red: 0.863, green: 0.165, blue: 0.157).opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 100,
                endRadius: 500
            )
            .ignoresSafeArea()
        }
    }
    
    // Main Content Container
    private var mainContentContainer: some View {
        VStack(spacing: 0) {
            // Categories indicator section
            categoriesIndicatorSection

            // Content type selector section
            contentTypeSelectorSection

            // Main content or state views
            mainContentOrStateViews
        }
        .frame(maxHeight: .infinity)
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
    
    // Content Type Selector Section - Native pill picker
    private var contentTypeSelectorSection: some View {
        Group {
            if showContentTypeSelector {
                Picker("Content Type", selection: $contentTypeFilter) {
                    ForEach(MediaListViewModel.ContentType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .onChange(of: contentTypeFilter) { _, newType in
                    selectedCategories.removeAll()
                    Task {
                        await viewModel.loadMedia(contentType: newType)
                    }
                }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                namespace: animation,
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
                namespace: animation,
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
    
    // iOS Toolbar Content - Native Style
    #if os(iOS)
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(navigationTitle)
                .font(.headline.weight(.semibold))
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            // Sort menu
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

            // Refresh button
            Button(action: {
                Task {
                    await viewModel.refreshMedia(contentType: contentTypeFilter)
                }
            }) {
                Image(systemName: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    .symbolEffect(.rotate, options: .repeating.speed(1.5), isActive: viewModel.isRefreshing)
            }
            .disabled(viewModel.isRefreshing || viewModel.isLoading)
        }
    }
    #endif

    // macOS Toolbar Content - Native Style (NO duplicated search)
    #if os(macOS)
    @ToolbarContentBuilder
    private var macOSToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(navigationTitle)
                .font(.headline.weight(.semibold))
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Sort menu
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

            // Filter menu
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
                    .symbolEffect(.rotate, options: .repeating.speed(1.5), isActive: viewModel.isRefreshing)
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
    
    // Full Screen Cover Content — uses unified MediaDetailSheet
    #if os(iOS)
    private var fullScreenCoverContent: some View {
        Group {
            if selectedMediaItemId != nil {
                if let movieDetailViewModel = movieDetailViewModel,
                   let movieDetail = movieDetailViewModel.movieDetail {
                    MediaDetailSheet(
                        detail: movieDetail,
                        onDismiss: dismissMediaDetail,
                        selectedView: $selectedView
                    )
                } else if let serieDetailViewModel = serieDetailViewModel,
                          let serieDetail = serieDetailViewModel.serieDetail {
                    MediaDetailSheet(
                        detail: serieDetail,
                        onDismiss: dismissMediaDetail,
                        selectedView: $selectedView
                    )
                } else {
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
                if let movieDetailViewModel = movieDetailViewModel,
                   let movieDetail = movieDetailViewModel.movieDetail {
                    MediaDetailSheet(
                        detail: movieDetail,
                        onDismiss: dismissMediaDetail,
                        selectedView: $selectedView
                    )
                } else if let serieDetailViewModel = serieDetailViewModel,
                          let serieDetail = serieDetailViewModel.serieDetail {
                    MediaDetailSheet(
                        detail: serieDetail,
                        onDismiss: dismissMediaDetail,
                        selectedView: $selectedView
                    )
                } else {
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
            // Background - skip on macOS to preserve native sidebar/toolbar materials
            #if !os(macOS)
            backgroundView
            #endif

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
        .onChange(of: searchText) { _, newValue in
            print("[MediaListView] Internal searchText changed to: '\(newValue)'")
            touchBarManager.searchText = newValue
        }
        .onChange(of: selectedCategories) { _, newValue in
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
        .onChange(of: touchBarManager.searchText) { _, newValue in
            print("[MediaListView] TouchBarManager searchText changed to: '\(newValue)'")
            if newValue != searchText {
                searchText = newValue
            }
        }
        .onChange(of: touchBarManager.selectedCategoryIDs) { _, newValue in
            print("[MediaListView] TouchBarManager selectedCategoryIDs changed to: \(newValue)")
            if newValue != selectedCategories {
                selectedCategories = newValue
            }
        }
        .onChange(of: sidebarCategoryFilter) { _, newValue in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if let categoryId = newValue {
                    selectedCategories = [categoryId]
                } else {
                    selectedCategories.removeAll()
                }
            }
        }
        #endif
    }
    
    // MARK: - Computed Properties

    var navigationTitle: String {
        switch contentTypeFilter {
        case .all: return "Media Library"
        case .movies: return "Movies"
        case .series: return "Series"
        }
    }

    var navigationPrompt: String {
        switch contentTypeFilter {
        case .all: return "media"
        case .movies: return "movies"
        case .series: return "series"
        }
    }

    var effectiveSearchText: String {
        return searchText
    }

    var effectiveSelectedCategories: Set<String> {
        #if os(macOS)
        // Use TouchBar selected categories
        return touchBarManager.selectedCategoryIDs
        #else
        return selectedCategories
        #endif
    }

    var filteredMovies: [Movie] {
        viewModel.filterMovies(searchText: effectiveSearchText, categoryIds: effectiveSelectedCategories)
    }

    var filteredSeries: [Serie] {
        viewModel.filterSeries(searchText: effectiveSearchText, categoryIds: effectiveSelectedCategories)
    }

    var filteredContent: [Any] {
        switch contentTypeFilter {
        case .all:
            return filteredMovies + filteredSeries
        case .movies:
            return filteredMovies
        case .series:
            return filteredSeries
        }
    }

    // Visual indicator that shows which categories are selected - native style
    private var selectedCategoriesIndicator: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedCategories), id: \.self) { categoryId in
                    Button(action: { toggleCategory(categoryId) }) {
                        HStack(spacing: 4) {
                            Text(getCategoryName(for: categoryId))
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.secondary.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
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

    // MARK: - Helper Methods

    func showMovieDetail(for movieId: Int) {
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
    
    func showSerieDetail(for serie: Serie) {
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
    func dismissMediaDetail() {
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




