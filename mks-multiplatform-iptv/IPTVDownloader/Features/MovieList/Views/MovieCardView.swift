import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MovieCardView: View {
    let movie: Movie
    @State private var isHovered = false
    @State private var isAppearing = false // For initial appearance animation
    @State private var shineOffset: CGFloat = -200 // For shine effect
    @State private var gradientRotation: Double = 0 // For rotating gradient animation
    @State private var pulseScale: CGFloat = 1.0 // For subtle pulsing effect
    var namespace: Namespace.ID
    
    // Constants for adaptive dimensions
    private let posterAspectRatio: CGFloat = 2/3
    private let cornerRadius: CGFloat = 12
    private let minPosterWidth: CGFloat = 120
    
    // Font sizes - slightly increased for better readability
    private let titleFontSize: CGFloat = 15
    private let detailsFontSize: CGFloat = 13
    private let smallDetailsFontSize: CGFloat = 11
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Poster (always visible)
                posterImage(width: geometry.size.width)
                    .frame(width: geometry.size.width)
                
                // Enhanced movie details overlay
                enhancedMovieDetails
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(width: geometry.size.width)
                    .background(
                        Rectangle()
                            .fill(Color(.darkGray).opacity(0.9))
                            .blur(radius: 0.5)
                    )
                // Improved animation for details appearance
                    .opacity(isHovered ? 1 : 0)
                    .offset(y: isHovered ? 0 : 10)
            }
            .frame(width: geometry.size.width, height: geometry.size.width / posterAspectRatio)
            .background(.background)
            .cornerRadius(cornerRadius)
            // Animated moving gradient glow effect on hover
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.7),
                                Color.purple.opacity(0.8),
                                Color.pink.opacity(0.7),
                                Color.orange.opacity(0.6),
                                Color.blue.opacity(0.7)
                            ]),
                            center: .center,
                            angle: .degrees(gradientRotation)
                        ),
                        lineWidth: isHovered ? 2.5 : 0
                    )
                    .scaleEffect(pulseScale)
                    .blur(radius: isHovered ? 3 : 0)
            )
            // Improved shadow animation
            .shadow(
                color: .black.opacity(isHovered ? 0.25 : 0.15),
                radius: isHovered ? 12 : 8,
                x: 0,
                y: isHovered ? 6 : 4
            )
            // Improved hover animation with multiple properties
            .scaleEffect(isHovered ? 1.03 : 1)
            .brightness(isHovered ? 0.03 : 0)
            // Staggered animations for different properties
            .animation(.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.1), value: isHovered)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                
                // Trigger shine effect when hovering starts
                if hovering {
                    // Start the gradient rotation animation
                    withAnimation(Animation.linear(duration: 4).repeatForever(autoreverses: false)) {
                        gradientRotation = 360
                    }
                    
                    // Start the pulse animation
                    withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        pulseScale = 1.03
                    }
                    
                    // Shine effect animation
                    withAnimation(Animation.easeInOut(duration: 1.2)) {
                        shineOffset = geometry.size.width + 200
                    }
                } else {
                    // Reset animations when not hovering
                    withAnimation {
                        gradientRotation = 0
                        pulseScale = 1.0
                    }
                    shineOffset = -200
                }
            }
            // Initial appearance animation
            .opacity(isAppearing ? 1 : 0)
            .offset(y: isAppearing ? 0 : 20)
            .scaleEffect(isAppearing ? 1 : 0.97)
        }
        .aspectRatio(posterAspectRatio, contentMode: .fit)
        .frame(minWidth: minPosterWidth)
        // Improved transition with timing curve
        .transition(
            .asymmetric(
                insertion: .modifier(
                    active: CustomScaleModifier(scale: 0.95, opacity: 0, offset: CGSize(width: 0, height: 20)),
                    identity: CustomScaleModifier(scale: 1, opacity: 1, offset: .zero)
                ),
                removal: .modifier(
                    active: CustomScaleModifier(scale: 0.9, opacity: 0, offset: CGSize(width: 0, height: -10)),
                    identity: CustomScaleModifier(scale: 1, opacity: 1, offset: .zero)
                )
            )
        )
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
    }
    
    // Enhanced movie details with improved typography and focus on title and year
    private var enhancedMovieDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Enhanced title with better typography
            Text(movie.formattedTitle ?? movie.name)
                .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .foregroundColor(.primary)
                .matchedGeometryEffect(id: "\(movie.id)-title", in: namespace)
            
            HStack {
                // Year with enhanced styling
                if let year = movie.year {
                    Text(year)
                        .font(.system(size: detailsFontSize, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(.darkGray).opacity(0.5))
                                .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
                        )
                }
                
                Spacer()
                
                // Enhanced rating view
                enhancedRatingView
            }
            .matchedGeometryEffect(id: "\(movie.id)-details", in: namespace)
        }
    }
    
    private func posterImage(width: CGFloat) -> some View {
        CachedAsyncImage(url: URL(string: movie.streamIcon ?? "")) { phase in
            switch phase {
            case .empty:
                SkeletonLoader()
                    .aspectRatio(posterAspectRatio, contentMode: .fill)
            case .success(let image):
                ZStack {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width)
                        .clipped()
                        .overlay(
                            // Improved gradient on poster (visible when not hovered)
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .black.opacity(0.1),
                                    .black.opacity(0.3),
                                    .black.opacity(0.6)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            // Smoother fade animation for gradient
                                .opacity(isHovered ? 0 : 0.8)
                                .animation(.easeInOut(duration: 0.3), value: isHovered)
                                .overlay(
                                    // Rating badge with animated entrance
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.system(size: smallDetailsFontSize))
                                        Text(movie.rating ?? "5.0")
                                            .font(.system(size: smallDetailsFontSize))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }
                                        .padding(6)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.6))
                                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                        )
                                        .padding(8)
                                    // Animated badge with scale and opacity
                                        .opacity(isHovered ? 0 : 1)
                                        .scaleEffect(isHovered ? 0.9 : 1)
                                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                )
                        )
                    
                    // Enhanced shine effect overlay with better animation
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .white.opacity(0.1),
                                    .white.opacity(0.3),
                                    .white.opacity(0.1),
                                    .clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .rotationEffect(.degrees(35))
                        .offset(x: shineOffset)
                        .frame(width: 60)
                        .blendMode(.screen)
                        .opacity(isHovered ? 1 : 0)
                }
            case .failure:
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width * 0.35)
                    
                    Text(movie.name)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal)
                }
                .frame(width: width)
                .frame(height: width / posterAspectRatio)
                .background(Color.gray.opacity(0.1))
                .foregroundColor(.secondary)
            @unknown default:
                EmptyView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    Color.secondary.opacity(isHovered ? 0.2 : 0.1),
                    lineWidth: isHovered ? 1.5 : 1
                )
                .animation(.easeInOut(duration: 0.2), value: isHovered)
        )
        .matchedGeometryEffect(id: "\(movie.id)-poster", in: namespace)
    }
    
    // Enhanced rating view with improved visual design
    private var enhancedRatingView: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
                .font(.system(size: smallDetailsFontSize))
            Text(movie.rating ?? "5.0")
                .font(.system(size: detailsFontSize, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(.background)

        )
    }
    
}
// Custom transition modifier for more control
struct CustomScaleModifier: ViewModifier {
    let scale: CGFloat
    let opacity: CGFloat
    let offset: CGSize
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(offset)
    }
}

