import AVFoundation
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

@MainActor @Test func aVideoShowsItsPosterUntilItsFirstFrameIsIn() async throws {
    let url = try await movie(width: 64, height: 48, frames: 6)
    defer { try? FileManager.default.removeItem(at: url) }
    let poster = image(width: 8, height: 6)
    let content = VideoContent(PreviewVideo(url: url, poster: poster))
    #expect(content.still === poster)

    await withCheckedContinuation { done in
        content.load { done.resume() }
    }
    #expect(content.still?.size == CGSize(width: 64, height: 48))
}

/// A short H.264 movie of solid frames.
private func movie(width: Int, height: Int, frames: Int) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for i in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        adaptor.append(try #require(buffer), withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
    }
    input.markAsFinished()
    await writer.finishWriting()
    try #require(writer.status == .completed)
    return url
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
