//
//  TestViews.swift
//  mks-multiplatform-iptv
//
//  Unified test views for grid layout and media list preview testing
//

import SwiftUI

// MARK: - Mock Data
struct MockData {
    static let movies = [
        Movie(name: "Casino", streamType: "movie", streamId: 1, streamIcon: "https://cdn11.bigcommerce.com/s-yzgoj/images/stencil/500x659/products/2891345/5947614/MOVCF5676__59910.1679593031.jpg", rating: "7.8", rating5Based: 4.0, added: "2021-05-01", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Goodfellas", streamType: "movie", streamId: 2, streamIcon: "https://m.media-amazon.com/images/M/MV5BY2NkZjEzMDgtN2RjYy00YzM1LWI4ZmQtMjA4YWI5NzQ3YzY2XkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "8.7", rating5Based: 4.3, added: "2021-05-02", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Scarface", streamType: "movie", streamId: 3, streamIcon: "https://m.media-amazon.com/images/M/MV5BM2MyNjYxNmUtYTAwNi00MTYxLWJmNWYtYzZlODY3ZTk3OTFlXkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "8.3", rating5Based: 4.1, added: "2021-05-03", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "The Godfather", streamType: "movie", streamId: 4, streamIcon: "https://m.media-amazon.com/images/M/MV5BM2MyNjYxNmUtYTAwNi00MTYxLWJmNWYtYzZlODY3ZTk3OTFlXkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "9.2", rating5Based: 4.6, added: "2021-05-04", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Pulp Fiction", streamType: "movie", streamId: 5, streamIcon: "https://m.media-amazon.com/images/M/MV5BNGNhMDIzZTUtNTBlZi00MTRlLWFjM2ItYzViMjE3YzI5MjljXkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "8.9", rating5Based: 4.4, added: "2021-05-05", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "The Departed", streamType: "movie", streamId: 6, streamIcon: "https://m.media-amazon.com/images/M/MV5BMTI1MTY2OTIxNV5BMl5BanBnXkFtZTYwNjQ4NjY3._V1_.jpg", rating: "8.5", rating5Based: 4.2, added: "2021-05-06", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Heat", streamType: "movie", streamId: 7, streamIcon: "https://m.media-amazon.com/images/M/MV5BNDc0YjdmN2YtNzJhZC00OTdlLTllYjUtNGNjMTgxZDM4NjJjXkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "8.2", rating5Based: 4.1, added: "2021-05-07", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "The Wolf of Wall Street", streamType: "movie", streamId: 8, streamIcon: "https://m.media-amazon.com/images/M/MV5BMjIxMjgxNTk0MF5BMl5BanBnXkFtZTgwNjIyOTg2MDE@._V1_.jpg", rating: "8.2", rating5Based: 4.1, added: "2021-05-08", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Taxi Driver", streamType: "movie", streamId: 9, streamIcon: "https://m.media-amazon.com/images/M/MV5BM2M1MmVhNDgtNmI0YS00ZDNmLTkyNjctNTJiYTQ2N2NmYzc2XkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "8.2", rating5Based: 4.1, added: "2021-05-09", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Raging Bull", streamType: "movie", streamId: 10, streamIcon: "https://m.media-amazon.com/images/M/MV5BYjRmODkzNDItMTNhNi00YjJlLTg0ZjAtODlhZGI2YWNmMGI1XkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "8.2", rating5Based: 4.1, added: "2021-05-10", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "Mean Streets", streamType: "movie", streamId: 11, streamIcon: "https://m.media-amazon.com/images/M/MV5BMTYzODE3MjMtYzgwOC00ZWE2LTliNTMtN2I2NmFmNmQzNTYzXkEyXkFqcGdeQXVyNzkwMjQ5NzM@._V1_.jpg", rating: "7.2", rating5Based: 3.6, added: "2021-05-11", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: ""),
        Movie(name: "The Irishman", streamType: "movie", streamId: 12, streamIcon: "https://m.media-amazon.com/images/M/MV5BMGUyM2ZiZmUtMWY0OC00NTQ4LThkOGUtNjY2NjkzMDJiMWMwXkEyXkFqcGdeQXVyMzY0MTE3NzU@._V1_.jpg", rating: "7.8", rating5Based: 3.9, added: "2021-05-12", isAdult: "0", categoryId: "1", containerExtension: "mp4", customSid: "", directSource: "")
    ]
    
    static let movieCategories = [
        MovieCategory(categoryId: "1", categoryName: "Crime", parentId: 0),
        MovieCategory(categoryId: "2", categoryName: "Action", parentId: 0),
        MovieCategory(categoryId: "3", categoryName: "Drama", parentId: 0)
    ]
    
    static let seriesCategories = [
        SeriesCategory(categoryId: "10", categoryName: "Crime Series", parentId: 0),
        SeriesCategory(categoryId: "11", categoryName: "Drama Series", parentId: 0)
    ]
}

// MARK: - Mock ViewModel
class MockMediaListViewModel: MediaListViewModel {
    override init(movieService: MovieService) {
        super.init(movieService: movieService)
        loadExampleMovies(MockData.movies)
    }
    
