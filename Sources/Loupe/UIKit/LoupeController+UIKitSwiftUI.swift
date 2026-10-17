#if canImport(UIKit)
import SwiftUI

extension LoupeController {
    /// Draws a SwiftUI view over the images as the accessories.
    public func setAccessories<Content: View>(_ content: Content) {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        accessoryHost = host
        accessoryView = host.view
    }
}
#endif
