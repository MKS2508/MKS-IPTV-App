import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// Image cache
class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, PlatformImage>()
    
    private init() {}

    func set(_ image: PlatformImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func get(forKey key: String) -> PlatformImage? {
        return cache.object(forKey: key as NSString)
    }
}

// Image loader
class ImageLoader: ObservableObject {
    @Published var image: PlatformImage?
    private let url: URL
    private let cache: ImageCache
    
    init(url: URL, cache: ImageCache = .shared) {
        self.url = url
        self.cache = cache
    }
    
    func load() {
        if let cachedImage = cache.get(forKey: url.absoluteString) {
            DispatchQueue.main.async {
                self.image = cachedImage
            }
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let loadedImage = PlatformImage(data: data) else { return }
            
            DispatchQueue.main.async {
                self.cache.set(loadedImage, forKey: self.url.absoluteString)
                self.image = loadedImage
            }
        }.resume()
    }
}

// Cached async image view
struct CachedAsyncImage<Content: View>: View {
    @StateObject private var loader: ImageLoader
    private let content: (AsyncImagePhase) -> Content
    
    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.content = content
        _loader = StateObject(wrappedValue: ImageLoader(url: url ?? URL(string: "https://example.com/placeholder.png")!))
    }
    
    var body: some View {
        content(phase)
            .onAppear {
                loader.load()
            }
    }
    
    private var phase: AsyncImagePhase {
        if let image = loader.image {
            return .success(Image(platformImage: image))
        } else {
            return .empty
        }
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
