import AVFoundation
import ImagePreview
import SwiftUI

#if canImport(UIKit)
typealias PlatformImage = UIImage
extension Image {
    init(platform image: PlatformImage) { self.init(uiImage: image) }
}
#else
typealias PlatformImage = NSImage
extension Image {
    init(platform image: PlatformImage) { self.init(nsImage: image) }
}
#endif

struct Photo: Identifiable {
    let id: String
    /// What the feed draws; also what the viewer draws until the full image is in.
    var thumbnail: PlatformImage?
    var image: PreviewMedia
    var aspectRatio: CGFloat
    var isVideo = false
}

struct Post: Identifiable {
    let id: String
    let author: String
    let text: String
    var photos: [Photo]
}

/// Drawn on the device, so the example works offline: a long screenshot, a landscape, a portrait, a square.
@MainActor
enum Artwork {
    static func render<V: View>(_ view: V, size: CGSize) -> PlatformImage {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        #if canImport(UIKit)
        return renderer.uiImage!
        #else
        return renderer.nsImage!
        #endif
    }

    static func photo(_ id: String, _ view: some View, size: CGSize) -> Photo {
        let image = render(view, size: size)
        return Photo(id: id, thumbnail: image, image: .image(PreviewImage(image)), aspectRatio: size.width / size.height)
    }

    static func landscape(_ hue: Double) -> some View {
        ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95), Color(hue: hue + 0.08, saturation: 0.7, brightness: 0.55)], startPoint: .top, endPoint: .bottom)
            Circle().fill(.white.opacity(0.85)).frame(width: 180).offset(x: 220, y: -130).blur(radius: 2)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 520))
                p.addLine(to: CGPoint(x: 260, y: 300))
                p.addLine(to: CGPoint(x: 420, y: 430))
                p.addLine(to: CGPoint(x: 640, y: 240))
                p.addLine(to: CGPoint(x: 960, y: 520))
                p.addLine(to: CGPoint(x: 960, y: 640))
                p.addLine(to: CGPoint(x: 0, y: 640))
            }
            .fill(Color(hue: hue + 0.15, saturation: 0.5, brightness: 0.3))
        }
    }

    static func screenshot() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("2011: one winter coat, a hundred and fifty. I remember the price because it took me three days to decide.")
                .font(.system(size: 34, weight: .medium))
            Text("2026: 336 million, decided in eleven seconds.")
                .font(.system(size: 34, weight: .medium))
            Divider()
            ForEach(0..<7) { i in
                HStack(alignment: .top, spacing: 14) {
                    Circle().fill(Color(hue: Double(i) / 7, saturation: 0.5, brightness: 0.85)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reader \(i + 1)").font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
                        Text(["Checking how many digits 336 million has.", "In 2002 I looked at a coat for two years before buying it.", "When I had a few hundred thousand I wanted a car; I bought nothing.", "The price stuck with me too.", "Eleven seconds is generous.", "Same coat, still wearing it.", "Bookmarked."][i])
                            .font(.system(size: 24))
                    }
                    Spacer()
                    Image(systemName: "heart.fill").foregroundStyle(.red).font(.system(size: 20))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(36)
        .foregroundStyle(.black)
        .background(.white)
    }

    static func pattern(_ hue: Double) -> some View {
        Canvas { context, size in
            let n = 8
            let w = size.width / CGFloat(n)
            for i in 0..<n {
                for j in 0..<n {
                    let rect = CGRect(x: CGFloat(i) * w, y: CGFloat(j) * w, width: w, height: w).insetBy(dx: 6, dy: 6)
                    let h = (hue + Double(i + j) / 30).truncatingRemainder(dividingBy: 1)
                    context.fill(Path(roundedRect: rect, cornerRadius: (i * j) % 3 == 0 ? w / 2 : 10), with: .color(Color(hue: h, saturation: 0.6, brightness: 0.9)))
                }
            }
        }
        .background(Color(white: 0.1))
    }

    static func portrait(_ hue: Double) -> some View {
        ZStack {
            RadialGradient(colors: [Color(hue: hue, saturation: 0.4, brightness: 1), Color(hue: hue + 0.5, saturation: 0.6, brightness: 0.25)], center: .init(x: 0.4, y: 0.35), startRadius: 10, endRadius: 700)
            Image(systemName: "leaf.fill").font(.system(size: 220)).foregroundStyle(.white.opacity(0.9)).rotationEffect(.degrees(-20))
        }
    }

    static func posts() -> [Post] {
        [
            Post(id: "a", author: "Lin", text: "Fifteen years between these two numbers.", photos: [
                photo("a1", landscape(0.58), size: CGSize(width: 960, height: 640)),
                photo("a2", screenshot(), size: CGSize(width: 640, height: 1180)),
            ]),
            Post(id: "b", author: "Mara", text: "One picture, nothing else.", photos: [
                photo("b1", landscape(0.05), size: CGSize(width: 960, height: 640)),
            ]),
            Post(id: "c", author: "Teo", text: "Three from the weekend.", photos: [
                photo("c1", portrait(0.3), size: CGSize(width: 600, height: 800)),
                photo("c2", pattern(0.6), size: CGSize(width: 640, height: 640)),
                photo("c3", landscape(0.75), size: CGSize(width: 960, height: 640)),
            ]),
            Post(id: "d", author: "Ines", text: "Four in a grid.", photos: [
                photo("d1", pattern(0.1), size: CGSize(width: 640, height: 640)),
                photo("d2", portrait(0.85), size: CGSize(width: 600, height: 800)),
                photo("d3", landscape(0.45), size: CGSize(width: 960, height: 640)),
                photo("d4", screenshot(), size: CGSize(width: 640, height: 1180)),
            ]),
        ]
    }

    /// Photos from the network: the thumbnail is fetched small for the feed, the viewer fetches the full one.
    static func remotePost() -> Post {
        let ids = [1015, 1025, 1039, 1043, 1069]
        return Post(id: "r", author: "Picsum", text: "From the network: the full images load after they open.", photos: ids.map { id in
            let url = URL(string: "https://picsum.photos/id/\(id)/2400/1600")!
            return Photo(id: "r\(id)", thumbnail: nil, image: .image(PreviewImage(url: url)), aspectRatio: 1.5)
        })
    }
}

