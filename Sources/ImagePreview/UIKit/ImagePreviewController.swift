#if canImport(UIKit)
import UIKit

/// Shows images full screen, opening out of the thumbnail that was tapped and closing back into it.
///
/// Swipe between images, pinch or double-tap to zoom, and drag an image in any direction
/// to close it: it follows the finger, shrinks, and lets what is underneath show through;
/// let go and it flies back into its thumbnail, or springs back if the drag was not far or fast enough.
///
/// ```swift
/// let preview = ImagePreviewController(count: photos.count, index: tapped) { i in
///     PreviewImage(url: photos[i].url, placeholder: cells[i].imageView.image)
/// } source: { i in
///     PreviewSource(view: cells[i].imageView, cornerRadius: 8)
/// }
/// preview.present(from: view)
/// ```
@MainActor
public final class ImagePreviewController {
    /// What the accessories can read (the index, whether they are showing) and do.
    public let context: ImagePreviewContext
    public var configuration: ImagePreviewConfiguration
    /// The image on screen changed (a swipe, or `select`).
    public var onIndexChange: ((Int) -> Void)?
    /// The viewer started closing.
    public var onDismiss: (() -> Void)?
    /// The viewer finished closing and is gone.
    public var onDidDismiss: (() -> Void)?
    /// Drawn over the images, full screen, faded with a tap and during drags: close buttons,
    /// captions, a page indicator. Touches outside its subviews go through to the images.
    public var accessoryView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if isLoaded { installAccessoryView() }
        }
    }

    /// A view controller whose view is the accessory view (a SwiftUI hosting controller), kept as the viewer's child.
    var accessoryHost: UIViewController?

    /// The image on screen.
    public var index: Int { context.index }
    public private(set) var isPresented = false
    var isClosing: Bool { phase == .closing || phase == .closed }

    private let count: Int
    private let imageProvider: (Int) -> PreviewImage
    private let sourceProvider: (Int) -> PreviewSource?

    /// - Parameters:
    ///   - count: How many images there are.
    ///   - index: The image to open.
    ///   - image: The image at an index; asked for when it is about to be shown.
    ///   - source: The thumbnail of the image at an index, if it is on screen.
    public init(
        count: Int,
        index: Int = 0,
        configuration: ImagePreviewConfiguration = .init(),
        image: @escaping (Int) -> PreviewImage,
        source: @escaping (Int) -> PreviewSource? = { _ in nil }
    ) {
        self.count = max(count, 0)
        self.context = ImagePreviewContext(index: min(max(index, 0), max(count - 1, 0)), count: max(count, 0))
        self.configuration = configuration
        self.imageProvider = image
        self.sourceProvider = source
        context.onDismiss = { [weak self] in self?.dismiss() }
        context.onSelect = { [weak self] in self?.select($0, animated: true) }
    }

    // MARK: Presenting

    /// Opens the viewer over the window `view` is in.
    public func present(from view: UIView) {
        guard !isPresented, count > 0, let scene = view.window?.windowScene else { return }
        isPresented = true
        Self.retained[ObjectIdentifier(self)] = self

        let window = UIWindow(windowScene: scene)
        window.windowLevel = UIWindow.Level(rawValue: (view.window?.windowLevel.rawValue ?? UIWindow.Level.normal.rawValue) + 1)
        window.backgroundColor = .clear
        let root = PreviewRootViewController(controller: self)
        window.rootViewController = root
        previousKeyWindow = scene.keyWindow
        self.window = window
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        open()
    }

    /// Closes the viewer, into the thumbnail of the image on screen if it is visible.
    public func dismiss() {
        switch phase {
        case .opening, .presented, .restoring:
            close(velocity: .zero)
        case .dragging, .closing, .closed:
            break
        }
    }

    /// Shows the image at `index`.
    public func select(_ index: Int, animated: Bool) {
        guard isLoaded, (0..<count).contains(index) else { return }
        pager.setContentOffset(CGPoint(x: CGFloat(index) * pager.bounds.width, y: 0), animated: animated && phase == .presented)
        if !animated || phase != .presented { setIndex(index) }
    }

    // MARK: State

    private enum Phase { case opening, presented, dragging, restoring, closing, closed }

    /// Viewers on screen keep themselves alive until they have closed.
    private static var retained: [ObjectIdentifier: ImagePreviewController] = [:]

    private var phase: Phase = .closed
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private weak var root: PreviewRootViewController?
    private var isLoaded: Bool { root?.isViewLoaded == true }

    private let backdrop = UIView()
    private let pager = PreviewPagerView()
    private let hero = HeroView()
    private let accessoryContainer = PassthroughView()
    private var pages: [Int: PreviewPageView] = [:]
    private var isLayingOut = false

    private var images: [Int: PreviewImage] = [:]
    private var loaded: [Int: UIImage] = [:]
    private var fallbacks: [Int: UIImage] = [:]
    private var loads: [Int: Task<Void, Never>] = [:]

    private var heroState = HeroState.presented(.zero)
    private var springs: SpringVector?
    private var springDone: (() -> Void)?
    private lazy var ticker = FrameTicker { [weak self] dt in self?.tick(dt) }

    private var drag: DismissDrag?
    private var dragAxis: DismissDrag.Axis = .vertical
    private var hiddenSource: PreviewSource?
    private var closingSource: PreviewSource?
    private var landing: Landing?
    /// Frames left in the hand-over from the landed image to its thumbnail.
    private var handoff: Int?
    /// Once the image is home: the scroll views to wait for before the window goes, and since when.
    private var retiring: ([UIScrollView], CFTimeInterval)?
    /// The status bar is drawn as the app draws it, not light over the dark backdrop.
    private var statusBarFollowsApp = false

    private lazy var gestureTarget = GestureTarget(self)
    private lazy var dismissPan = UIPanGestureRecognizer(target: gestureTarget, action: #selector(GestureTarget.pan(_:)))
    private lazy var singleTap = UITapGestureRecognizer(target: gestureTarget, action: #selector(GestureTarget.tap(_:)))
    private lazy var doubleTap = UITapGestureRecognizer(target: gestureTarget, action: #selector(GestureTarget.doubleTap(_:)))
    private lazy var gestureDelegate = GestureDelegate(self)

    // MARK: Building

    fileprivate func load(into root: PreviewRootViewController) {
        self.root = root
        let view: UIView = root.view
        view.backgroundColor = .clear
        backdrop.backgroundColor = UIColor(cgColor: configuration.backgroundColor)
        backdrop.alpha = 0
        view.addSubview(backdrop)

        pager.isPagingEnabled = true
        pager.showsHorizontalScrollIndicator = false
        pager.showsVerticalScrollIndicator = false
        pager.contentInsetAdjustmentBehavior = .never
        pager.scrollsToTop = false
        pager.delegate = gestureDelegate
        pager.isHidden = true
        // On an unzoomed image, a drag up or down, or sideways past the first or last image,
        // is the drag that closes, not a swipe.
        pager.shouldBeginPan = { [weak self] velocity in
            guard let self else { return true }
            return self.currentPage?.isZoomed == true || self.dismissAxis(for: velocity) == nil
        }
        view.addSubview(pager)

        hero.isUserInteractionEnabled = false
        view.addSubview(hero)

        accessoryContainer.alpha = 0
        view.addSubview(accessoryContainer)
        installAccessoryView()

        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        [dismissPan, singleTap, doubleTap].forEach { $0.delegate = gestureDelegate }
        dismissPan.maximumNumberOfTouches = 1
        [dismissPan, singleTap, doubleTap].forEach(view.addGestureRecognizer)
    }

    private func installAccessoryView() {
        guard let accessoryView else { return }
        if let host = accessoryHost, let root { root.addChild(host) }
        accessoryView.frame = accessoryContainer.bounds
        accessoryView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        accessoryContainer.addSubview(accessoryView)
        accessoryContainer.transparent = accessoryView
        if let host = accessoryHost, let root { host.didMove(toParent: root) }
    }

    fileprivate func layout(in view: UIView) {
        let bounds = view.bounds
        backdrop.frame = bounds
        hero.frame = bounds
        accessoryContainer.frame = bounds

        let width = bounds.width + configuration.pageSpacing
        let pagerFrame = CGRect(x: -configuration.pageSpacing / 2, y: 0, width: width, height: bounds.height)
        guard pager.frame != pagerFrame else { return }
        isLayingOut = true
        pager.frame = pagerFrame
        pager.contentSize = CGSize(width: width * CGFloat(count), height: bounds.height)
        pager.contentOffset = CGPoint(x: width * CGFloat(index), y: 0)
        for (i, page) in pages { page.frame = pageFrame(i) }
        isLayingOut = false
        updatePages()

        switch phase {
        case .opening, .restoring: retargetHero()
        case .presented, .dragging, .closing, .closed: break
        }
    }

    private func pageFrame(_ i: Int) -> CGRect {
        CGRect(x: pager.bounds.width * CGFloat(i) + configuration.pageSpacing / 2, y: 0,
               width: pager.bounds.width - configuration.pageSpacing, height: pager.bounds.height)
    }

    // MARK: Images

    private func image(_ i: Int) -> PreviewImage {
        if let image = images[i] { return image }
        let image = imageProvider(i)
        images[i] = image
        return image
    }

    /// The best image to draw for an index right now, starting its load if needed.
    private func currentImage(_ i: Int) -> UIImage? {
        if let image = loaded[i] { return image }
        startLoading(i)
        return loaded[i] ?? image(i).immediate ?? fallbacks[i]
    }

    private func startLoading(_ i: Int) {
        guard loads[i] == nil, loaded[i] == nil else { return }
        let source = image(i)
        if let key = source.key, let cached = PreviewImageLoader.cached(key) {
            loaded[i] = cached
            return
        }
        guard let load = source.load else { return }
        loads[i] = Task { [weak self] in
            guard let image = try? await load() else { return }
            let ready = source.key == nil ? await PreviewImageLoader.prepared(image) : image
            self?.didLoad(ready, at: i)
        }
    }

    private func didLoad(_ image: UIImage, at i: Int) {
        loaded[i] = image
        if let page = pages[i] {
            let wasShowing = page.image != nil
            page.setImage(image)
            if wasShowing { crossfade(page.imageView) }
        }
        if i == index, !hero.isHidden {
            hero.imageView.image = image
            crossfade(hero.imageView)
            retargetHero()
        }
    }

    private func crossfade(_ view: UIView) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.2
        view.layer.add(fade, forKey: "preview.fade")
    }

    // MARK: Pages

    private func updatePages() {
        guard pager.bounds.width > 0 else { return }
        let position = pager.contentOffset.x / pager.bounds.width
        let visible = Int(floor(position))...Int(ceil(position))
        let wanted = Set((visible.lowerBound - 1...visible.upperBound + 1).filter { (0..<count).contains($0) })
        for (i, page) in pages where !wanted.contains(i) {
            page.removeFromSuperview()
            pages[i] = nil
        }
        for i in wanted where pages[i] == nil {
            let page = PreviewPageView(frame: pageFrame(i))
            page.maximumZoomFactor = configuration.maximumZoomScale
            page.setImage(currentImage(i))
            pager.addSubview(page)
            pages[i] = page
        }
        // A page that has scrolled out of sight goes back to fitting the screen.
        for (i, page) in pages where !visible.contains(i) { page.resetZoom() }
    }

    fileprivate func pagerDidScroll() {
        guard !isLayingOut, pager.bounds.width > 0 else { return }
        updatePages()
        let i = Int((pager.contentOffset.x / pager.bounds.width).rounded())
        if (0..<count).contains(i), i != index { setIndex(i) }
    }

    private func setIndex(_ i: Int) {
        guard i != context.index else { return }
        context.index = i
        if phase != .closed, phase != .closing { hideSource() }
        onIndexChange?(i)
    }

    private var currentPage: PreviewPageView? { pages[index] }

    // MARK: Sources

    private func hideSource() {
        let source = sourceProvider(index)
        if hiddenSource?.view !== source?.view { hiddenSource?.setHidden(false) }
        source?.setHidden(true)
        hiddenSource = source
    }

    /// The thumbnail's frame in the viewer, if it is on screen.
    private func visibleFrame(of source: PreviewSource?) -> CGRect? {
        guard let frame = frame(of: source), let root = root?.view, frame.intersects(root.bounds) else { return nil }
        return frame
    }

    /// The thumbnail's frame in the viewer, on screen or not, while it is in a window.
    private func frame(of source: PreviewSource?) -> CGRect? {
        guard let view = source?.view, view.window != nil, let root = root?.view else { return nil }
        let frame = view.convert(view.bounds, to: root)
        return frame.width > 1 && frame.height > 1 ? frame : nil
    }

    /// A picture of the thumbnail as it is on screen, for when there is no image to fly yet.
    private func snapshot(_ source: PreviewSource?) -> UIImage? {
        guard let view = source?.view, let window = view.window else { return nil }
        let rect = view.convert(view.bounds, to: window)
        guard rect.width > 1, rect.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.opaque = false
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: window.bounds.size), afterScreenUpdates: false)
        }
    }

    // MARK: Opening and closing

    private var fittedFrame: CGRect {
        guard let root = root?.view else { return .zero }
        return root.bounds.placing(hero.imageView.image?.size ?? .zero, .fit)
    }

    private func open() {
        let source = sourceProvider(index)
        if currentImage(index) == nil, let snap = snapshot(source) { fallbacks[index] = snap }
        updatePages()
        currentPage?.setImage(currentImage(index))

        let image = currentImage(index)
        hero.imageView.image = image
        hero.isHidden = false
        phase = .opening
        hideSource()

        let fitted = fittedFrame
        let start = UIAccessibility.isReduceMotionEnabled ? nil : sourceState(source)
        setHero(start ?? .vanished(from: fitted))
        setAccessories(visible: true, delay: 0.06)
        animateHero(to: .presented(fitted), spring: configuration.transitionSpring) { [weak self] in
            self?.didSettlePresented()
        }
    }

    private func didSettlePresented() {
        phase = .presented
        currentPage?.setImage(currentImage(index))
        pager.isHidden = false
        hero.isHidden = true
        setAccessories(visible: true)
        root?.setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    /// Moves the image from the page into the hero, where it can be dragged and flown.
    private func liftHero() {
        guard let root = root?.view, let page = currentPage else { return }
        let image = page.imageView.convert(page.imageView.bounds, to: root)
        hero.imageView.image = page.image
        hero.isHidden = false
        setHero(HeroState(image: image, clip: image.intersection(root.bounds), cornerRadius: 0, backdrop: 1))
        pager.isHidden = true
    }

    private func close(velocity: CGPoint) {
        if phase == .presented { liftHero() }
        phase = .closing
        // From here the app has the touches and the keyboard again: the page can be scrolled while
        // the image flies home. Handing the key window back now, not when the viewer's window goes,
        // keeps that change from landing in the middle of a scroll and resetting it.
        window?.isUserInteractionEnabled = false
        if previousKeyWindow?.windowScene != nil { previousKeyWindow?.makeKey() }
        setAccessories(visible: false)
        onDismiss?()

        let source = sourceProvider(index)
        if hiddenSource?.view !== source?.view { hiddenSource?.setHidden(false) }
        hiddenSource = source
        source?.setHidden(true)
        closingSource = source

        let target = closedTarget(source)
        animateHero(to: target, spring: configuration.transitionSpring, velocity: velocity) { [weak self] in
            self?.didClose()
        }
        // Flying home to a thumbnail: follow it if the page moves under it.
        if target.backdrop == 0, target.opacity > 0, let frame = visibleFrame(of: source), let springs {
            landing = Landing(frame: frame, springs: springs)
        }
    }

    private func closedTarget(_ source: PreviewSource?) -> HeroState {
        (UIAccessibility.isReduceMotionEnabled ? nil : sourceState(source)) ?? .vanished(from: heroState.image)
    }

    /// The image laid over its thumbnail as the thumbnail draws it, if the thumbnail is on screen.
    private func sourceState(_ source: PreviewSource?, at frame: CGRect? = nil) -> HeroState? {
        guard let source, let frame = frame ?? visibleFrame(of: source), let size = hero.imageView.image?.size else { return nil }
        // A picture of the thumbnail already has its shape: it is drawn whole.
        let mode = fallbacks[index] != nil && loaded[index] == nil ? PreviewContentMode.fit : source.contentMode
        return .source(frame: frame, imageSize: size, mode: mode, cornerRadius: source.cornerRadius)
    }

    private func didClose() {
        phase = .closed
        closingSource?.setHidden(false)
        hiddenSource = nil
        landing = nil
        loads.values.forEach { $0.cancel() }
        onDidDismiss?()
        handOverOrFinish()
    }

    /// The image is home. The viewer's window stays, empty and letting every touch through,
    /// until the page the thumbnail is on has stopped scrolling: hiding a window over a scroll in
    /// progress makes the system lay the app's window out again, and a navigation bar with a
    /// large title then knocks the scroll off course (a visible jump under the finger).
    private func finish() {
        handoff = nil
        hero.isHidden = true
        backdrop.alpha = 0
        retiring = (scrollViews(around: closingSource?.view), CACurrentMediaTime())
        closingSource = nil
        ticker.start()
    }

    private func retire() {
        guard let (scrollViews, since) = retiring else { return }
        let atRest = scrollViews.allSatisfy { $0.window == nil || (!$0.isTracking && !$0.isDragging && !$0.isDecelerating) }
        guard atRest || CACurrentMediaTime() - since > 5 else { return }
        retiring = nil
        ticker.stop()
        window?.isHidden = true
        window = nil
        isPresented = false
        Self.retained[ObjectIdentifier(self)] = nil
    }

    private func scrollViews(around view: UIView?) -> [UIScrollView] {
        sequence(first: view?.superview) { $0?.superview }.compactMap { $0 as? UIScrollView }
    }

    /// The target of the running animation, worked out again (the image or the screen changed size).
    private func retargetHero() {
        guard springs != nil else { return }
        switch phase {
        case .opening, .restoring:
            springs?.retarget(HeroState.presented(fittedFrame).vector)
        case .closing:
            springs?.retarget(closedTarget(closingSource).vector)
        case .presented, .dragging, .closed:
            break
        }
        ticker.start()
    }

    // MARK: Dragging

    private func dismissAxis(for velocity: CGPoint) -> DismissDrag.Axis? {
        DismissDrag.axis(for: velocity, index: index, count: count)
    }

    fileprivate func canBeginDrag(velocity: CGPoint) -> Bool {
        guard let axis = dismissAxis(for: velocity) else { return false }
        dragAxis = axis
        switch phase {
        case .opening, .restoring:
            return true
        case .presented:
            guard let page = currentPage, !page.isZoomed else { return false }
            return !pager.isDragging && !pager.isDecelerating
        case .dragging, .closing, .closed:
            return false
        }
    }

    fileprivate func handlePan(_ pan: UIPanGestureRecognizer) {
        guard let root = root?.view else { return }
        switch pan.state {
        case .began:
            if phase == .presented { liftHero() }
            stopSprings()
            phase = .dragging
            drag = DismissDrag(start: heroState, anchor: pan.location(in: root), axis: dragAxis, container: root.bounds.size)
            setAccessories(visible: false)
        case .changed:
            guard let drag else { return }
            setHero(drag.state(translation: pan.translation(in: root)))
        case .ended, .cancelled, .failed:
            guard let drag else { return }
            self.drag = nil
            let t = pan.translation(in: root), v = pan.velocity(in: root)
            if pan.state == .ended, drag.closes(translation: t, velocity: v) {
                close(velocity: v)
            } else {
                phase = .restoring
                animateHero(to: .presented(fittedFrame), spring: configuration.restoreSpring, velocity: v) { [weak self] in
                    self?.didSettlePresented()
                }
            }
        default:
            break
        }
    }

    fileprivate func handleTap(_ tap: UITapGestureRecognizer) {
        guard phase == .presented else { return }
        if configuration.tapTogglesAccessories {
            context.accessoriesVisible.toggle()
            setAccessories(visible: true)
            root?.setNeedsUpdateOfHomeIndicatorAutoHidden()
        } else {
            dismiss()
        }
    }

    fileprivate func handleDoubleTap(_ tap: UITapGestureRecognizer) {
        guard phase == .presented, let page = currentPage else { return }
        page.toggleZoom(at: tap.location(in: page))
    }

    // MARK: Accessories

    private func setAccessories(visible: Bool, delay: TimeInterval = 0) {
        let alpha: CGFloat = visible && context.accessoriesVisible ? 1 : 0
        guard accessoryContainer.alpha != alpha else { return }
        UIView.animate(withDuration: alpha > 0 ? 0.25 : 0.15, delay: delay, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.accessoryContainer.alpha = alpha
        }
    }

    fileprivate var hidesHomeIndicator: Bool { !statusBarFollowsApp && !context.accessoriesVisible }

    #if !os(visionOS)
    /// Light over the backdrop; while closing, whatever the app underneath asks for.
    fileprivate var statusBarStyle: UIStatusBarStyle {
        guard statusBarFollowsApp, let app = appStatusBarController(\.childForStatusBarStyle) else { return .lightContent }
        return app.preferredStatusBarStyle
    }

    fileprivate var statusBarHidden: Bool {
        guard statusBarFollowsApp, let app = appStatusBarController(\.childForStatusBarHidden) else { return false }
        return app.prefersStatusBarHidden
    }

    /// The view controller of the app's window that decides its status bar, the way UIKit finds it.
    private func appStatusBarController(_ child: KeyPath<UIViewController, UIViewController?>) -> UIViewController? {
        var controller = previousKeyWindow?.rootViewController
        while let current = controller {
            if let presented = current.presentedViewController, !presented.isBeingDismissed,
               presented.modalPresentationCapturesStatusBarAppearance || presented.modalPresentationStyle == .fullScreen {
                controller = presented
            } else if let next = current[keyPath: child] {
                controller = next
            } else {
                return current
            }
        }
        return nil
    }
    #endif

    // MARK: Hero animation

    private func setHero(_ state: HeroState) {
        heroState = state
        hero.apply(state)
        backdrop.alpha = state.backdrop
        springs?.set(values: state.vector)
    }

    private func animateHero(to target: HeroState, spring: PreviewSpring, velocity: CGPoint = .zero, completion: @escaping () -> Void) {
        var springs = springs ?? SpringVector(values: heroState.vector, tolerances: HeroState.tolerances, spring: spring)
        if self.springs == nil || velocity != .zero {
            springs.set(values: heroState.vector, velocities: velocity == .zero ? nil : heroState.velocity(velocity, toward: target))
        }
        springs.retarget(target.vector, spring: spring)
        self.springs = springs
        springDone = completion
        ticker.start()
    }

    private func stopSprings() {
        ticker.stop()
        springs = nil
        springDone = nil
    }

    private func tick(_ dt: Double) {
        if retiring != nil { return retire() }
        if let handoff { return handOver(handoff) }
        guard var springs else { return ticker.stop() }
        if phase == .closing, var landing, let frame = frame(of: closingSource) {
            if !landing.follow(frame, springs: &springs), let target = sourceState(closingSource) {
                springs.retarget(target.vector)
            }
            self.landing = landing
        }
        let done = springs.step(dt)
        self.springs = springs
        heroState = HeroState(springs.values)
        hero.apply(heroState)
        backdrop.alpha = heroState.backdrop
        // Closing: the status bar turns back to the app's as the page shows through.
        if phase == .closing, !statusBarFollowsApp, heroState.backdrop < 0.5 {
            statusBarFollowsApp = true
            #if !os(visionOS)
            UIView.animate(withDuration: 0.2) { self.root?.setNeedsStatusBarAppearanceUpdate() }
            #endif
        }
        if done {
            let completion = springDone
            stopSprings()
            completion?()
        }
    }

    // MARK: Hand-over

    /// The thumbnail shows again a frame or two after it is told to (SwiftUI may take one more).
    /// Until it surely has, the landed image stays pinned on it, following it if the page is
    /// scrolling, so the two never part; then the image goes.
    private func handOverOrFinish() {
        guard heroState.opacity > 0, closingSource != nil else { return finish() }
        handoff = 4
        ticker.start()
    }

    private func handOver(_ frames: Int) {
        if let frame = frame(of: closingSource), let state = sourceState(closingSource, at: frame) { setHero(state) }
        if frames > 1 { handoff = frames - 1 } else { finish() }
    }

    // MARK: Keyboard

    fileprivate func handleKey(_ command: UIKeyCommand) {
        switch command.input {
        case UIKeyCommand.inputEscape: dismiss()
        case UIKeyCommand.inputLeftArrow: select(index - 1, animated: true)
        case UIKeyCommand.inputRightArrow: select(index + 1, animated: true)
        default: break
        }
    }

    // MARK: Gesture plumbing

    @MainActor private final class GestureTarget: NSObject {
        weak var controller: ImagePreviewController?
        init(_ controller: ImagePreviewController) { self.controller = controller }
        @objc func pan(_ g: UIPanGestureRecognizer) { controller?.handlePan(g) }
        @objc func tap(_ g: UITapGestureRecognizer) { controller?.handleTap(g) }
        @objc func doubleTap(_ g: UITapGestureRecognizer) { controller?.handleDoubleTap(g) }
    }

    @MainActor private final class GestureDelegate: NSObject, UIGestureRecognizerDelegate, UIScrollViewDelegate {
        weak var controller: ImagePreviewController?
        init(_ controller: ImagePreviewController) { self.controller = controller }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let controller, let pan = g as? UIPanGestureRecognizer, pan === controller.dismissPan else { return true }
            return controller.canBeginDrag(velocity: pan.velocity(in: pan.view))
        }

        // A touch on an accessory belongs to it alone.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let controller, let view = touch.view else { return true }
            return !view.isDescendant(of: controller.accessoryContainer)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { controller?.pagerDidScroll() }
    }
}

