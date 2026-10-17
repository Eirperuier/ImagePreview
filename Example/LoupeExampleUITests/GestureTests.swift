import XCTest

/// Drives the viewer with finger-speed gestures, so a recording of the screen shows how it moves.
/// Run with the screen recorded (`xcrun simctl io booted recordVideo`) and look at the frames.
final class GestureTests: XCTestCase {
    @MainActor
    func testGestures() throws {
        let app = XCUIApplication()
        app.launch()
        let images = app.images
        XCTAssertTrue(images.element(boundBy: 0).waitForExistence(timeout: 15))
        let first = images.element(boundBy: 0)
        let screen = app.windows.firstMatch
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }

        // Open, then swipe to the second image and back.
        first.tap()
        sleep(1)
        at(0.85, 0.6).press(forDuration: 0.05, thenDragTo: at(0.15, 0.6), withVelocity: 900, thenHoldForDuration: 0)
        sleep(1)
        at(0.15, 0.6).press(forDuration: 0.05, thenDragTo: at(0.85, 0.6), withVelocity: 900, thenHoldForDuration: 0)
        sleep(1)

        // A short drag that is let go slowly: the image goes back.
        at(0.5, 0.5).press(forDuration: 0.05, thenDragTo: at(0.55, 0.62), withVelocity: 250, thenHoldForDuration: 0.4)
        sleep(1)

        // A long drag, held, then let go: it closes into the thumbnail.
        at(0.5, 0.5).press(forDuration: 0.05, thenDragTo: at(0.62, 0.8), withVelocity: 600, thenHoldForDuration: 0.3)
        sleep(2)

        // Open the long screenshot, drag it upward and let go.
        images.element(boundBy: 1).tap()
        sleep(1)
        at(0.5, 0.6).press(forDuration: 0.05, thenDragTo: at(0.4, 0.3), withVelocity: 900, thenHoldForDuration: 0)
        sleep(2)
    }
}
