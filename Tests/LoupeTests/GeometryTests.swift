import CoreGraphics
import Testing
@testable import Loupe

@Test func fillCropsAndFitLetterboxes() {
    let frame = CGRect(x: 10, y: 20, width: 100, height: 100)
    let wide = CGSize(width: 400, height: 200)
    #expect(frame.placing(wide, .fill) == CGRect(x: -40, y: 20, width: 200, height: 100))
    #expect(frame.placing(wide, .fit) == CGRect(x: 10, y: 45, width: 100, height: 50))
}

@Test func theGrabbedPointStaysUnderTheFinger() {
    let start = HeroState.presented(CGRect(x: 0, y: 100, width: 400, height: 600))
    let anchor = CGPoint(x: 120, y: 300)
    let drag = DismissDrag(start: start, anchor: anchor, container: CGSize(width: 400, height: 800))
    let t = CGPoint(x: 30, y: 200)
    let state = drag.state(translation: t)
    // The grabbed point is at the same fraction of the image before and after.
    let fx = (anchor.x - start.image.minX) / start.image.width
    let fy = (anchor.y - start.image.minY) / start.image.height
    #expect(abs(state.image.minX + fx * state.image.width - (anchor.x + t.x)) < 0.001)
    #expect(abs(state.image.minY + fy * state.image.height - (anchor.y + t.y)) < 0.001)
    #expect(state.image.width < start.image.width)
    #expect(state.backdrop < 1)
}

@Test func aFlickClosesAndAPullBackStays() {
    let drag = DismissDrag(start: .presented(.zero), anchor: .zero, container: CGSize(width: 400, height: 800))
    func closes(_ ty: CGFloat, _ vy: CGFloat) -> Bool {
        drag.closes(translation: CGPoint(x: 0, y: ty), velocity: CGPoint(x: 0, y: vy))
    }
    #expect(closes(30, 1200))
    #expect(closes(-30, -1200))
    #expect(closes(-200, 0))
    #expect(!closes(100, 0))
    #expect(!closes(200, -900))
}

@Test func sidewaysClosesOnlyPastTheEnds() {
    #expect(DismissDrag.axis(for: CGPoint(x: 500, y: 20), index: 0, count: 3) == .right)
    #expect(DismissDrag.axis(for: CGPoint(x: -500, y: 20), index: 0, count: 3) == nil)
    #expect(DismissDrag.axis(for: CGPoint(x: -500, y: 20), index: 2, count: 3) == .left)
    #expect(DismissDrag.axis(for: CGPoint(x: 500, y: 20), index: 1, count: 3) == nil)
    #expect(DismissDrag.axis(for: CGPoint(x: 20, y: -500), index: 1, count: 3) == .vertical)

    let right = DismissDrag(start: .presented(.zero), anchor: .zero, axis: .right, container: CGSize(width: 400, height: 800))
    #expect(right.closes(translation: CGPoint(x: 20, y: 0), velocity: CGPoint(x: 900, y: 0)))
    #expect(right.closes(translation: CGPoint(x: 120, y: 0), velocity: .zero))
    #expect(!right.closes(translation: CGPoint(x: 60, y: 0), velocity: .zero))
    // Pulled back past where it started: that is not closing.
    #expect(!right.closes(translation: CGPoint(x: -150, y: 0), velocity: .zero))
    #expect(!right.closes(translation: CGPoint(x: 150, y: 0), velocity: CGPoint(x: -900, y: 0)))
}

@Test func aSpringArrivesAndKeepsItsVelocityWhenRetargeted() {
    var spring = SpringVector(values: [0], tolerances: [0.01], spring: .transition)
    spring.retarget([100])
    for _ in 0..<6 { _ = spring.step(1.0 / 60) }
    let midway = spring.velocities[0]
    #expect(midway > 0)
    spring.retarget([50])
    #expect(spring.velocities[0] == midway)
    var settled = false
    for _ in 0..<120 where !settled { settled = spring.step(1.0 / 60) }
    #expect(settled)
    #expect(spring.values == [50])
}

@Test func anImageFlyingHomeIsCarriedByItsThumbnailAsItLands() {
    let thumbnail = CGRect(x: 20, y: 300, width: 100, height: 100)
    let target = HeroState.source(frame: thumbnail, imageSize: CGSize(width: 100, height: 100), mode: .fill, cornerRadius: 12)
    var springs = SpringVector(values: HeroState.presented(CGRect(x: 0, y: 200, width: 400, height: 400)).vector,
                               tolerances: HeroState.tolerances, spring: .transition)
    springs.retarget(target.vector)
    var landing = Landing(frame: thumbnail, springs: springs)

    // Still far: the page scrolls 50 up; the landing spot moves, the image barely does.
    let before = springs.values[1]
    #expect(landing.follow(thumbnail.offsetBy(dx: 0, dy: -50), springs: &springs))
    #expect(springs.targets[1] == Double(target.image.minY) - 50)
    #expect(abs(springs.values[1] - before) < 1)

    // Nearly there: the next 50 carry the image along with the thumbnail.
    for _ in 0..<40 { _ = springs.step(1.0 / 120) }
    let gap = springs.values[1] - springs.targets[1]
    #expect(landing.follow(thumbnail.offsetBy(dx: 0, dy: -100), springs: &springs))
    #expect(abs((springs.values[1] - springs.targets[1]) - gap) < 1)

    // It lands exactly on the thumbnail where it now is.
    while !springs.step(1.0 / 120) {}
    #expect(HeroState(springs.values).image.minY == target.image.minY - 100)
}
