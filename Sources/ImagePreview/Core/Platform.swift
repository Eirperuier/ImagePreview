#if canImport(UIKit)
import UIKit

/// The platform's image type: `UIImage` on iOS, iPadOS, Mac Catalyst and visionOS, `NSImage` on macOS.
public typealias PreviewPlatformImage = UIImage
/// The platform's view type: `UIView`, or `NSView` on macOS.
public typealias PreviewPlatformView = UIView
#elseif canImport(AppKit)
import AppKit

public typealias PreviewPlatformImage = NSImage
public typealias PreviewPlatformView = NSView
#endif
