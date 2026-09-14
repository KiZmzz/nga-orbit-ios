import SwiftUI
import UIKit

/// Memory cache plus off-main downsampling for remote images. NGA list thumbnails
/// used to pop in with a hitch because full-size data was decoded on the main
/// thread at row time. Here the image is fetched ahead of scrolling, decoded once
/// at a bounded pixel size on a background task, and cached in memory.
@MainActor
enum RemoteImageStore {
    private static let cache = NSCache<NSURL, UIImage>()

    /// Download, downsample and cache. The decode runs off the main actor.
    static func image(at url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let image = await Task.detached(priority: .utility) {
            Self.decode(data, maxPixel: maxPixel)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL, cost: data.count) }
        return image
    }

    /// Warm the cache before rows scroll into view so cards render finished.
    static func warm(_ urls: [URL], maxPixel: CGFloat) {
        for url in urls where cache.object(forKey: url as NSURL) == nil {
            Task { _ = await image(at: url, maxPixel: maxPixel) }
        }
    }

    /// One ImageIO thumbnail at a bounded pixel size: bounded memory, single decode.
    private nonisolated static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A remote image that renders only after a real, downsampled decode. Until then
/// it shows a quiet placeholder; failed loads keep the reserved geometry stable.
struct DownsampledImageView: View {
    let url: URL
    var maxPixel: CGFloat = 600
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                switch contentMode {
                case .fill: Image(uiImage: image).resizable().scaledToFill()
                case .fit: Image(uiImage: image).resizable().scaledToFit()
                @unknown default: Image(uiImage: image).resizable().scaledToFill()
                }
            } else {
                AppTheme.cardSoft.opacity(0.55)
            }
        }
        .task(id: url) {
            if image == nil { image = await RemoteImageStore.image(at: url, maxPixel: maxPixel) }
        }
    }
}
