#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// What one page of the viewer shows, for content of your own; ``PreviewImage`` and
/// ``PreviewVideo`` are built on it.
///
/// The viewer moves the content: it flies it out of its thumbnail and back, follows a drag that
/// closes it, pages it and zooms it. What it moves is the content's still, a picture of it, with
/// the content's own view over the still if it has one, laid out at the still's size and zoomed and
/// clipped with it: a video can play as it flies. The still's size is the content's shape.
///
/// ```swift
/// final class FeedVideo: PreviewContent {
///     let player: FeedPlayer
///     func still() -> UIImage? { player.currentFrame ?? player.poster }
///     func makeView(for place: PreviewContentPlace) -> UIView? { PlayerView(player.avPlayer) }
///     func setState(_ state: PreviewContentState) {
///         if state == .offScreen { player.pause() } else { player.play() }
///     }
/// }
///
/// .imagePreview(selection: $opened, items: items) { item in
///     PreviewMedia.content(FeedVideo(player: item.player))
/// }
/// ```
///
/// The viewer asks for an item's content when its page is about to be shown, once while it is open.
@MainActor
public protocol PreviewContent: AnyObject {
    /// A picture of the content as it is now; nil before there is any, when the viewer draws a
    /// picture of the thumbnail instead. Asked when a page is built, when the content flies off
    /// its page, and after `changed`.
    func still() -> PreviewPlatformImage?
    /// Starts getting what the content shows; call `changed` when there is a better still (the
    /// full image, a video's first frame). Called once, when the content is first wanted.
    func load(changed: @escaping @MainActor () -> Void)
    /// The viewer has closed: stop loading.
    func cancel()
    /// A view showing the content live over its still, or nil to show the still alone there.
    /// Asked for each page built and each flight; the viewer sizes, zooms and clips it, and
    /// removes it when it is done with it. It takes no clicks or touches.
    func makeView(for place: PreviewContentPlace) -> PreviewPlatformView?
    /// Where the content is now: the viewer calls this when it changes. A video plays when it is
    /// ``PreviewContentState/onScreen`` or ``PreviewContentState/moving`` and pauses when it is
    /// ``PreviewContentState/offScreen``.
    func setState(_ state: PreviewContentState)
}

extension PreviewContent {
    public func load(changed: @escaping @MainActor () -> Void) {}
    public func cancel() {}
    public func makeView(for place: PreviewContentPlace) -> PreviewPlatformView? { nil }
    public func setState(_ state: PreviewContentState) {}
}

/// Where a content's view goes.
public enum PreviewContentPlace: Sendable {
    /// On its page, fitted to the screen and zoomed with it.
    case page
    /// Flying out of the thumbnail or back into it, or dragged: resized every frame.
    case flight
}

/// Where a content is.
public enum PreviewContentState: Sendable {
    /// Not on screen: another page is, or the viewer has closed.
    case offScreen
    /// On its page, the viewer open and nothing moving it.
    case onScreen
    /// Flying in or out, or being dragged.
    case moving
}

/// What one page shows: an image, a video, or content of your own. ``PreviewImage`` and
/// ``PreviewVideo`` are media themselves; return `PreviewMedia` where an item can be either.
public struct PreviewMedia: PreviewMediaConvertible {
    let makeContent: @MainActor () -> any PreviewContent

    public static func image(_ image: PreviewImage) -> PreviewMedia { PreviewMedia { ImageContent(image) } }
    public static func video(_ video: PreviewVideo) -> PreviewMedia { PreviewMedia { VideoContent(video) } }
    /// Content of your own.
    @MainActor public static func content(_ content: any PreviewContent) -> PreviewMedia { PreviewMedia { content } }

    public var previewMedia: PreviewMedia { self }
}

/// An image, a video, or either: what the viewer can show on a page.
public protocol PreviewMediaConvertible {
    var previewMedia: PreviewMedia { get }
}

extension PreviewImage: PreviewMediaConvertible {
    public var previewMedia: PreviewMedia { .image(self) }
}

/// An image: the still is all there is, the placeholder until the full image arrives.
final class ImageContent: PreviewContent {
    private let image: PreviewImage
    private var loaded: PreviewPlatformImage?
    private var task: Task<Void, Never>?

    init(_ image: PreviewImage) { self.image = image }

    func still() -> PreviewPlatformImage? { loaded ?? image.immediate }

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
