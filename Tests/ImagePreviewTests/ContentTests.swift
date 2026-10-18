import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ImagePreview
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor @Test func anImageShowsItsPlaceholderUntilTheFullImageArrives() async throws {
    let placeholder = image(width: 30, height: 20)
    let full = image(width: 300, height: 200)
    let content = ImageContent(PreviewImage(placeholder: placeholder) { full })
    #expect(content.still === placeholder)

    await withCheckedContinuation { done in
        content.load { done.resume() }
    }
    #expect(content.still?.size == CGSize(width: 300, height: 200))
}

@MainActor @Test func anImageAtAURLHasNoStillUntilItIsDecoded() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
    try png(width: 3, height: 2, to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let content = ImageContent(PreviewImage(url: url))
    #expect(content.still == nil)
    await withCheckedContinuation { done in
        content.load { done.resume() }
    }
    #expect(content.still?.size == CGSize(width: 3, height: 2))
    // Decoded once: the next viewer has it at once.
    #expect(ImageContent(PreviewImage(url: url)).still != nil)
}

private func cgImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func image(width: Int, height: Int) -> PreviewPlatformImage {
    #if canImport(UIKit)
    UIImage(cgImage: cgImage(width: width, height: height), scale: 1, orientation: .up)
    #else
    NSImage(cgImage: cgImage(width: width, height: height), size: CGSize(width: width, height: height))
    #endif
}

private func png(width: Int, height: Int, to url: URL) throws {
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cgImage(width: width, height: height), nil)
    #expect(CGImageDestinationFinalize(destination))
}
