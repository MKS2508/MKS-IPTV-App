import SwiftUI
import IPTVCore

// Implementación de una versión más personalizada del proveedor de tags para series
struct EnhancedSerieTagProvider: TagContentProvider {
    let serie: Serie
    let config: CardAppearanceConfig
    
    init(serie: Serie, config: CardAppearanceConfig = .seriesDefault) {
        self.serie = serie
        self.config = config
    }
    
    func basicTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        // Año de la serie en formato llamativo
        if let year = serie.year {
            tags.append((customIcon(for: "year") ?? "calendar", year))
        }
        
        // Género principal
        if !serie.genre.isEmpty {
            let genres = serie.genre.components(separatedBy: ",")
            if let mainGenre = genres.first?.trimmingCharacters(in: .whitespaces) {
                tags.append((customIcon(for: "genre") ?? "film", mainGenre))
            }
        }
        
        // Duración del episodio
        if !serie.episodeRunTime.isEmpty {
            tags.append((customIcon(for: "runtime") ?? "clock", serie.episodeRunTime))
        }
        
        // Calidad si está disponible
        if let quality = serie.quality {
            tags.append(("badge.hd", quality))
        }
        
        return tags.prefix(config.maxVisibleTags).map { ($0.0, $0.1) }
    }
    
    func expandedTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        // Lista completa de géneros
        if !serie.genre.isEmpty {
            tags.append((customIcon(for: "genre") ?? "film.stack", "Genre: \(serie.genre)"))
        }
        
        // Duración del episodio con formato mejorado
        if !serie.episodeRunTime.isEmpty {
            tags.append((customIcon(for: "runtime") ?? "timer", "Episode Length: \(serie.episodeRunTime)"))
        }
        
        // Reparto principal
        if !serie.cast.isEmpty {
            tags.append((customIcon(for: "cast") ?? "person.2", "Cast: \(serie.cast)"))
        }
        
        // Director o creador
        if let director = serie.director, !director.isEmpty {
            tags.append(("megaphone.fill", "Creator: \(director)"))
        }
        
        // Fecha de lanzamiento formateada (may be epoch timestamp or yyyy-MM-dd)
        if !serie.releaseDate.isEmpty {
            let fmt = DateFormatter()
            let date: Date?
            if let ts = TimeInterval(serie.releaseDate) {
                date = Date(timeIntervalSince1970: ts)
            } else {
                fmt.dateFormat = "yyyy-MM-dd"
                date = fmt.date(from: serie.releaseDate)
            }
            if let date {
                fmt.dateFormat = "MMMM d, yyyy"
                tags.append(("calendar.badge.clock", "First Aired: \(fmt.string(from: date))"))
            } else {
                tags.append(("calendar", "First Aired: \(serie.releaseDate)"))
            }
        }

        // Fecha de última modificación (may be epoch timestamp or yyyy-MM-dd)
        if !serie.lastModified.isEmpty {
            let fmt = DateFormatter()
            let date: Date?
            if let ts = TimeInterval(serie.lastModified) {
                date = Date(timeIntervalSince1970: ts)
            } else {
                fmt.dateFormat = "yyyy-MM-dd"
                date = fmt.date(from: serie.lastModified)
            }
            if let date {
                fmt.dateFormat = "MMM d, yyyy"
                tags.append(("arrow.triangle.2.circlepath", "Updated: \(fmt.string(from: date))"))
            }
        }
        
        // Información sobre temporadas
        if !serie.backdropPath.isEmpty {
            let seasonCount = serie.backdropPath.count
            let seasonText = seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons"
            tags.append(("tv.and.mediabox", seasonText))
        }
        
        return tags
    }
    
    func customIcon(for tagType: String) -> String? {
        return config.iconMappings[tagType]
    }
}

// Versión avanzada del componente que utiliza el proveedor personalizado
struct PlatformSpecificSerieCardViewAdvanced: View {
    let serie: Serie
    let namespace: Namespace.ID
    var onViewDetails: (() -> Void)?
    
    init(serie: Serie, namespace: Namespace.ID, onViewDetails: (() -> Void)? = nil) {
        self.serie = serie
        self.namespace = namespace
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        #if os(iOS)
        // Creación del componente con un proveedor personalizado
        EnhancedMediaCardViewSeriesiOS(
            serie: serie,
            namespace: namespace,
            tagProvider: EnhancedSerieTagProvider(
                serie: serie,
                config: CardAppearanceConfig.seriesDefault
            ),
            onViewDetails: onViewDetails ?? {}
        )
        #else
        SerieCardView(serie: serie, namespace: namespace)
        #endif
    }
}

// Componente avanzado que usa un proveedor de tags personalizado
struct EnhancedMediaCardViewSeriesiOS<Provider: TagContentProvider>: View {
    let serie: Serie
    var namespace: Namespace.ID
    let tagProvider: Provider
    var onViewDetails: () -> Void
    
    @Environment(\.cardAppearance) private var configFromEnv
    
    // Inicializador con proveedor personalizado
    init(serie: Serie, namespace: Namespace.ID, tagProvider: Provider, onViewDetails: @escaping () -> Void) {
        self.serie = serie
        self.namespace = namespace
        self.tagProvider = tagProvider
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        // Utiliza MediaCardViewiOS con el tagProvider personalizado
        MediaCardViewiOS(
            mediaCardType: .serie(serie),
            namespace: namespace,
            onViewDetails: onViewDetails
        )
        // Aquí podríamos personalizar más aspectos si fuera necesario
    }
}
