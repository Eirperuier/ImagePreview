import SwiftUI

extension View {
    /// Shows `items` full screen while `selection` is set, opening out of the thumbnail marked
    /// with ``imagePreviewSource(_:cornerRadius:contentMode:)`` for the selected item and closing back into it.
    ///
    /// Swiping to another image updates `selection`; closing sets it to `nil`, and setting it to `nil` closes.
    ///
    /// ```swift
    /// @State private var opened: Photo.ID?
    ///
    /// LazyVGrid(columns: columns) {
    ///     ForEach(photos) { photo in
    ///         Thumbnail(photo)
    ///             .imagePreviewSource(photo.id, cornerRadius: 12)
    ///             .onTapGesture { opened = photo.id }
    ///     }
    /// }
    /// .imagePreview(selection: $opened, items: photos) { photo in
    ///     PreviewImage(url: photo.url, placeholder: photo.thumbnail)
    /// }
    /// ```
    public func imagePreview<Item: Identifiable>(
        selection: Binding<Item.ID?>,
        items: [Item],
        configuration: ImagePreviewConfiguration = .init(),
        image: @escaping (Item) -> PreviewImage
    ) -> some View {
        imagePreview(selection: selection, items: items, configuration: configuration, image: image) { page in
            ImagePreviewDefaultPage(page: page)
        }
    }

    /// Shows `items` full screen while `selection` is set, on a page you dress yourself.
    ///
    /// On iOS the page is a real page in a navigation controller: give it a `.toolbar` and a
    /// `.navigationTitle` for the bars over the images, which a tap hides and shows and a drag fades.
    ///
    /// ```swift
    /// .imagePreview(selection: $opened, items: photos) { photo in
    ///     PreviewImage(url: photo.url, placeholder: photo.thumbnail)
    /// } page: { page in
    ///     page.toolbar {
    ///         ToolbarItem(placement: .bottomBar) { ShareLink(item: photos[page.context.index].url) }
    ///     }
    /// }
    /// ```
    public func imagePreview<Item: Identifiable, Page: View>(
        selection: Binding<Item.ID?>,
        items: [Item],
        configuration: ImagePreviewConfiguration = .init(),
        image: @escaping (Item) -> PreviewImage,
        @ViewBuilder page: @escaping (ImagePreviewPage) -> Page
    ) -> some View {
        modifier(ImagePreviewModifier(selection: selection, items: items, configuration: configuration, image: image, page: page))
    }

    /// Marks this view as the thumbnail of the item with `id`: the viewer opens out of it and
    /// closes back into it, and it is hidden while its image is out.
    ///
    /// - Parameters:
    ///   - cornerRadius: The thumbnail's corner radius.
    ///   - contentMode: How the thumbnail draws its image: `.fill` for `scaledToFill`, `.fit` for `scaledToFit`.
    public func imagePreviewSource<ID: Hashable>(_ id: ID, cornerRadius: CGFloat = 0, contentMode: PreviewContentMode = .fill) -> some View {
        modifier(PreviewSourceModifier(id: AnyHashable(id), cornerRadius: cornerRadius, contentMode: contentMode))
    }
}

// MARK: - Sources

/// The thumbnails on screen, by item, and which of them are hidden because their image is out.
@MainActor @Observable
final class PreviewRegistry {
    private(set) var hidden: Set<AnyHashable> = []
    @ObservationIgnored private var anchors: [AnyHashable: Anchor] = [:]

    struct Anchor {
        weak var view: PreviewPlatformView?
        var cornerRadius: CGFloat
        var contentMode: PreviewContentMode
    }

    func register(_ id: AnyHashable, _ anchor: Anchor) { anchors[id] = anchor }

    func setHidden(_ id: AnyHashable, _ isHidden: Bool) {
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
    }

    func source(_ id: AnyHashable) -> PreviewSource? {
        guard let anchor = anchors[id], let view = anchor.view else { return nil }
        return PreviewSource(view: view, cornerRadius: anchor.cornerRadius, contentMode: anchor.contentMode) { [weak self] in
            self?.setHidden(id, $0)
        }
    }
}

struct PreviewSourceModifier: ViewModifier {
    let id: AnyHashable
    let cornerRadius: CGFloat
    let contentMode: PreviewContentMode
    @Environment(PreviewRegistry.self) private var registry: PreviewRegistry?

