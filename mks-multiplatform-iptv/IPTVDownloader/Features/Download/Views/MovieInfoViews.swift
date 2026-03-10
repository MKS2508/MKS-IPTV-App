import SwiftUI

// MARK: - Movie Information Views for AddDownloadView

struct MovieInfoViews {
    
    static func moviePosterView(movieDetail: MovieDetail) -> some View {
        AsyncImage(url: URL(string: movieDetail.movieImage)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                Color.gray.opacity(0.3)
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .frame(width: 120, height: 180)
        .cornerRadius(8)
    }
    
    static func movieBasicInfoView(movieDetail: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(movieDetail.movieData.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if let year = extractYear(from: movieDetail.releaseDate) {
                Text(year)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            if let rating = movieDetail.movieData.rating5Based {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                    
                    Text(String(format: "%.1f", rating))
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    static func movieDetailedInfoView(movieDetail: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !movieDetail.plot.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sinopsis")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(movieDetail.plot)
                        .font(.body)
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Información detallada")
                    .font(.headline)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    if !movieDetail.director.isEmpty {
                        detailRow(title: "Director", content: movieDetail.director)
                    }
                    
                    if !movieDetail.cast.isEmpty {
                        detailRow(title: "Reparto", content: movieDetail.cast.joined(separator: ", "))
                    }
                    
                    if !movieDetail.duration.isEmpty {
                        detailRow(title: "Duración", content: movieDetail.duration)
                    }
                    
                    if !movieDetail.genre.isEmpty {
                        detailRow(title: "Género", content: movieDetail.genre)
                    }
                    
                    if !movieDetail.releaseDate.isEmpty {
                        detailRow(title: "Fecha de estreno", content: movieDetail.releaseDate)
                    }
                }
            }
        }
    }
    
    static func detailRow(title: String, content: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(title):")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.gray)
                .frame(width: 100, alignment: .leading)
            
            Text(content)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
    
    private static func extractYear(from dateString: String?) -> String? {
        guard let dateString = dateString else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            return yearFormatter.string(from: date)
        }
        
        return nil
    }
}