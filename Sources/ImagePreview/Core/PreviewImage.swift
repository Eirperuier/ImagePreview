import Foundation
import ImageIO
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// One image to show: what to draw right away (the thumbnail you already have, so the
/// transition starts on the first frame) and, optionally, how to get the full-size image.
public struct PreviewImage: @unchecked Sendable {
    /// Drawn at once, while the full image loads; usually the thumbnail on screen.
    public var placeholder: PreviewPlatformImage?
    let load: (@Sendable () async throws -> PreviewPlatformImage)?
    let key: AnyHashable?

    /// An image already in memory.
    public init(_ image: PreviewPlatformImage) {
        placeholder = image
        load = nil
        key = nil
    }

    /// An image at a URL (remote or a file), decoded off the main thread and kept in a small cache.
    /// - Parameter placeholder: what to draw until it arrives; the transition uses it, so pass the thumbnail if you have it.
    public init(url: URL, placeholder: PreviewPlatformImage? = nil) {
        self.placeholder = placeholder
        self.key = url
        self.load = { try await PreviewImageLoader.image(at: url) }
    }

    /// An image you load yourself (from your own cache, a database, Photos…).
    public init(placeholder: PreviewPlatformImage? = nil, load: @escaping @Sendable () async throws -> PreviewPlatformImage) {
        self.placeholder = placeholder
        self.key = nil
        self.load = load
    }

    /// The best image available without waiting.
    @MainActor var immediate: PreviewPlatformImage? {
        if let key, let cached = PreviewImageLoader.cached(key) { return cached }
        return placeholder
    }
}

/// Loads and decodes images off the main thread, so a page never stalls while it scrolls in.
enum PreviewImageLoader {
    /// The longest side a decoded image keeps, in pixels: plenty to zoom into, bounded in memory.
    nonisolated(unsafe) static var maxPixelSize = 4096

    @MainActor private static let cache: NSCache<AnyHashableBox, PreviewPlatformImage> = {
        let cache = NSCache<AnyHashableBox, PreviewPlatformImage>()
        cache.countLimit = 24
        return cache
    }()

    @MainActor static func cached(_ key: AnyHashable) -> PreviewPlatformImage? {
        cache.object(forKey: AnyHashableBox(key))
    }

    @MainActor static func store(_ image: PreviewPlatformImage, for key: AnyHashable) {
        cache.setObject(image, forKey: AnyHashableBox(key))
    }

    static func image(at url: URL) async throws -> PreviewPlatformImage {
        let data: Data
        if url.isFileURL {
            data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url, options: .mappedIfSafe) }.value
        } else {
            data = try await URLSession.shared.data(from: url).0
        }
        let decoded = try await Task.detached(priority: .userInitiated) { () throws -> Decoded in
            try decode(data)
        }.value
        #if canImport(UIKit)
        let image = UIImage(cgImage: decoded.image, scale: 1, orientation: .up)
        #else
        let image = NSImage(cgImage: decoded.image, size: CGSize(width: decoded.image.width, height: decoded.image.height))
        #endif
        await MainActor.run { store(image, for: url) }
        return image
    }

    struct Decoded: @unchecked Sendable { let image: CGImage }

    /// Decodes now (not lazily at first draw), the orientation applied, the longest side at most `maxPixelSize`.
    static func decode(_ data: Data) throws -> Decoded {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Decoded(image: image)
    }

    /// Prepares an image someone handed us for drawing, off the main thread where the platform allows.
    static func prepared(_ image: PreviewPlatformImage) async -> PreviewPlatformImage {
        #if canImport(UIKit)
        let box = Box(image)
        return await Task.detached(priority: .userInitiated) { Box(box.value.preparingForDisplay() ?? box.value) }.value.value
        #else
        return image
        #endif
    }
}

final class AnyHashableBox: NSObject {
    let value: AnyHashable
    init(_ value: AnyHashable) { self.value = value }
    override var hash: Int { value.hashValue }
    override func isEqual(_ object: Any?) -> Bool { (object as? AnyHashableBox)?.value == value }
}

struct Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
