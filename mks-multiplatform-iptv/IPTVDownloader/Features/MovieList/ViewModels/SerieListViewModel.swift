import Foundation

@MainActor
class SerieListViewModel: ObservableObject {
    @Published private(set) var series: [Serie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let movieService: MovieService
    private var didLoadSeries = false
    
    init(movieService: MovieService) {
        self.movieService = movieService
    }
    
    func loadSeries() async {
        guard !didLoadSeries else { return }
        
        isLoading = true
        error = nil
        
        do {
            series = try await movieService.fetchSeries()
            series = orderByAddedDesc(series) // Apply default sorting
            didLoadSeries = true
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func refreshSeries() async {
        didLoadSeries = false
        await loadSeries()
    }
    
    func filterSeries(searchText: String) -> [Serie] {
        guard !searchText.isEmpty else { return series }
        return series.filter { serie in
            serie.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func getSerie(by id: Int) -> Serie? {
        return series.first { $0.id == id }
    }
    
    // New sorting methods
    
    func orderByNameAlphabeticallyAsc(_ series: [Serie]) -> [Serie] {
        return series.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    func orderByNameAlphabeticallyDesc(_ series: [Serie]) -> [Serie] {
        return series.sorted { $0.name.lowercased() > $1.name.lowercased() }
    }
    
    func orderByAddedAsc(_ series: [Serie]) -> [Serie] {
        return series.sorted { (s1: Serie, s2: Serie) -> Bool in
            guard let date1 = Double(s1.lastModified), let date2 = Double(s2.lastModified) else {
                return false
            }
            return date1 < date2
        }
    }

    func orderByAddedDesc(_ series: [Serie]) -> [Serie] {
        return series.sorted { (s1: Serie, s2: Serie) -> Bool in
            guard let date1 = Double(s1.lastModified), let date2 = Double(s2.lastModified) else {
                return false
            }
            return date1 > date2
        }
    }

    func loadExampleSeries(_ series: [Serie]) {
        self.series = series
    }
    
    // Method to apply a specific sorting
    func applySort(_ sortMethod: ([Serie]) -> [Serie]) {
        series = sortMethod(series)
    }
}