// MARK: - Views

/// The window's root: lays the viewer out and speaks for it to the system (status bar, keys).
private final class PreviewRootViewController: UIViewController {
    private let controller: ImagePreviewController

    init(controller: ImagePreviewController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        controller.load(into: self)
    }

    override func accessibilityPerformEscape() -> Bool {
        controller.dismiss()
        return true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        controller.layout(in: view)
    }

    #if !os(visionOS)
    override var preferredStatusBarStyle: UIStatusBarStyle { controller.statusBarStyle }
    override var prefersStatusBarHidden: Bool { controller.statusBarHidden }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var prefersHomeIndicatorAutoHidden: Bool { controller.hidesHomeIndicator }
    #endif

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand.inputEscape, UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].map {
            let command = UIKeyCommand(input: $0, modifierFlags: [], action: #selector(key(_:)))
            command.wantsPriorityOverSystemBehavior = true
            return command
        }
    }

    @objc private func key(_ command: UIKeyCommand) { controller.handleKey(command) }
}

/// Swipes between the images.
private final class PreviewPagerView: UIScrollView {
    var shouldBeginPan: (CGPoint) -> Bool = { _ in true }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === panGestureRecognizer, !shouldBeginPan(panGestureRecognizer.velocity(in: self)) { return false }
        return super.gestureRecognizerShouldBegin(g)
    }
}

