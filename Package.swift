// swift-tools-version: 6.0

import PackageDescription

/// ImagePreview: a photo viewer that opens from the thumbnail you tapped and closes back into it.
/// iPhone, iPad, Mac (Catalyst and AppKit) and Vision Pro, with a SwiftUI and a UIKit/AppKit API.
let package = Package(
    name: "ImagePreview",
    platforms: [.iOS(.v17), .macCatalyst(.v17), .macOS(.v14), .visionOS(.v1)],
    products: [
        .library(name: "ImagePreview", targets: ["ImagePreview"]),
    ],
    targets: [
        .target(name: "ImagePreview", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ImagePreviewTests", dependencies: ["ImagePreview"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
