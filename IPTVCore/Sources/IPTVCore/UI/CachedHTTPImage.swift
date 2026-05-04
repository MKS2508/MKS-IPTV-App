//
//  CachedHTTPImage.swift
//  IPTVCore
//
//  Drop-in replacement for AsyncImage. Uses RawHTTPClient instead of
//  URLSession so plain-HTTP poster URLs aren't blocked by tvOS 26 ATS.
//
//  Public phase type matches SwiftUI's AsyncImagePhase so call sites are
//  copy-paste compatible (.empty / .success(Image) / .failure(Error)).
//
//  In-memory NSCache keyed by URL string. 256-entry / 64 MB cap.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias _PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias _PlatformImage = NSImage
#endif

public struct CachedHTTPImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    public init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    public var body: some View {
        content(phase)
            .task(id: url?.absoluteString) {
                await load()
            }
    }

    private func load() async {
        guard let url else { phase = .empty; return }

        if let cached = ImageMemoryCache.shared.image(for: url) {
            phase = .success(Image(platformImage: cached))
            return
        }

        do {
            let (data, response) = try await RawHTTPClient.shared.get(url, timeout: 20)
            guard response.statusCode == 200, let image = _PlatformImage(data: data) else {
                phase = .failure(LoadError.badStatus(response.statusCode))
                return
            }
            ImageMemoryCache.shared.store(image, for: url)
            phase = .success(Image(platformImage: image))
        } catch is CancellationError {
            // View disappeared — leave state as-is so we can resume on reappear.
        } catch {
            MKSLog.network.error("CachedHTTPImage load failed url=\(url) error=\(error)")
            phase = .failure(error)
        }
    }

    private enum LoadError: Error {
        case badStatus(Int)
    }
}

// MARK: - Image bridge

private extension Image {
    init(platformImage: _PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - Cache

private final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()

    private let cache: NSCache<NSString, _PlatformImage> = {
        let c = NSCache<NSString, _PlatformImage>()
        c.countLimit = 256
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    func image(for url: URL) -> _PlatformImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: _PlatformImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}