    // Convenience initializer for tests with mock profile
    convenience init() {
        let mockProfile = IPTVProfile(name: "Mock", baseURL: "http://mock.com", username: "test", password: "test")
        let mockService = MovieService(profile: mockProfile)
        self.init(movieService: mockService)
    }
    
    override func loadMedia(contentType: ContentType = .all, categoryId: String? = nil, forceRefresh: Bool = false) async {
        loadExampleMovies(MockData.movies)
    }
    
    override func refreshMedia(contentType: ContentType = .all, categoryId: String? = nil) async {
        // Override to prevent network calls
    }
}

// MARK: - Simple Grid Layout Test
struct SimpleGridLayoutTest: View {
    // Platform-specific layout constants
    #if os(iOS)
    private let cardMinWidth: CGFloat = 150
    private let gridSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 8
    #else
    private let cardMinWidth: CGFloat = 160
    private let gridSpacing: CGFloat = 20
    private let horizontalPadding: CGFloat = 24
    private let verticalPadding: CGFloat = 16
    #endif
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: .infinity),
                 spacing: gridSpacing, alignment: .top)]
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                #if os(macOS)
                // Top spacer for macOS toolbar
                Color.clear
                    .frame(height: 100)
                #endif
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(0..<12, id: \.self) { index in
                            SimpleCardView(index: index)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    #if os(macOS)
                    .padding(.top, 30)
                    .padding(.bottom, verticalPadding)
                    #else
                    .padding(.vertical, verticalPadding)
                    #endif
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Simple Grid Test")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Simple Grid Test")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
            }
        }
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Simple Card View
struct SimpleCardView: View {
    let index: Int
    private let colors: [Color] = [.blue, .green, .red, .orange, .purple, .pink]
    
    var body: some View {
        Rectangle()
            .fill(colors[index % colors.count].opacity(0.7))
            .aspectRatio(2/3, contentMode: .fit)
            .overlay(
                VStack {
                    Text("Card \(index + 1)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Row: \(index / 4 + 1)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
            )
            .cornerRadius(12)
            .shadow(radius: 4)
    }
}

// MARK: - Media List Test with Real Cards
struct MediaListTestView: View {
    @StateObject private var mockViewModel = MockMediaListViewModel()
    @State private var selectedView: String? = "Movies"
    @Namespace private var animation
    
    // Platform-specific layout constants
    #if os(iOS)
    private let cardMinWidth: CGFloat = 150
    private let gridSpacing: CGFloat = 16
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 8
    #else
    private let cardMinWidth: CGFloat = 160
    private let gridSpacing: CGFloat = 20
    private let horizontalPadding: CGFloat = 24
    private let verticalPadding: CGFloat = 16
    #endif
    
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: cardMinWidth, maximum: .infinity),
                 spacing: gridSpacing, alignment: .top)]
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            // Background
            backgroundView
            
            VStack(spacing: 0) {
                #if os(macOS)
                Color.clear
                    .frame(height: 100)
                #endif
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: gridSpacing) {
                        ForEach(MockData.movies, id: \.streamId) { movie in
                            MovieCardView(movie: movie, namespace: animation)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    #if os(macOS)
                    .padding(.top, 30)
                    .padding(.bottom, verticalPadding)
                    #else
                    .padding(.vertical, verticalPadding)
                    #endif
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Movies")
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Text("Movies")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
            }
        }
        #else
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            Task {
                await mockViewModel.loadMedia(contentType: .movies)
            }
        }
    }
    
    private var backgroundView: some View {
        ZStack {
            Image("backgroundPattern")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                
            VisualEffect(blurStyle: .dark,
                         vibrancy: true, cornerRadius: 0,
                         opacity: 0.35).ignoresSafeArea(edges: .all)
        }
    }
}

// MARK: - Full Media List View Test
struct FullMediaListViewTest: View {
    @StateObject private var mockViewModel = MockMediaListViewModel()
    @State private var selectedView: String? = "Movies"
    
    var body: some View {
        MediaListView(
            viewModel: mockViewModel,
            selectedView: $selectedView,
            movieCategories: MockData.movieCategories,
            seriesCategories: MockData.seriesCategories,
            initialContentType: .movies,
            showContentTypeSelector: true
        )
        .onAppear {
            Task {
                await mockViewModel.loadMedia(contentType: .movies)
            }
        }
    }
}

// MARK: - Preview Provider
struct TestViews_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Simple Grid Layout Tests
            NavigationStack {
                SimpleGridLayoutTest()
            }
            .previewDisplayName("Simple Grid - Standard")
            .frame(width: 1200, height: 800)
            
            NavigationStack {
                SimpleGridLayoutTest()
            }
            .previewDisplayName("Simple Grid - Wide")
            .frame(width: 1600, height: 900)
            
            // Media List with Real Cards
            NavigationStack {
                MediaListTestView()
            }
            .previewDisplayName("Media Cards - Standard")
            .frame(width: 1200, height: 800)
            
            NavigationStack {
                MediaListTestView()
            }
            .previewDisplayName("Media Cards - Wide")
            .frame(width: 1600, height: 900)
            
            // Full Media List View
            NavigationStack {
                FullMediaListViewTest()
            }
            .previewDisplayName("Full Media List")
            .frame(width: 1200, height: 800)
        }
        .preferredColorScheme(.dark)
    }
}