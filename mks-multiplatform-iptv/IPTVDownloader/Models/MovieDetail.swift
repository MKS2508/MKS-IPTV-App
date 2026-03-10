import Foundation

struct MovieDetail: Identifiable, Codable {
    let movieData: Movie
    let movieImage: String
    let tmdbId: Int
    let backdrop: String?
    let youtubeTrailer: String?
    let genre: String
    let plot: String
    let cast: [String]
    let rating: String?       // Decodificado desde `info` - ahora opcional
    let director: String
    let releaseDate: String
    let backdropPath: [String]?
    let durationSecs: Int
    let duration: String
    
    var id: Int { movieData.streamId }
    
    enum CodingKeys: String, CodingKey {
        case info
        case movieData = "movie_data"
    }
    
    enum InfoKeys: String, CodingKey {
        case movieImage = "movie_image"
        case tmdbId = "tmdb_id"
        case backdrop
        case youtubeTrailer = "youtube_trailer"
        case genre
        case plot
        case cast
        case rating                     // Aquí está `rating` en `info`
        case director
        case releaseDate = "releasedate"
        case backdropPath = "backdrop_path"
        case durationSecs = "duration_secs"
        case duration
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decoding Movie base data
        self.movieData = try container.decode(Movie.self, forKey: .movieData)
        
        // Decoding additional info
        let infoContainer = try container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        self.movieImage = try infoContainer.decode(String.self, forKey: .movieImage)
        self.tmdbId = try infoContainer.decode(Int.self, forKey: .tmdbId)
        self.backdrop = try infoContainer.decodeIfPresent(String.self, forKey: .backdrop)
        self.youtubeTrailer = try infoContainer.decodeIfPresent(String.self, forKey: .youtubeTrailer)
        self.genre = try infoContainer.decode(String.self, forKey: .genre)
        self.plot = try infoContainer.decode(String.self, forKey: .plot)
        
        let castString = try infoContainer.decode(String.self, forKey: .cast)
        self.cast = castString.components(separatedBy: ",")
        
        self.rating = try infoContainer.decodeIfPresent(String.self, forKey: .rating)  // Decodificar `rating` aquí - ahora opcional
        self.director = try infoContainer.decode(String.self, forKey: .director)
        self.releaseDate = try infoContainer.decode(String.self, forKey: .releaseDate)
        self.backdropPath = try infoContainer.decodeIfPresent([String].self, forKey: .backdropPath)
        self.durationSecs = try infoContainer.decode(Int.self, forKey: .durationSecs)
        self.duration = try infoContainer.decode(String.self, forKey: .duration)
    }

    // Add this inside your MovieDetail struct
    init(
        movieData: Movie,
        movieImage: String,
        tmdbId: Int,
        backdrop: String?,
        youtubeTrailer: String?,
        genre: String,
        plot: String,
        cast: [String],
        rating: String?,
        director: String,
        releaseDate: String,
        backdropPath: [String]?,
        durationSecs: Int,
        duration: String
    ) {
        self.movieData = movieData
        self.movieImage = movieImage
        self.tmdbId = tmdbId
        self.backdrop = backdrop
        self.youtubeTrailer = youtubeTrailer
        self.genre = genre
        self.plot = plot
        self.cast = cast
        self.rating = rating
        self.director = director
        self.releaseDate = releaseDate
        self.backdropPath = backdropPath
        self.durationSecs = durationSecs
        self.duration = duration
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encoding Movie base data
        try container.encode(movieData, forKey: .movieData)
        
        // Encoding additional info
        var infoContainer = container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        try infoContainer.encode(movieImage, forKey: .movieImage)
        try infoContainer.encode(tmdbId, forKey: .tmdbId)
        try infoContainer.encodeIfPresent(backdrop, forKey: .backdrop)
        try infoContainer.encodeIfPresent(youtubeTrailer, forKey: .youtubeTrailer)
        try infoContainer.encode(genre, forKey: .genre)
        try infoContainer.encode(plot, forKey: .plot)
        try infoContainer.encode(cast.joined(separator: ", "), forKey: .cast)
        try infoContainer.encode(director, forKey: .director)
        try infoContainer.encode(releaseDate, forKey: .releaseDate)
        try infoContainer.encodeIfPresent(backdropPath, forKey: .backdropPath)
        try infoContainer.encode(durationSecs, forKey: .durationSecs)
        try infoContainer.encode(duration, forKey: .duration)
    }
}