/// The moving image: a clipping frame with rounded corners, the whole image inside it.
private final class HeroView: UIView {
    let clipView = UIView()
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipView.clipsToBounds = true
        clipView.layer.cornerCurve = .continuous
        imageView.contentMode = .scaleToFill
        imageView.accessibilityIgnoresInvertColors = true
        clipView.addSubview(imageView)
        addSubview(clipView)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ state: HeroState) {
        clipView.frame = state.clip
        clipView.layer.cornerRadius = min(state.cornerRadius, min(state.clip.width, state.clip.height) / 2)
        imageView.frame = state.image.offsetBy(dx: -state.clip.minX, dy: -state.clip.minY)
        clipView.alpha = state.opacity
    }
}

/// Lets touches through wherever the accessories draw nothing, so the images underneath can be
/// swiped, pinched and dragged around the buttons. A SwiftUI hosting view claims every touch
/// inside it; where it is the view hit, what is drawn near the touch decides.
final class PassthroughView: UIView {
    weak var transparent: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard alpha > 0.01 else { return nil }
        let hit = super.hitTest(point, with: event)
        if hit === self { return nil }
        if let transparent, hit === transparent, !transparent.drawsSomething(near: convert(point, to: transparent)) { return nil }
        return hit
    }
}

extension UIView {
    /// Whether anything visible is drawn within a fingertip of `point`.
    func drawsSomething(near point: CGPoint, radius: CGFloat = 10) -> Bool {
        let side = Int(radius * 2)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: 0, y: CGFloat(side))
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: radius - point.x, y: radius - point.y)
            layer.render(in: context)
            return true
        }
        guard drawn else { return false }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 8 }
    }
}
#endif
