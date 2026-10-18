# ImagePreview

A photo viewer for Apple platforms that opens out of the thumbnail you tapped and closes back into it.

- **Seamless.** The image grows out of its thumbnail (crop, corner radius and all) and lands back in it exactly; the thumbnail hides while its image is out.
- **Follows your finger.** Drag an image up or down, or sideways past the first or last image: it moves with the finger, shrinks about the point you grabbed and lets the screen underneath show through. Let go and it flies home carrying your flick, or springs back if the drag was short.
- **Interruptible.** Every transition is a spring on the same state, so a drag can catch the image mid-flight and a new target never makes it jump.
- **Responsive.** The transition starts on the tap's frame from the thumbnail you already have; full images decode off the main thread and cross-fade in.
- **A real page.** The viewer is a page with the system's bars: on iOS a view controller presented in a navigation controller of its own, on the Mac the window's own title bar while the images cover it, in the window's own style (a compact title bar stays compact).
- **Everywhere.** iPhone, iPad, Mac (native AppKit and Mac Catalyst) and Apple Vision Pro, with a SwiftUI and a UIKit/AppKit API.

| | iOS · iPadOS · Catalyst · visionOS | macOS |
|---|---|---|
| Move between images | swipe | two-finger swipe, drag, ← → |
| Zoom | pinch, double-tap | pinch, double-click |
| Close | drag up or down, or sideways past the first or last image; close button | the same with two fingers or the mouse; click outside the image, Esc, Space |
| Bars and controls | tap to hide and show | click the image to hide and show |

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/Eirperuier/ImagePreview.git", from: "0.3.2")
```

Requires iOS 17, Mac Catalyst 17, macOS 14 or visionOS 1.

## SwiftUI

Mark each thumbnail with `imagePreviewSource`, and attach `imagePreview` to a view that contains them:

```swift
import ImagePreview

struct Gallery: View {
    let photos: [Photo]
    @State private var opened: Photo.ID?

    var body: some View {
        LazyVGrid(columns: columns) {
            ForEach(photos) { photo in
                Image(uiImage: photo.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .imagePreviewSource(photo.id, cornerRadius: 12)
                    .onTapGesture { opened = photo.id }
            }
        }
        .imagePreview(selection: $opened, items: photos) { photo in
            PreviewImage(url: photo.url, placeholder: photo.thumbnail)
        }
    }
}
```

`selection` follows the viewer: swiping changes it, closing sets it to `nil`, and setting it to `nil` closes the viewer.

### Actions

Buttons for the image on screen go beside the close button, where each platform puts a page's buttons: on iOS on the navigation bar; on the Mac on the window's toolbar if it has one, at the end of its title bar if not.

```swift
.imagePreview(selection: $opened, items: photos) { photo in
    PreviewImage(url: photo.url, placeholder: photo.thumbnail)
} actions: { photo in
    ShareLink(item: photo.url)
}
```

### The page

On iOS, iPadOS, Mac Catalyst and visionOS the viewer is a page in its own navigation controller. It has the system close button on the navigation bar and, for several images, where you are as the title. Dress the page yourself with the `page` closure: its `.toolbar` and `.navigationTitle` go on the system bars, which a tap hides and shows and a drag fades. `page.context` gives the index, the count, `dismiss()` and `select(_:)`:

```swift
.imagePreview(selection: $opened, items: photos) { photo in
    PreviewImage(url: photo.url, placeholder: photo.thumbnail)
} page: { page in
    page.navigationTitle(photos[page.context.index].title)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                ShareLink(item: photos[page.context.index].url)
            }
        }
}
```

On macOS the viewer lays itself over the window's content, and while the images cover the window its title bar is the page's, drawn dark over the backdrop. The window keeps its style: macOS draws a window with a toolbar with larger corners than one with a compact title bar, so a window with a toolbar shows the page's toolbar (the close button, the actions and the page's `.toolbar`), and one without keeps its compact title bar, with the page's title and the actions and close button at its end; there the page's `.toolbar` is not shown. The window gets its own title bar back as soon as anything of it shows through, when an image is dragged or the viewer closes.

## UIKit and AppKit

```swift
let preview = ImagePreviewController(count: photos.count, index: tappedIndex) { index in
    PreviewImage(url: photos[index].url, placeholder: cells[index].imageView.image)
} source: { index in
    collectionView.cellForItem(at: IndexPath(item: index, section: 0)).map {
        PreviewSource(view: ($0 as! PhotoCell).imageView, cornerRadius: 8)
    }
}
preview.onIndexChange = { index in
    collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredVertically, animated: false)
}
preview.present(from: view)
```

The source closure is asked again when the viewer closes, so after scrolling the collection view to the image on screen, the image lands in the right cell. If there is no thumbnail on screen, the image fades out where it is.

On iOS, put buttons on the bars through `preview.page.navigationItem` and `preview.page.toolbarItems`; on macOS, set `preview.title` and `preview.actionsView`. On both, `setPage(actions:_:)` builds the page in SwiftUI before presenting.

## Images

`PreviewImage` is what to show for one item:

- `PreviewImage(image)`: an image in memory.
- `PreviewImage(url:placeholder:)`: a remote or file URL, decoded off the main thread (orientation applied, longest side at most 4096 px) and kept in a small cache.
- `PreviewImage(placeholder:load:)`: your own loader.

Pass the thumbnail you already have as the `placeholder`: the transition starts from it on the first frame and the full image cross-fades in when it arrives. Without one, the viewer starts from a picture of the thumbnail as it is on screen.

## Configuration

```swift
var configuration = ImagePreviewConfiguration()
configuration.backgroundColor = CGColor(gray: 0, alpha: 1)
configuration.pageSpacing = 16
configuration.maximumZoomScale = 4
configuration.transitionSpring = PreviewSpring(response: 0.36, dampingRatio: 1)
configuration.restoreSpring = PreviewSpring(response: 0.32, dampingRatio: 0.86)
configuration.tapTogglesAccessories = true   // the bars; false: a tap closes the viewer
```

With Reduce Motion on, the viewer fades in and out in place instead of flying.

## Example

`Example/ImagePreviewExample.xcodeproj` is a feed of posts with one to five images, drawn on the device, plus a post loaded from the network. It runs on iPhone, iPad, Mac and Vision Pro. `ImagePreviewExampleUITests` drives the gestures at finger speed; record the simulator while it runs (`xcrun simctl io booted recordVideo`) to see them frame by frame.

## License

MIT
