#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What one page of the viewer shows.
///
/// The viewer flies a still picture of the content as it opens and closes and while a page is
/// dragged. In between, the page shows the still, fitted, zoomed and moved with the page, and over
/// it the content's own view if it has one. The still's size is the content's shape.
@MainActor
protocol PreviewContent: AnyObject {
    /// The best picture of the content there is now; nil before there is any.
    var still: PreviewPlatformImage? { get }
    /// Starts getting what the content shows, calling `changed` when the still is better.
    func load(changed: @escaping @MainActor () -> Void)
    /// Stops loading: the viewer has closed.
    func cancel()
    /// A view laid over the still at its size and zoomed with it, showing the content live (a
    /// video playing); nil when the still is all there is. Asked each time a page is built.
    func makeView() -> PreviewPlatformView?
}

extension PreviewContent {
    func makeView() -> PreviewPlatformView? { nil }
}

/// An image: the still is all there is, the placeholder until the full image arrives.
final class ImageContent: PreviewContent {
    private let image: PreviewImage
    private var loaded: PreviewPlatformImage?
    private var task: Task<Void, Never>?

    init(_ image: PreviewImage) { self.image = image }

    var still: PreviewPlatformImage? { loaded ?? image.immediate }

    func load(changed: @escaping @MainActor () -> Void) {
        guard task == nil, loaded == nil else { return }
        if let key = image.key, let cached = PreviewImageLoader.cached(key) {
            loaded = cached
            return
        }
        guard let load = image.load else { return }
        // The loader decodes what it loads; an image handed over is made ready to draw here.
        let prepares = image.key == nil
        task = Task { [weak self] in
            guard let full = try? await load() else { return }
            let ready = prepares ? await PreviewImageLoader.prepared(full) : full
            guard let self else { return }
            self.loaded = ready
            changed()
        }
    }

    func cancel() { task?.cancel() }
}
