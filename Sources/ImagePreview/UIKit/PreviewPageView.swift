#if canImport(UIKit)
import UIKit

/// One page of the viewer: its still fitted to the screen and the content's view over it; pinch and double-tap to zoom.
final class PreviewPageView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var maximumZoomFactor: CGFloat = 4 {
        didSet { updateZoomLimits() }
    }
    private var laidOutSize: CGSize = .zero
    private var imageSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        bouncesZoom = true
        scrollsToTop = false
        imageView.contentMode = .scaleToFill
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var image: UIImage? { imageView.image }

    /// The content's view, over the still.
    func setLiveView(_ view: UIView?) {
        guard let view else { return }
        view.frame = imageView.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.addSubview(view)
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
        let size = image?.size ?? .zero
        let sameShape = size.hasArea && imageSize.hasArea
            && abs(size.width / size.height - imageSize.width / imageSize.height) < 0.002
        imageSize = size
        if !sameShape { fit() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != laidOutSize { fit() }
    }

    /// The image's rect on screen when fitted (not zoomed).
    var fittedFrame: CGRect { CGRect(origin: .zero, size: bounds.size).placing(imageSize, .fit) }

    var isZoomed: Bool { zoomScale > minimumZoomScale + 0.01 }

    func resetZoom(animated: Bool = false) {
        if isZoomed { setZoomScale(minimumZoomScale, animated: animated) }
    }

    private func fit() {
        laidOutSize = bounds.size
        zoomScale = 1
        let fitted = fittedFrame
        imageView.frame = CGRect(origin: .zero, size: fitted.size)
        contentSize = fitted.size
        updateZoomLimits()
        centerContent()
    }

    /// Zooming in far enough to fill the screen first, as Photos does; otherwise a fixed step.
    private var doubleTapScale: CGFloat {
        let fitted = fittedFrame
        guard fitted.width > 0, fitted.height > 0 else { return 2.5 }
        let fill = max(bounds.width / fitted.width, bounds.height / fitted.height)
        return fill > 1.25 ? fill : 2.5
    }

    private func updateZoomLimits() {
        minimumZoomScale = 1
        maximumZoomScale = max(maximumZoomFactor, doubleTapScale)
    }

    private func centerContent() {
        let x = max((bounds.width - contentSize.width) / 2, 0)
        let y = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    /// Double tap: zoom in on the tapped point, or back out.
    func toggleZoom(at point: CGPoint) {
        if isZoomed {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }
        let scale = doubleTapScale
        let p = convert(point, to: imageView)
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }

    // Unzoomed, the image has nowhere to scroll: leave the drag to swiping and closing.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === panGestureRecognizer, !isZoomed { return false }
        return super.gestureRecognizerShouldBegin(g)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerContent() }
}
#endif
