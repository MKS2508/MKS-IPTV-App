import SwiftUI

// MARK: - Tag System Protocol
protocol TagContentProvider {
    func basicTags() -> [(icon: String, text: String)]  // Tags visibles sin tap (ej. año, calidad)
    func expandedTags() -> [(icon: String, text: String)] // Tags al hacer tap (ej. género, director)
    func customIcon(for tagType: String) -> String?  // Override de íconos
}

// Implementación por defecto
extension TagContentProvider {
    func customIcon(for tagType: String) -> String? {
        return nil  // Por defecto, no hay íconos personalizados
    }
}

// MARK: - Configuración de Apariencia de Tarjetas
enum RatingDisplayStyle: Equatable {
    case stars  // Muestra estrellas basadas en el rating
    case numeric  // Solo muestra el valor numérico
    case combined  // Muestra una estrella y el valor numérico
}

struct CardAppearanceConfig: Equatable {
    let expandAnimation: Animation
    let cornerRadius: CGFloat
    let maxVisibleTags: Int
    let iconMappings: [String: String]
    let ratingStyle: RatingDisplayStyle
    let borderStyle: BorderStyle
    
    // Implementando Equatable manualmente para manejar la comparación de Animation
    static func == (lhs: CardAppearanceConfig, rhs: CardAppearanceConfig) -> Bool {
        return lhs.cornerRadius == rhs.cornerRadius &&
               lhs.maxVisibleTags == rhs.maxVisibleTags &&
               lhs.iconMappings == rhs.iconMappings &&
               lhs.ratingStyle == rhs.ratingStyle
        // Nota: No comparamos expandAnimation porque Animation no es Equatable
    }
    
    enum BorderStyle: Equatable {
        case none
        case simple(Color, CGFloat)
        case gradient(colors: [Color], animated: Bool)
        
        static func == (lhs: BorderStyle, rhs: BorderStyle) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case (.simple(let color1, let width1), .simple(let color2, let width2)):
                return color1 == color2 && width1 == width2
            case (.gradient(let colors1, let animated1), .gradient(let colors2, let animated2)):
                return colors1 == colors2 && animated1 == animated2
            default:
                return false
            }
        }
    }
    
    // Configuración por defecto
    static let `default` = CardAppearanceConfig(
        expandAnimation: .spring(response: 0.3, dampingFraction: 0.7),
        cornerRadius: 16,
        maxVisibleTags: 2,
        iconMappings: [:],
        ratingStyle: .combined,
        borderStyle: .gradient(colors: [.blue.opacity(0.7), .purple.opacity(0.8), .pink.opacity(0.7)], animated: true)
    )
    
    // Configuración específica para películas
    static let movieDefault = CardAppearanceConfig(
        expandAnimation: .spring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.2),
        cornerRadius: 16,
        maxVisibleTags: 2,
        iconMappings: [
            "year": "calendar",
            "quality": "hd",
            "added": "calendar.badge.plus",
            "format": "doc.fill",
            "rating": "star.fill",
            "adult": "exclamationmark.triangle"
        ],
        ratingStyle: .combined,
        borderStyle: .gradient(colors: [.blue.opacity(0.7), .purple.opacity(0.8), .pink.opacity(0.7)], animated: true)
    )
    
    // Configuración específica para series
    static let seriesDefault = CardAppearanceConfig(
        expandAnimation: .spring(response: 0.3, dampingFraction: 0.7),
        cornerRadius: 16,
        maxVisibleTags: 2,
        iconMappings: [
            "year": "calendar",
            "quality": "hd",
            "genre": "film",
            "runtime": "clock",
            "cast": "person.2",
            "rating": "star.fill"
        ],
        ratingStyle: .combined,
        borderStyle: .gradient(colors: [.blue.opacity(0.7), .purple.opacity(0.8), .pink.opacity(0.7)], animated: true)
    )
}

// Environment key para la configuración de apariencia
struct CardAppearanceKey: EnvironmentKey {
    static let defaultValue = CardAppearanceConfig.default
}

extension EnvironmentValues {
    var cardAppearance: CardAppearanceConfig {
        get { self[CardAppearanceKey.self] }
        set { self[CardAppearanceKey.self] = newValue }
    }
}

// MARK: - Implementación de Tag Providers
struct MovieTagProvider: TagContentProvider {
    let movie: Movie
    let config: CardAppearanceConfig
    
    init(movie: Movie, config: CardAppearanceConfig = .movieDefault) {
        self.movie = movie
        self.config = config
    }
    
    func basicTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        if let year = movie.year {
            tags.append((getIconName(for: "year"), year))
        }
        
        if let quality = movie.quality {
            tags.append((getIconName(for: "quality"), quality))
        }
        
