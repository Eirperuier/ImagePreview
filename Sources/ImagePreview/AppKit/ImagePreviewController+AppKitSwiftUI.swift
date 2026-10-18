#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import SwiftUI

extension ImagePreviewController {
    /// Draws a SwiftUI view over the images as the accessories.
    public func setAccessories<Content: View>(_ content: Content) {
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        accessoryView = host
    }

    /// Draws a SwiftUI view built on the viewer's page over the images. Call before presenting.
    public func setPage<Content: View>(@ViewBuilder _ content: @escaping (ImagePreviewPage) -> Content) {
        setAccessories(PreviewPageHost(page: ImagePreviewPage(context: context), content: content))
    }
}

/// What is drawn over the images, as a SwiftUI view: a close button and the page indicator,
/// to which overlays can be added. Clicks on nothing of it reach the images.
public struct ImagePreviewPage: View {
    /// What the page can read (the index, the count) and do.
    public let context: ImagePreviewContext

    public var body: some View {
        ImagePreviewAccessories(context: context)
    }
}
#endif
