#if canImport(UIKit)
import SwiftUI

extension ImagePreviewController {
    /// Makes the viewer's page a SwiftUI view built around the images, so its `.toolbar` and
    /// `.navigationTitle` go on the viewer's navigation bar and toolbar. Call before presenting.
    public func setPage<Content: View>(@ViewBuilder _ content: @escaping (ImagePreviewPage) -> Content) {
        let host = PreviewHostingController(rootView: PreviewPageHost(page: ImagePreviewPage(context: context, stage: stage), content: content))
        host.view.backgroundColor = .clear
        pageController = host
    }
}

/// Shows the toolbar when SwiftUI puts items on it.
private final class PreviewHostingController<Content: View>: UIHostingController<Content> {
    override func setToolbarItems(_ items: [UIBarButtonItem]?, animated: Bool) {
        super.setToolbarItems(items, animated: animated)
        (navigationController as? PreviewNavigationController)?.updateToolbar()
    }
}

/// The images, as a SwiftUI view: give it a `.toolbar`, a `.navigationTitle`, or overlays.
///
/// It has a close button on the navigation bar; the bars hide and show with a tap and fade while an image is dragged.
public struct ImagePreviewPage: View {
    /// What the page can read (the index, the count) and do.
    public let context: ImagePreviewContext
    let stage: UIViewController

    public var body: some View {
        PreviewStage(stage: stage)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ImagePreviewCloseButton(context: context)
                }
            }
    }
}

/// Puts the viewer's stage (backdrop, pages, the image in flight) in the SwiftUI page.
private struct PreviewStage: UIViewControllerRepresentable {
    let stage: UIViewController

    func makeUIViewController(context: Context) -> UIViewController { stage }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif
