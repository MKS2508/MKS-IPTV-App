import SwiftUI

struct PlatformSpecificSerieCardView: View {
    let serie: Serie
    var onViewDetails: (() -> Void)?
    @Namespace private var namespace
    
    // Configuración personalizada para series
    private let serieCardConfig = CardAppearanceConfig(
        expandAnimation: .spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.3),
        cornerRadius: 16,
        maxVisibleTags: 2,
        iconMappings: [
            "year": "calendar.circle.fill",
            "genre": "film.stack",
            "runtime": "timer",
            "cast": "person.2.fill",
            "rating": "star.fill"
        ],
        ratingStyle: .combined,
        borderStyle: .gradient(colors: [.indigo.opacity(0.7), .purple.opacity(0.8), .blue.opacity(0.7)], animated: true)
    )
    
    // Constructor con parámetro opcional para la acción
    init(serie: Serie, onViewDetails: (() -> Void)? = nil) {
        self.serie = serie
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        #if os(iOS)
        // Nuevo componente unificado con configuración personalizada
        MediaCardViewiOS(
            mediaCardType: .serie(serie),
            namespace: namespace,
            onViewDetails: onViewDetails ?? {}
        )
        .environment(\.cardAppearance, serieCardConfig)
        #else
        SerieCardView(serie: serie, namespace: namespace)
        #endif
    }
}

// Extensión para agregar más información a los tags si se desea
extension SerieTagProvider {
    // Método personalizado para agregar tags adicionales
    func additionalInfoTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        // Ejemplo: Información sobre temporadas/episodios
        if !serie.backdropPath.isEmpty {
            let seasonCount = serie.backdropPath.count
            tags.append(("tv.and.mediabox", "Seasons: \(seasonCount)"))
        }
        
        // Fecha de lanzamiento formateada
        if !serie.releaseDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: serie.releaseDate) {
                formatter.dateFormat = "MMM d, yyyy"
                let formattedDate = formatter.string(from: date)
                tags.append(("calendar.badge.clock", "Released: \(formattedDate)"))
            }
        }
        
        return tags
    }
}

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
        
        // Fecha de lanzamiento formateada
        if !serie.releaseDate.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: serie.releaseDate) {
                formatter.dateFormat = "MMMM d, yyyy"
                let formattedDate = formatter.string(from: date)
                tags.append(("calendar.badge.clock", "First Aired: \(formattedDate)"))
            } else {
                tags.append(("calendar", "First Aired: \(serie.releaseDate)"))
            }
        }
        
        // Fecha de última modificación (útil para saber si hay actualizaciones)
        if !serie.lastModified.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: serie.lastModified) {
                formatter.dateFormat = "MMM d, yyyy"
                let formattedDate = formatter.string(from: date)
                tags.append(("arrow.triangle.2.circlepath", "Updated: \(formattedDate)"))
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
