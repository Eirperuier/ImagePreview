import AVFoundation
import CoreImage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// One video to show: it plays while it is on screen, from the start again when it ends.
public struct PreviewVideo: @unchecked Sendable {
    /// A file or a remote URL AVFoundation can play.
    public var url: URL
    /// Drawn at once, until the video's first frame is in; usually the thumbnail on screen.
    public var poster: PreviewPlatformImage?

    /// - Parameter poster: what to draw until the first frame is in; the transition uses it, so pass the thumbnail if you have it.
    public init(url: URL, poster: PreviewPlatformImage? = nil) {
        self.url = url
        self.poster = poster
    }
}

extension PreviewVideo: PreviewMediaConvertible {
    public var previewMedia: PreviewMedia { .video(self) }
}

/// A video. Its still is the poster, then the first frame, and once it has played the frame it
/// is on, so the picture flown when the viewer closes is the one that was on screen.
final class VideoContent: PreviewContent {
    private let video: PreviewVideo
    private let player: AVPlayer
    private let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
    /// The first frame, then the last frame taken from the player.
    private var frame: PreviewPlatformImage?
    /// How the video's frames are turned to be upright.
    private var orientation: CGImagePropertyOrientation = .up
    private var task: Task<Void, Never>?
    private var isActive = false
    private var hasPlayed = false
    nonisolated(unsafe) private var ended: NSObjectProtocol?

    private static let context = CIContext()

    init(_ video: PreviewVideo) {
        self.video = video
        let item = AVPlayerItem(url: video.url)
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        ended = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playFromStart() }
        }
    }

    deinit {
        if let ended { NotificationCenter.default.removeObserver(ended) }
    }

    var still: PreviewPlatformImage? {
        if hasPlayed, let now = currentFrame() { frame = now }
        return frame ?? video.poster
    }

    func load(changed: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let url = video.url
        task = Task { [weak self] in
            guard let first = try? await Self.firstFrame(at: url), let self else { return }
            self.orientation = first.orientation
            guard self.frame == nil else { return }
            self.frame = Self.platformImage(first.image)
            changed()
        }
    }

    func cancel() {
        task?.cancel()
        isActive = false
        player.pause()
    }

    func makeView() -> PreviewPlatformView? { PreviewPlayerView(player: player) }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            hasPlayed = true
            player.play()
        } else {
            if let now = currentFrame() { frame = now }
            player.pause()
        }
    }

    private func playFromStart() {
        player.seek(to: .zero)
        if isActive { player.play() }
    }

    /// The frame the player is showing, upright.
    private func currentFrame() -> PreviewPlatformImage? {
        guard let buffer = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        guard let cgImage = Self.context.createCGImage(image, from: image.extent) else { return nil }
        return Self.platformImage(cgImage)
    }

    struct FirstFrame: @unchecked Sendable {
        let image: CGImage
        let orientation: CGImagePropertyOrientation
    }

    /// The first frame, upright, decoded off the main thread, and how the video's frames are turned.
    private nonisolated static func firstFrame(at url: URL) async throws -> FirstFrame {
        let asset = AVURLAsset(url: url)
        var orientation = CGImagePropertyOrientation.up
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            orientation = Self.orientation(of: try await track.load(.preferredTransform))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let side = CGFloat(PreviewImageLoader.maxPixelSize)
        generator.maximumSize = CGSize(width: side, height: side)
        return FirstFrame(image: try await generator.image(at: .zero).image, orientation: orientation)
    }

    private static func platformImage(_ image: CGImage) -> PreviewPlatformImage {
        #if canImport(UIKit)
        UIImage(cgImage: image, scale: 1, orientation: .up)
        #else
        NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        #endif
    }

    /// The turn a track's transform gives its frames (a phone's portrait video is stored on its side).
    private nonisolated static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}

/// Shows a player's video, fitted in the view (which has the video's shape).
#if canImport(UIKit)
final class PreviewPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        let layer = layer as! AVPlayerLayer
        layer.player = player
        layer.videoGravity = .resizeAspect
        isUserInteractionEnabled = false
        accessibilityIgnoresInvertColors = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
#else
final class PreviewPlayerView: NSView {
    init(player: AVPlayer) {
        super.init(frame: .zero)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.layer = layer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