// Enhanced skeleton loader with improved animation
struct SkeletonLoader: View {
    @State private var animation = false
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.gray.opacity(0.1),
                Color.gray.opacity(0.2),
                Color.gray.opacity(0.1)
            ]),
            startPoint: animation ? .trailing : .leading,
            endPoint: animation ? .leading : .trailing
        )
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                animation.toggle()
            }
        }
    }
}

// Helper extension to erase view type
extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}


struct MovieCardView_Previews: PreviewProvider {
    @Namespace static var previewNamespace
    
    // Datos de ejemplo para las películas
    static let casino = Movie(
        name: "Casino",
        streamType: "movie",
        streamId: 1,
        streamIcon: "https://cdn11.bigcommerce.com/s-yzgoj/images/stencil/500x659/products/2891345/5947614/MOVCF5676__59910.1679593031.jpg?c=2", // Reemplaza con la URL real de la imagen de Casino
        rating: "7.8",
        rating5Based: 4.0,
        added: "1620000000",
        isAdult: "0",
        categoryId: "1",
        containerExtension: "mp4",
        customSid: "",
        directSource: ""
    )
    
    static let elPico = Movie(
        name: "El Pico",
        streamType: "movie",
        streamId: 2,
        streamIcon: "https://m.media-amazon.com/images/M/MV5BMTJkOTNhNjAtNzgzNy00ODAwLWE5N2EtNzZiNzNiNmVjNmFhXkEyXkFqcGc@._V1_.jpg", // Reemplaza con la URL real de la imagen de El Pico
        rating: "6.5",
        rating5Based: 3.25,
        added: "1620000000",
        isAdult: "1", // Ajusta este valor si es necesario
        categoryId: "1",
        containerExtension: "mp4",
        customSid: "",
        directSource: ""
    )
    
    static let navajeros = Movie(
        name: "Navajeros",
        streamType: "movie",
        streamId: 3,
        streamIcon: "https://image.tmdb.org/t/p/original/qRLLhYcctqlVCMdNGP85erTbSqI.jpg", // Si tienes una URL, puedes incluirla aquí
        rating: "7.0",
        rating5Based: 3.5,
        added: "1620000000",
        isAdult: "0",
        categoryId: "1",
        containerExtension: "mp4",
        customSid: "",
        directSource: ""
    )
    
    static var previews: some View {
        Group {
            // Preview de la tarjeta en tamaño normal para "Casino"
            MovieCardView(movie: casino, namespace: previewNamespace)
                .frame(width: 180)
                .previewDisplayName("Casino - Normal")
                .padding()
            
            // Preview de la tarjeta en tamaño compacto para "El Pico"
            MovieCardView(movie: elPico, namespace: previewNamespace)
                .frame(width: 120)
                .previewDisplayName("El Pico - Compacto")
                .padding()
            
            // Grid Preview para mostrar múltiples tarjetas
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)
            ], spacing: 12) {
                ForEach([casino, elPico, navajeros], id: \.streamId) { movie in
                    MovieCardView(movie: movie, namespace: previewNamespace)
                }
            }
            .previewDisplayName("Grid Preview")
            .padding()
            .frame(maxWidth: 600)
        }
        .previewLayout(.sizeThatFits)
        .background(.background)
    }
}
