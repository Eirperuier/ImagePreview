import SwiftUI

extension View {
    /// Shows `items` full screen while `selection` is set, opening out of the thumbnail marked
    /// with ``loupeSource(_:cornerRadius:contentMode:)`` for the selected item and closing back into it.
    ///
    /// Swiping to another image updates `selection`; closing sets it to `nil`, and setting it to `nil` closes.
    ///
    /// ```swift
    /// @State private var opened: Photo.ID?
    ///
    /// LazyVGrid(columns: columns) {
    ///     ForEach(photos) { photo in
    ///         Thumbnail(photo)
    ///             .loupeSource(photo.id, cornerRadius: 12)
    ///             .onTapGesture { opened = photo.id }
    ///     }
    /// }
    /// .loupe(selection: $opened, items: photos) { photo in
    ///     LoupeImage(url: photo.url, placeholder: photo.thumbnail)
    /// }
    /// ```
    public func loupe<Item: Identifiable>(
        selection: Binding<Item.ID?>,
        items: [Item],
        configuration: LoupeConfiguration = .init(),
        image: @escaping (Item) -> LoupeImage
    ) -> some View {
        loupe(selection: selection, items: items, configuration: configuration, image: image) { context in
            LoupeAccessories(context: context)
        }
    }

    /// Shows `items` full screen while `selection` is set, with your own accessories drawn over the images.
    ///
    /// The accessories cover the screen; touches that land on nothing of theirs reach the images.
    /// A tap hides and shows them, and they fade while an image is dragged.
    public func loupe<Item: Identifiable, Accessories: View>(
        selection: Binding<Item.ID?>,
        items: [Item],
        configuration: LoupeConfiguration = .init(),
        image: @escaping (Item) -> LoupeImage,
        @ViewBuilder accessories: @escaping (LoupeContext) -> Accessories
    ) -> some View {
        modifier(LoupeModifier(selection: selection, items: items, configuration: configuration, image: image, accessories: accessories))
    }

    /// Marks this view as the thumbnail of the item with `id`: the viewer opens out of it and
    /// closes back into it, and it is hidden while its image is out.
    ///
    /// - Parameters:
    ///   - cornerRadius: The thumbnail's corner radius.
    ///   - contentMode: How the thumbnail draws its image: `.fill` for `scaledToFill`, `.fit` for `scaledToFit`.
    public func loupeSource<ID: Hashable>(_ id: ID, cornerRadius: CGFloat = 0, contentMode: LoupeContentMode = .fill) -> some View {
        modifier(LoupeSourceModifier(id: AnyHashable(id), cornerRadius: cornerRadius, contentMode: contentMode))
    }
}

// MARK: - Sources

/// The thumbnails on screen, by item, and which of them are hidden because their image is out.
@MainActor @Observable
final class LoupeRegistry {
    private(set) var hidden: Set<AnyHashable> = []
    @ObservationIgnored private var anchors: [AnyHashable: Anchor] = [:]

    struct Anchor {
        weak var view: LoupePlatformView?
        var cornerRadius: CGFloat
        var contentMode: LoupeContentMode
    }

    func register(_ id: AnyHashable, _ anchor: Anchor) { anchors[id] = anchor }

    func setHidden(_ id: AnyHashable, _ isHidden: Bool) {
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
    }

    func source(_ id: AnyHashable) -> LoupeSource? {
        guard let anchor = anchors[id], let view = anchor.view else { return nil }
        return LoupeSource(view: view, cornerRadius: anchor.cornerRadius, contentMode: anchor.contentMode) { [weak self] in
            self?.setHidden(id, $0)
        }
    }
}

struct LoupeSourceModifier: ViewModifier {
    let id: AnyHashable
    let cornerRadius: CGFloat
    let contentMode: LoupeContentMode
    @Environment(LoupeRegistry.self) private var registry: LoupeRegistry?

    func body(content: Content) -> some View {
        let isHidden = registry?.hidden.contains(id) == true
        content
            .opacity(isHidden ? 0 : 1)
            .animation(nil, value: isHidden)
            .background {
                if let registry {
                    LoupeAnchorView(id: id, cornerRadius: cornerRadius, contentMode: contentMode, registry: registry)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// An empty platform view the size of the thumbnail, through which its frame on screen is read.
struct LoupeAnchorView {
    let id: AnyHashable
    let cornerRadius: CGFloat
    let contentMode: LoupeContentMode
    let registry: LoupeRegistry

    @MainActor func update(_ view: LoupePlatformView) {
        registry.register(id, .init(view: view, cornerRadius: cornerRadius, contentMode: contentMode))
    }
}

/// An empty platform view in the hierarchy, from which the viewer finds its window.
struct LoupeHostView {
    let presenter: LoupePresenter
}

#if canImport(UIKit)
extension LoupeAnchorView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        update(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { update(view) }
}

extension LoupeHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        presenter.host = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { presenter.host = view }
}
#elseif canImport(AppKit)
extension LoupeAnchorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = LoupeInertView()
        update(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { update(view) }
}

extension LoupeHostView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = LoupeInertView()
        presenter.host = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { presenter.host = view }
}

/// Takes no clicks.
final class LoupeInertView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

// MARK: - Presenting

/// Opens, moves and closes the viewer as the selection changes.
@MainActor
final class LoupePresenter {
    weak var host: LoupePlatformView?
    private var controller: LoupeController?
    private var shownID: AnyHashable?

    func update<Item: Identifiable, Accessories: View>(
        selection: Binding<Item.ID?>,
        items: [Item],
        configuration: LoupeConfiguration,
        registry: LoupeRegistry,
        image: @escaping (Item) -> LoupeImage,
        accessories: @escaping (LoupeContext) -> Accessories
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
        let controller = LoupeController(count: items.count, index: index, configuration: configuration) { i in
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
        controller.setAccessories(accessories(controller.context))
        self.controller = controller
        shownID = AnyHashable(selected)
        controller.present(from: host)
    }
}

struct LoupeModifier<Item: Identifiable, Accessories: View>: ViewModifier {
    let selection: Binding<Item.ID?>
    let items: [Item]
    let configuration: LoupeConfiguration
    let image: (Item) -> LoupeImage
    let accessories: (LoupeContext) -> Accessories
    @State private var registry = LoupeRegistry()
    @State private var presenter = LoupePresenter()

    func body(content: Content) -> some View {
        content
            .environment(registry)
            .background { LoupeHostView(presenter: presenter).allowsHitTesting(false) }
            .onChange(of: selection.wrappedValue, initial: true) {
                presenter.update(
                    selection: selection, items: items, configuration: configuration,
                    registry: registry, image: image, accessories: accessories
                )
            }
    }
}

// MARK: - Accessories

/// The accessories the viewer draws unless you give your own: a close button and, for more
/// than one image, where you are among them.
public struct LoupeAccessories: View {
    let context: LoupeContext

    public init(context: LoupeContext) {
        self.context = context
    }

    public var body: some View {
        VStack {
            HStack {
                LoupeCloseButton(context: context)
                Spacer()
            }
            Spacer()
            if context.count > 1 {
                LoupePageIndicator(context: context)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// A round button that closes the viewer.
public struct LoupeCloseButton: View {
    let context: LoupeContext

    public init(context: LoupeContext) {
        self.context = context
    }

    public var body: some View {
        Button {
            context.dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
        .keyboardShortcut(.cancelAction)
    }
}

/// Dots for a few images, "3 of 12" for many.
public struct LoupePageIndicator: View {
    let context: LoupeContext

    public init(context: LoupeContext) {
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
