#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import SwiftUI

extension ImagePreviewController {
    /// Makes the viewer's page a SwiftUI view built around the images: its `.navigationTitle` goes on the
    /// window's title bar while the images cover it, and its `.toolbar` on the window's toolbar if the
    /// window has one. Call before presenting.
    public func setPage<Content: View>(@ViewBuilder _ content: @escaping (ImagePreviewPage) -> Content) {
        setPage(actions: { _ in EmptyView() }, content)
    }

    /// Makes the viewer's page a SwiftUI view built around the images, with `actions` (buttons for the
    /// image on screen) beside the close button: on the window's toolbar if it has one, in its title bar
    /// otherwise. Call before presenting.
    public func setPage<Actions: View, Content: View>(
        @ViewBuilder actions: @escaping (ImagePreviewContext) -> Actions,
        @ViewBuilder _ content: @escaping (ImagePreviewPage) -> Content
    ) {
        let context = context
        let actions: (() -> AnyView)? = Actions.self == EmptyView.self ? nil : { AnyView(actions(context)) }
        let host = PreviewHostingView(rootView: PreviewPageHost(page: ImagePreviewPage(context: context, stage: stage, actions: actions), content: content))
        host.controller = self
        host.sceneBridgingOptions = []
        pageView = host
        // The title and toolbar come from the same page built again without the images, in a view of
        // its own that bridges them to the window: a hosting view cannot start bridging once it is showing.
        makeTitlebar = { toolbar in
            let bar = NSHostingView(rootView: PreviewPageHost(page: ImagePreviewPage(context: context, stage: nil, actions: actions), content: content))
            bar.sceneBridgingOptions = toolbar ? [.toolbars, .title] : [.title]
            return bar
        }
        makeTitlebarControls = {
            let controls = NSHostingView(rootView: PreviewTitlebarControls(context: context, actions: actions))
            controls.frame.size = controls.fittingSize
            return controls
        }
    }
}

/// While the image flies home, the window underneath takes clicks and scrolls again.
private final class PreviewHostingView<Content: View>: NSHostingView<Content> {
    weak var controller: ImagePreviewController?

    override func hitTest(_ point: NSPoint) -> NSView? {
        controller?.isClosing == true ? nil : super.hitTest(point)
    }
}

/// The images, as a SwiftUI view: give it a `.navigationTitle`, a `.toolbar`, or overlays.
///
/// The title is the window's while the images cover it. In a window with a toolbar, the close button,
/// the actions and the page's `.toolbar` go on it; a window without one keeps its compact title bar,
/// with the actions and the close button at its end. A click on an image hides and shows them.
public struct ImagePreviewPage: View {
    /// What the page can read (the index, the count) and do.
    public let context: ImagePreviewContext
    /// The stage; none in the page built for the title bar alone.
    let stage: NSView?
    let actions: (() -> AnyView)?

    public var body: some View {
        Group {
            if let stage {
                PreviewStage(stage: stage).ignoresSafeArea()
            } else {
                Color.clear
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ImagePreviewCloseButton(context: context)
            }
            if let actions {
                ToolbarItemGroup(placement: .primaryAction) { actions() }
            }
        }
        .modifier(HiddenToolbarBackground())
    }
}

/// The actions and the close button, at the end of a title bar without a toolbar.
private struct PreviewTitlebarControls: View {
    let context: ImagePreviewContext
    let actions: (() -> AnyView)?

    var body: some View {
        HStack(spacing: 4) {
            actions?()
            ImagePreviewCloseButton(context: context)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.accessoryBar)
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
}

/// The images go under the toolbar as they are.
private struct HiddenToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content.toolbarBackground(.hidden, for: .windowToolbar)
        }
    }
}

/// Puts the viewer's stage (backdrop, pages, the image in flight) in the SwiftUI page.
private struct PreviewStage: NSViewRepresentable {
    let stage: NSView

    func makeNSView(context: Context) -> NSView { stage }
    func updateNSView(_ view: NSView, context: Context) {}
}
#endif
