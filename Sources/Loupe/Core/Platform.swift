#if canImport(UIKit)
import UIKit

/// The platform's image type: `UIImage` on iOS, iPadOS, Mac Catalyst and visionOS, `NSImage` on macOS.
public typealias LoupePlatformImage = UIImage
/// The platform's view type: `UIView`, or `NSView` on macOS.
public typealias LoupePlatformView = UIView
#elseif canImport(AppKit)
import AppKit

public typealias LoupePlatformImage = NSImage
public typealias LoupePlatformView = NSView
#endif