    func body(content: Content) -> some View {
        let isHidden = registry?.hidden.contains(id) == true
        content
            .opacity(isHidden ? 0 : 1)
            .animation(nil, value: isHidden)
            .background {
                if let registry {
                    PreviewAnchorView(id: id, cornerRadius: cornerRadius, contentMode: contentMode, registry: registry)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// An empty platform view the size of the thumbnail, through which its frame on screen is read.
struct PreviewAnchorView {
    let id: AnyHashable
    let cornerRadius: CGFloat
    let contentMode: PreviewContentMode
    let registry: PreviewRegistry

    @MainActor func update(_ view: PreviewPlatformView) {
        registry.register(id, .init(view: view, cornerRadius: cornerRadius, contentMode: contentMode))
    }
}

/// An empty platform view in the hierarchy, from which the viewer finds its window.
struct PreviewHostView {
    let presenter: PreviewPresenter
}

#if canImport(UIKit)
extension PreviewAnchorView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        update(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { update(view) }
}

extension PreviewHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        presenter.host = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { presenter.host = view }
}
#elseif canImport(AppKit)
extension PreviewAnchorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PreviewInertView()
        update(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { update(view) }
}

extension PreviewHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = PreviewInertView()
        presenter.host = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { presenter.host = view }
}

/// Takes no clicks.
final class PreviewInertView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

// MARK: - Presenting

/// Opens, moves and closes the viewer as the selection changes.
@MainActor
final class PreviewPresenter {
    weak var host: PreviewPlatformView?
    private var controller: ImagePreviewController?
    private var shownID: AnyHashable?

    func update<Item: Identifiable, Page: View>(
        selection: Binding<Item.ID?>,
        items: [Item],
        configuration: ImagePreviewConfiguration,
        registry: PreviewRegistry,
        image: @escaping (Item) -> PreviewImage,
        page: @escaping (ImagePreviewPage) -> Page
    ) {
        let selected = selection.wrappedValue
        guard let selected else {
            controller?.dismiss()
            return
        }
        guard let index = items.firstIndex(where: { $0.id == selected }) else { return }
        if let controller, controller.isPresented, !controller.isClosing {
            if shownID != AnyHashable(selected) {
                shownID = AnyHashable(selected)
                controller.select(index, animated: false)
            }
            return
        }
        guard let host else { return }
        let ids = items.map { AnyHashable($0.id) }
        let controller = ImagePreviewController(count: items.count, index: index, configuration: configuration) { i in
            image(items[i])
        } source: { [weak registry] i in
            registry?.source(ids[i])
        }
        controller.onIndexChange = { [weak self] i in
            self?.shownID = ids[i]
            selection.wrappedValue = items[i].id
        }
        controller.onDismiss = { [weak self, weak controller] in
            guard let self, self.controller === controller else { return }
            self.shownID = nil
            if selection.wrappedValue != nil { selection.wrappedValue = nil }
        }
        controller.setPage(page)
        self.controller = controller
        shownID = AnyHashable(selected)
        controller.present(from: host)
    }
}

struct ImagePreviewModifier<Item: Identifiable, Page: View>: ViewModifier {
    let selection: Binding<Item.ID?>
    let items: [Item]
    let configuration: ImagePreviewConfiguration
    let image: (Item) -> PreviewImage
    let page: (ImagePreviewPage) -> Page
    @State private var registry = PreviewRegistry()
    @State private var presenter = PreviewPresenter()

    func body(content: Content) -> some View {
        content
            .environment(registry)
            .background { PreviewHostView(presenter: presenter).allowsHitTesting(false) }
            .onChange(of: selection.wrappedValue, initial: true) {
                presenter.update(
                    selection: selection, items: items, configuration: configuration,
                    registry: registry, image: image, page: page
                )
            }
    }
}

// MARK: - Page

/// Builds the page in a body, so what it reads of the context (the index) keeps it up to date.
struct PreviewPageHost<Content: View>: View {
    let page: ImagePreviewPage
    let content: (ImagePreviewPage) -> Content

    var body: some View { content(page) }
}

/// The page the viewer shows unless you give your own: where you are among the images, as the title.
struct ImagePreviewDefaultPage: View {
    let page: ImagePreviewPage

    var body: some View {
        let context = page.context
        let title = page.navigationTitle(context.count > 1 ? Text("\(context.index + 1) / \(context.count)") : Text(verbatim: ""))
        #if canImport(UIKit)
        title.navigationBarTitleDisplayMode(.inline)
        #else
        title
        #endif
    }
}

/// A button that closes the viewer, for the page's toolbar: the bar's close button on iOS.
public struct ImagePreviewCloseButton: View {
    let context: ImagePreviewContext

    public init(context: ImagePreviewContext) {
        self.context = context
    }

    public var body: some View {
        #if canImport(UIKit)
        // The bar's own close button.
        if #available(iOS 26.0, visionOS 26.0, *) {
            Button(role: .close) { context.dismiss() }
        } else {
            Button { context.dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel(Text("Close"))
        }
        #else
        Button { context.dismiss() } label: { Label("Close", systemImage: "xmark") }
        #endif
    }
}

/// Dots for a few images, "3 of 12" for many.
public struct ImagePreviewPageIndicator: View {
    let context: ImagePreviewContext

    public init(context: ImagePreviewContext) {
        self.context = context
    }

    public var body: some View {
        Group {
            if context.count <= 9 {
                HStack(spacing: 7) {
                    ForEach(0..<context.count, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(i == context.index ? 1 : 0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                Text("\(context.index + 1) / \(context.count)")
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
        .animation(.easeOut(duration: 0.15), value: context.index)
        .accessibilityElement()
        .accessibilityLabel(Text("\(context.index + 1) of \(context.count)"))
    }
}