/// A clip drawn on the device, so the example plays a video offline: the sun crossing the sky.
enum Clip {
    static let width = 960, height = 540, frames = 120

    struct Made: @unchecked Sendable {
        let url: URL
        let poster: CGImage
    }

    @MainActor static func post() async -> Post? {
        guard let clip = try? await make() else { return nil }
        #if canImport(UIKit)
        let poster = UIImage(cgImage: clip.poster)
        #else
        let poster = NSImage(cgImage: clip.poster, size: CGSize(width: width, height: height))
        #endif
        return Post(id: "v", author: "Sol", text: "A clip and a still.", photos: [
            Photo(id: "v1", thumbnail: poster, image: .video(PreviewVideo(url: clip.url, poster: poster)),
                  aspectRatio: CGFloat(width) / CGFloat(height), isVideo: true),
            Artwork.photo("v2", Artwork.landscape(0.12), size: CGSize(width: 960, height: 640)),
        ])
    }

    /// Four seconds of H.264, written to a temporary file.
    nonisolated static func make() async throws -> Made {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ImagePreviewExample-clip.mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(CGFloat(i) / CGFloat(frames - 1), in: context)
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }

        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        draw(0, in: context)
        return Made(url: url, poster: context.makeImage()!)
    }

    /// The frame at `t` (0 to 1): the sun rises on the left and sets on the right, the sky warming as it goes.
    nonisolated static func draw(_ t: CGFloat, in context: CGContext) {
        let w = CGFloat(width), h = CGFloat(height)
        let warmth = 1 - sin(.pi * t)
        let sky = [CGColor(red: 0.3 + 0.5 * warmth, green: 0.55, blue: 0.95 - 0.4 * warmth, alpha: 1),
                   CGColor(red: 0.98, green: 0.75 - 0.2 * warmth, blue: 0.55, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sky, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        let sun = CGPoint(x: w * (0.12 + 0.76 * t), y: h * (0.3 + 0.5 * sin(.pi * t)))
        context.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.88, alpha: 1))
        context.fillEllipse(in: CGRect(x: sun.x - 50, y: sun.y - 50, width: 100, height: 100))
        context.setFillColor(CGColor(red: 0.2, green: 0.16, blue: 0.3, alpha: 1))
        context.move(to: CGPoint(x: 0, y: 0))
        for (x, y) in [(0.0, 0.3), (0.25, 0.55), (0.42, 0.35), (0.66, 0.62), (1.0, 0.28), (1.0, 0.0)] {
            context.addLine(to: CGPoint(x: w * x, y: h * y))
        }
        context.fillPath()
    }
}