        return tags.prefix(config.maxVisibleTags).map { ($0.0, $0.1) }
    }
    
    func expandedTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        if let added = movie.added {
            tags.append((getIconName(for: "added"), "Added: \(added)"))
        }
        
        if let containerExtension = movie.containerExtension {
            tags.append((getIconName(for: "format"), "Format: \(containerExtension.uppercased())"))
        }
        
        if let quality = movie.quality {
            tags.append((getIconName(for: "quality"), "Quality: \(quality)"))
        }
        
        if movie.isAdult == "1" {
            tags.append((getIconName(for: "adult"), "Adult Content"))
        }
        
        return tags
    }
    
    func customIcon(for tagType: String) -> String? {
        return config.iconMappings[tagType]
    }
    
    func getIconName(for type: String) -> String {
        return customIcon(for: type) ?? defaultIconForTag(type)
    }
    
     func defaultIconForTag(_ type: String) -> String {
        switch type {
        case "year": return "calendar"
        case "quality": return "hd"
        case "added": return "calendar.badge.plus"
        case "format": return "doc.fill"
        case "adult": return "exclamationmark.triangle"
        default: return "tag"
        }
    }
}

struct SerieTagProvider: TagContentProvider {
    let serie: Serie
    let config: CardAppearanceConfig
    
    init(serie: Serie, config: CardAppearanceConfig = .seriesDefault) {
        self.serie = serie
        self.config = config
    }
    
    func basicTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        if let year = serie.year {
            tags.append((getIconName(for: "year"), year))
        }
        
        if let quality = serie.quality {
            tags.append((getIconName(for: "quality"), quality))
        }
        
        return tags.prefix(config.maxVisibleTags).map { ($0.0, $0.1) }
    }
    
    func expandedTags() -> [(icon: String, text: String)] {
        var tags = [(String, String)]()
        
        if !serie.genre.isEmpty {
            tags.append((getIconName(for: "genre"), serie.genre))
        }
        
        if !serie.episodeRunTime.isEmpty {
            tags.append((getIconName(for: "runtime"), serie.episodeRunTime))
        }
        
        if !serie.cast.isEmpty {
            tags.append((getIconName(for: "cast"), serie.cast))
        }
        
        return tags
    }
    
    func customIcon(for tagType: String) -> String? {
        return config.iconMappings[tagType]
    }
    
    private func getIconName(for type: String) -> String {
        return customIcon(for: type) ?? defaultIconForTag(type)
    }
    
    private func defaultIconForTag(_ type: String) -> String {
        switch type {
        case "year": return "calendar"
        case "quality": return "hd"
        case "genre": return "film"
        case "runtime": return "clock"
        case "cast": return "person.2"
        default: return "tag"
        }
    }
}

// MARK: - Componentes Visuales Reutilizables

struct TagView: View {
    let icon: String
    let text: String
    let fontSize: CGFloat
    let iconColor: Color
    let textColor: Color
    let backgroundColor: Color
    
    init(
        icon: String,
        text: String,
        fontSize: CGFloat = 14,
        iconColor: Color = .white.opacity(0.8),
        textColor: Color = .white.opacity(0.9),
        backgroundColor: Color = Color(.darkGray).opacity(0.5)
    ) {
        self.icon = icon
        self.text = text
        self.fontSize = fontSize
        self.iconColor = iconColor
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: fontSize))
                .foregroundColor(iconColor)
            
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
        )
    }
}

struct RatingBadgeView: View {
    let rating: String
    let style: RatingDisplayStyle
    let fontSize: CGFloat
    
    init(
        rating: String,
        style: RatingDisplayStyle = .combined,
        fontSize: CGFloat = 12
    ) {
        self.rating = rating
        self.style = style
        self.fontSize = fontSize
    }
    
    var body: some View {
        switch style {
        case .stars:
            starRating
        case .numeric:
            numericRating
        case .combined:
            combinedRating
        }
    }
    
    private var starRating: some View {
        let ratingValue = Double(rating) ?? 0
        let fullStars = Int(ratingValue / 2)
        
        return HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Image(systemName: index < fullStars ? "star.fill" : "star")
                    .font(.system(size: fontSize))
                    .foregroundColor(.yellow)
            }
        }
    }
    
    private var numericRating: some View {
        Text(rating)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(.white)
    }
    
    private var combinedRating: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
                .font(.system(size: fontSize))
            Text(rating)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

struct GradientBorderView: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let isAnimated: Bool
    let colors: [Color]
    
    @State private var rotation: Double = 0
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                AngularGradient(
                    colors: colors,
                    center: .center,
                    angle: .degrees(rotation)
                ),
                lineWidth: lineWidth
            )
            .blur(radius: lineWidth > 0 ? 2 : 0)
            .onAppear {
                if isAnimated {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
    }
}

struct PlaceholderView: View {
    let systemImage: String
    let title: String
    let aspectRatio: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 50)
            
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color.gray.opacity(0.1))
        .foregroundColor(.secondary)
    }
}

// MARK: - Extensiones de Modelo
extension Movie {
    var formattedTitle: String {
        return name
    }
    
    var year: String? {
        // Extraer año del nombre, ej. "The Matrix (1999) 4K" -> "1999"
        let pattern = "\\((\\d{4})\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let nsString = name as NSString
        let matches = regex.matches(in: name, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = matches.first else { return nil }
        return nsString.substring(with: match.range(at: 1))
    }
}

extension Serie {
    var formattedTitle: String {
        return name
    }
    
    var year: String? {
        // Extraer año del nombre, ej. "Stranger Things (2016)" -> "2016"
        let pattern = "\\((\\d{4})\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let nsString = name as NSString
        let matches = regex.matches(in: name, range: NSRange(location: 0, length: nsString.length))
        
        guard let match = matches.first else { return nil }
        return nsString.substring(with: match.range(at: 1))
    }
}
