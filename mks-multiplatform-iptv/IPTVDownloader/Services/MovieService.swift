import Foundation

// NOTE: This service must always use the currently active profile.
actor MovieService {
    private let session: URLSession
    let profile: IPTVProfile
    
    init(profile: IPTVProfile, session: URLSession = .shared) {
        self.profile = profile
        self.session = session
    }
    
    func fetchMovies() async throws -> [Movie] {
        return try await fetchMovies(page: nil)
    }
    
    func fetchMovies(page: Int? = nil) async throws -> [Movie] {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_vod_streams")
        ]
        
        let request = URLRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode([Movie].self, from: data)
    }
    
    func fetchMovieDetails(movieId: Int) async throws -> MovieDetail {
        return try await fetchMovieDetails(vodId: movieId)
    }
    
    func fetchMovieDetails(vodId: Int) async throws -> MovieDetail {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_vod_info"),
            URLQueryItem(name: "vod_id", value: String(vodId))
        ]
        
        // Log URL and parameters
        print("Request URL: \(components.url?.absoluteString ?? "Invalid URL")")
        print("Query Items: \(components.queryItems ?? [])")
        
        let request = URLRequest(url: components.url!)
        
        // Log request details
        print("Request: \(request)")
        
        // Perform request and log response details
        let (data, response) = try await session.data(for: request)
        
        // Convert and log the data as a string
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw data response as String: \(dataString)")
        } else {
            print("Failed to decode data to String")
        }
        
        // Log HTTP response status code
        if let httpResponse = response as? HTTPURLResponse {
            print("HTTP Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                throw APIError.invalidResponse
            }
        } else {
            print("Invalid HTTP response")
            throw APIError.invalidResponse
        }
        
        // Decode response and return
        do {
            // Decode response and return
            let movieDetail = try JSONDecoder().decode(MovieDetail.self, from: data)
            
            // Log the successfully decoded MovieDetail object
            print("Decoded Movie Detail: \(movieDetail)")
            return movieDetail
        } catch let decodingError as DecodingError {
            // Handle specific decoding errors
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("Type mismatch for type \(type) in context: \(context)")
            case .valueNotFound(let value, let context):
                print("Value not found for \(value) in context: \(context)")
            case .keyNotFound(let key, let context):
                print("Key not found for \(key) in context: \(context)")
            case .dataCorrupted(let context):
                print("Data corrupted in context: \(context)")
            @unknown default:
                print("Unknown decoding error: \(decodingError)")
            }
        } catch {
            // Handle any other errors that are not related to decoding
            print("Unexpected error while decoding MovieDetail: \(error)")
            throw error
        }
        
        // Throw an error if decoding fails, ensuring a return in all paths
        throw APIError.decodingError
    }

    // Fetch series categories
    func fetchMovieCategories() async throws -> [MovieCategory] {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_vod_categories")
        ]
        
        let request = URLRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode([MovieCategory].self, from: data)
    }
    // Fetch movies categories
    func fetchSeriesCategories() async throws -> [SeriesCategory] {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_series_categories")
        ]
        
        let request = URLRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode([SeriesCategory].self, from: data)
    }
    // fetch live channel categories
    func fetchLiveChannelsCategories() async throws -> [LiveChannelCategory] {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_live_categories")
        ]
        
        let request = URLRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode([LiveChannelCategory].self, from: data)
    }

    // Fetch series
    func fetchSeries() async throws -> [Serie] {
        return try await fetchSeries(page: nil)
    }
    
    func fetchSeries(page: Int? = nil) async throws -> [Serie] {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_series")
        ]
        
        let request = URLRequest(url: components.url!)
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
        
        return try JSONDecoder().decode([Serie].self, from: data)
    }
    
    // Fetch live channels
    func fetchLiveChannels() async throws -> [LiveChannel] {
        print("🚀 MovieService: Starting live channels fetch...")
        print("📍 Server URL: \(profile.baseURL)")
        
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_live_streams")
        ]
        
        guard let url = components.url else {
            print("❌ Invalid URL components")
            throw APIError.invalidURL
        }
        
        print("🌐 Request URL: \(url)")
        let request = URLRequest(url: url)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid HTTP response")
                throw APIError.invalidResponse
            }
            
            print("📊 HTTP Status Code: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                print("❌ HTTP Error: \(httpResponse.statusCode)")
                throw APIError.invalidResponse
            }
            
            print("📦 Response data size: \(data.count) bytes")
            
            // Debug: Print first few characters of response
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 Response preview: \(String(responseString.prefix(200)))")
            }
            
            let channels = try JSONDecoder().decode([LiveChannel].self, from: data)
            print("✅ Successfully decoded \(channels.count) live channels")
            
            // Debug: Print first few channel names
            let firstChannels = channels.prefix(3).map { $0.name }
            print("📺 First channels: \(firstChannels)")
            
            return channels
            
        } catch let decodingError as DecodingError {
            print("❌ JSON Decoding Error: \(decodingError)")
            throw APIError.decodingFailure(decodingError)
        } catch {
            print("❌ Network Error: \(error)")
            throw error
        }
    }
    
    // Fetch series details using series_id
    func fetchSeriesDetails(seriesId: Int) async throws -> SerieDetail {
        var components = URLComponents(string: profile.baseURL)!
        components.path = "/player_api.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: profile.username),
            URLQueryItem(name: "password", value: profile.password),
            URLQueryItem(name: "action", value: "get_series_info"),
            URLQueryItem(name: "series_id", value: String(seriesId))
        ]
        
        let request = URLRequest(url: components.url!)

        // Perform request and log response details
        let (data, response) = try await session.data(for: request)
        
        // Convert and log the data as a string
        if let dataString = String(data: data, encoding: .utf8) {
            print("Raw data response as String: \(dataString)")
        } else {
            print("Failed to decode data to String")
        }

        // Log HTTP response status code
        if let httpResponse = response as? HTTPURLResponse {
            print("HTTP Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                throw APIError.invalidResponse
            }
        } else {
            print("Invalid HTTP response")
            throw APIError.invalidResponse
        }
        
        // Decode response and return
        do {
            let seriesDetail = try JSONDecoder().decode(SerieDetail.self, from: data)
            
            // Log the successfully decoded SerieDetail object
            print("Decoded Series Detail: \(seriesDetail)")
            return seriesDetail
        } catch let decodingError as DecodingError {
            // Handle specific decoding errors
            switch decodingError {
            case .typeMismatch(let type, let context):
                print("Type mismatch for type \(type) in context: \(context)")
            case .valueNotFound(let value, let context):
                print("Value not found for \(value) in context: \(context)")
            case .keyNotFound(let key, let context):
                print("Key not found for \(key) in context: \(context)")
            case .dataCorrupted(let context):
                print("Data corrupted in context: \(context)")
            @unknown default:
                print("Unknown decoding error: \(decodingError)")
            }
        } catch {
            // Handle any other errors that are not related to decoding
            print("Unexpected error while decoding SerieDetail: \(error)")
            throw error
        }
        throw APIError.decodingError
    }

}

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
    case decodingFailure(DecodingError)
    case networkError(Error)
}
