import CoreGraphics
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The thumbnail an image opens from and closes back into.
@MainActor
public struct LoupeSource {
    /// The view showing the thumbnail; its frame on screen is read when the viewer opens and again when it closes.
    public weak var view: LoupePlatformView?
    /// The thumbnail's corner radius, which the image grows out of and shrinks back into.
    public var cornerRadius: CGFloat
    /// How the thumbnail draws its image, so the first and last frames match it exactly.
    public var contentMode: LoupeContentMode
    let setHidden: (Bool) -> Void

    /// - Parameters:
    ///   - view: The view showing the thumbnail. It is hidden while the viewer shows its image.
    ///   - cornerRadius: The thumbnail's corner radius.
    ///   - contentMode: How the thumbnail draws its image.
    public init(view: LoupePlatformView, cornerRadius: CGFloat = 0, contentMode: LoupeContentMode = .fill) {
        self.view = view
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.setHidden = { [weak view] hidden in view?.isHidden = hidden }
    }

    init(view: LoupePlatformView, cornerRadius: CGFloat, contentMode: LoupeContentMode, setHidden: @escaping (Bool) -> Void) {
        self.view = view
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.setHidden = setHidden
    }
}

/// How the viewer looks and moves.
public struct LoupeConfiguration: Sendable {
    /// The backdrop behind the image when it is fully open.
    public var backgroundColor: CGColor = CGColor(gray: 0, alpha: 1)
    /// The gap between neighbouring images while swiping.
    public var pageSpacing: CGFloat = 16
    /// How far an image zooms in, relative to fitting the screen.
    public var maximumZoomScale: CGFloat = 4
    /// The spring that opens and closes the viewer.
    public var transitionSpring: LoupeSpring = .transition
    /// The spring that puts the image back after a drag that did not close it.
    public var restoreSpring: LoupeSpring = .restore
    /// A single tap hides and shows the accessories (otherwise it closes the viewer).
    public var tapTogglesAccessories = true

    public init() {}
}

/// What the accessories drawn over the viewer can read and do.
@MainActor @Observable
public final class LoupeContext {
    /// The index of the image on screen.
    public internal(set) var index: Int
    /// How many images there are.
    public internal(set) var count: Int
    /// Whether the accessories are showing (a tap toggles them; a drag hides them).
    public internal(set) var accessoriesVisible = true
    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored var onSelect: (Int) -> Void = { _ in }

    init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    /// Closes the viewer, back into the thumbnail if it is on screen.
    public func dismiss() { onDismiss() }

    /// Shows another image.
    public func select(_ index: Int) { onSelect(index) }
}
