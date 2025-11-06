import Foundation
@MainActor
class MovieListViewModel: ObservableObject {
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    private var didLoadMovies = false
    
    private let movieService: MovieService
    
    init(movieService: MovieService) {
        self.movieService = movieService
    }
    
    func loadMovies(categoryId: String? = nil) async {
        isLoading = true
        error = nil
        
        do {
            movies = try await movieService.fetchMovies()
            movies = orderByAddedDesc(movies) // Aplicar el filtro por defecto
            didLoadMovies = true
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func refreshMovies(categoryId: String? = nil) async {
        didLoadMovies = false
        await loadMovies(categoryId: categoryId)
    }
    
    func filterMovies(searchText: String) -> [Movie] {
        guard !searchText.isEmpty else { return movies }
        return movies.filter { movie in
            movie.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Nuevos métodos de ordenación
    
    func orderByNameAlphabeticallyAsc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func orderByNameAlphabeticallyDesc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted { $0.name.lowercased() > $1.name.lowercased() }
    }
    
    func orderByAddedAsc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted {
            guard let date1 = Double($0.added ?? "0"), let date2 = Double($1.added ?? "0") else {
                return false
            }
            return date1 < date2
        }
    }
    
    func orderByAddedDesc(_ movies: [Movie]) -> [Movie] {
        return movies.sorted {
            guard let date1 = Double($0.added ?? "0"), let date2 = Double($1.added ?? "0") else {
                return false
            }
            return date1 > date2
        }
    }
    func loadExampleMovies(_ movies: [Movie]) {
        self.movies = movies
    }
    // Método para aplicar un ordenamiento específico
    func applySort(_ sortMethod: ([Movie]) -> [Movie]) {
        movies = sortMethod(movies)
    }
}
