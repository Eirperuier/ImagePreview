#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import SwiftUI

extension ImagePreviewController {
    /// Draws a SwiftUI view over the images as the accessories.
    public func setAccessories<Content: View>(_ content: Content) {
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        accessoryView = host
    }
}
#endif
