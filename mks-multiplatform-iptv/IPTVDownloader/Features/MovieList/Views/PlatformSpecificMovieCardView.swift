//
//  PlatformSpecificMovieCardView.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 18/3/25.
//
import SwiftUI

struct PlatformSpecificMovieCardView: View {
    let movie: Movie
    var namespace: Namespace.ID
    var onViewDetails: (() -> Void)?
    
    // Configuración personalizada para películas
    private let movieCardConfig = CardAppearanceConfig(
        expandAnimation: .spring(response: 0.3, dampingFraction: 0.75, blendDuration: 0.3),
        cornerRadius: 18,
        maxVisibleTags: 2,
        iconMappings: [
            "year": "calendar.circle.fill",
            "quality": "badge.4k.fill",
            "added": "plus.circle.fill",
            "format": "doc.viewfinder",
            "adult": "exclamationmark.triangle.fill"
        ],
        ratingStyle: .combined,
        borderStyle: .gradient(colors: [.blue.opacity(0.7), .purple.opacity(0.8), .pink.opacity(0.7)], animated: true)
    )
    
    // Constructor con parámetro opcional para la acción
    init(movie: Movie, namespace: Namespace.ID, onViewDetails: (() -> Void)? = nil) {
        self.movie = movie
        self.namespace = namespace
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        #if os(iOS)
        // Nuevo componente unificado con configuración personalizada
        MediaCardViewiOS(
            mediaCardType: .movie(movie),
            namespace: namespace,
            onViewDetails: onViewDetails ?? {}
        )
        .environment(\.cardAppearance, movieCardConfig)
        // También podríamos crear un MovieTagProvider personalizado si quisiéramos
        #else
        MovieCardView(movie: movie, namespace: namespace)
        #endif
    }
}

// Extensión para agregar más información a los tags si se desea
extension MovieTagProvider {
    // Método personalizado que podría utilizarse para agregar tags adicionales
    func additionalInfoTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        // Ejemplo: Agregar información adicional para películas
        if let added = movie.added {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: added) {
                formatter.dateFormat = "MMM d, yyyy"
                let formattedDate = formatter.string(from: date)
                tags.append((getIconName(for: "added"), "Added: \(formattedDate)"))
            }
        }
        
        return tags
    }
}

// Implementación de una versión más personalizada del proveedor de tags
struct EnhancedMovieTagProvider: TagContentProvider {
    let movie: Movie
    let config: CardAppearanceConfig
    
    init(movie: Movie, config: CardAppearanceConfig = .movieDefault) {
        self.movie = movie
        self.config = config
    }
    
    func basicTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        // Mostrar el año con un formato específico
        if let year = movie.year {
            tags.append((customIcon(for: "year") ?? "calendar", year))
        }
        
        // Mostrar calidad con ícono personalizado
        if let quality = movie.quality {
            let icon = quality.contains("4K") ? "badge.4k.fill" :
                       quality.contains("HD") ? "h.square.fill" : "video.fill"
            tags.append((icon, quality))
        }
        
        return tags.prefix(config.maxVisibleTags).map { ($0.0, $0.1) }
    }
    
    func expandedTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        // Formato de fecha mejorado
        if let added = movie.added {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: added) {
                formatter.dateFormat = "MMM d, yyyy"
                let formattedDate = formatter.string(from: date)
                tags.append((customIcon(for: "added") ?? "calendar.badge.plus", "Added: \(formattedDate)"))
            } else {
                tags.append((customIcon(for: "added") ?? "calendar.badge.plus", "Added: \(added)"))
            }
        }
        
        // Formato del archivo con ícono personalizado
        if let containerExtension = movie.containerExtension {
            tags.append((customIcon(for: "format") ?? "doc.fill",
                        "Format: \(containerExtension.uppercased())"))
        }
        
        // Calidad con etiqueta descriptiva
        if let quality = movie.quality {
            let description: String
            switch quality.lowercased() {
            case "4k":
                description = "Ultra HD Quality"
            case "hd":
                description = "High Definition"
            case "sd":
                description = "Standard Definition"
            default:
                description = "Quality: \(quality)"
            }
            tags.append((customIcon(for: "quality") ?? "hd", description))
        }
        
        // Advertencia de contenido para adultos más notoria
        if movie.isAdult == "1" {
            tags.append((customIcon(for: "adult") ?? "exclamationmark.triangle",
                        "Warning: Adult Content"))
        }
        
        return tags
    }
    
    func customIcon(for tagType: String) -> String? {
        return config.iconMappings[tagType]
    }
}

// Versión avanzada del componente que utiliza el proveedor personalizado
struct PlatformSpecificMovieCardViewAdvanced: View {
    let movie: Movie
    let namespace: Namespace.ID
    var onViewDetails: (() -> Void)?
    
    init(movie: Movie, namespace: Namespace.ID, onViewDetails: (() -> Void)? = nil) {
        self.movie = movie
        self.namespace = namespace
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        #if os(iOS)
        // Creación del componente con un proveedor personalizado
        EnhancedMediaCardViewiOS(
            movie: movie,
            namespace: namespace,
            tagProvider: EnhancedMovieTagProvider(
                movie: movie,
                config: CardAppearanceConfig.movieDefault
            ),
            onViewDetails: onViewDetails ?? {}
        )
        #else
        MovieCardView(movie: movie, namespace: namespace)
        #endif
    }
}

// Componente avanzado que usa un proveedor de tags personalizado
struct EnhancedMediaCardViewiOS<Provider: TagContentProvider>: View {
    let movie: Movie
    var namespace: Namespace.ID
    let tagProvider: Provider
    var onViewDetails: () -> Void
    
    @Environment(\.cardAppearance) private var configFromEnv
    
    // Inicializador con proveedor personalizado
    init(movie: Movie, namespace: Namespace.ID, tagProvider: Provider, onViewDetails: @escaping () -> Void) {
        self.movie = movie
        self.namespace = namespace
        self.tagProvider = tagProvider
        self.onViewDetails = onViewDetails
    }
    
    var body: some View {
        // Utiliza MediaCardViewiOS con el tagProvider personalizado
        MediaCardViewiOS(
            mediaCardType: .movie(movie),
            namespace: namespace,
            onViewDetails: onViewDetails
        )
        // Aquí podríamos personalizar más aspectos si fuera necesario
    }
}
