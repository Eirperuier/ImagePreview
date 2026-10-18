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

        // The first image, dragged right: there is nothing before it, so it closes.
        first.tap()
        sleep(1)
        at(0.3, 0.5).press(forDuration: 0.05, thenDragTo: at(0.8, 0.55), withVelocity: 500, thenHoldForDuration: 0.3)
        sleep(2)

        // The last image, flicked left: it closes too.
        images.element(boundBy: 1).tap()
        sleep(1)
        at(0.8, 0.5).press(forDuration: 0.05, thenDragTo: at(0.45, 0.5), withVelocity: 1200, thenHoldForDuration: 0)
        sleep(2)

        // Open the long screenshot, drag it upward and let go.
        images.element(boundBy: 1).tap()
        sleep(1)
        at(0.5, 0.6).press(forDuration: 0.05, thenDragTo: at(0.4, 0.3), withVelocity: 900, thenHoldForDuration: 0)
        sleep(2)
    }

    /// Opens the clip, which plays as it flies, then drags it home, still playing.
    @MainActor
    func testVideo() throws {
        let app = XCUIApplication()
        app.launch()
        let play = app.images["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }
        play.tap()
        sleep(3)
        at(0.5, 0.5).press(forDuration: 0.05, thenDragTo: at(0.56, 0.78), withVelocity: 500, thenHoldForDuration: 0.6)
        sleep(2)
    }

    /// Closes an image with a slow transition and scrolls the page while it flies home:
    /// the image has to stay on course for its thumbnail and land on it where it now is.
    @MainActor
    func testScrollingWhileAnImageFliesHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PREVIEW_TRANSITION_RESPONSE"] = "1.6"
        app.launch()
        let image = app.images.element(boundBy: 2)
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }

        image.tap()
        sleep(3)
        app.buttons["Close"].tap()
        // The page underneath scrolls up, then back down, while the image is on its way.
        at(0.5, 0.75).press(forDuration: 0.02, thenDragTo: at(0.5, 0.55), withVelocity: 600, thenHoldForDuration: 0.1)
        at(0.5, 0.5).press(forDuration: 0.02, thenDragTo: at(0.5, 0.62), withVelocity: 600, thenHoldForDuration: 0.1)
        sleep(3)
    }

    /// Closes an image and scrolls the page slowly through the moment it lands: the image must
    /// hand over to its thumbnail without the two parting for a frame.
    @MainActor
    func testLandingWhileThePageScrolls() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PREVIEW_TRANSITION_RESPONSE"] = "0.7"
        app.launch()
        let image = app.images.element(boundBy: 2)
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }

        image.tap()
        sleep(2)
        app.buttons["Close"].tap()
        at(0.5, 0.85).press(forDuration: 0.02, thenDragTo: at(0.5, 0.45), withVelocity: 180, thenHoldForDuration: 0.2)
        sleep(2)
    }
    /// A slow flight home and a long, slow scroll that starts while the image is still flying,
    /// so the scroll is going on when the image lands and the viewer goes.
    @MainActor
    func testLandingDuringALongScroll() throws {
        let app = XCUIApplication()
        app.launchEnvironment["PREVIEW_TRANSITION_RESPONSE"] = "2.4"
        app.launch()
        let image = app.images.element(boundBy: 2)
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }

        image.tap()
        sleep(4)
        app.buttons["Close"].tap()
        at(0.5, 0.9).press(forDuration: 0.02, thenDragTo: at(0.5, 0.3), withVelocity: 120, thenHoldForDuration: 0.2)
        sleep(2)
    }
    /// Opens the first image and holds it, then swipes to the second and holds again, for screenshots of the bars.
    @MainActor
    func testBars() throws {
        let app = XCUIApplication()
        app.launch()
        let image = app.images.element(boundBy: 0)
        XCTAssertTrue(image.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch
        func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            screen.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
        }
        image.tap()
        sleep(4)
        at(0.85, 0.6).press(forDuration: 0.05, thenDragTo: at(0.15, 0.6), withVelocity: 900, thenHoldForDuration: 0)
        sleep(4)
        at(0.5, 0.6).tap()
        sleep(3)
    }
}
