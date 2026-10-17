import Foundation
import QuartzCore

/// A spring, described the way SwiftUI describes one: how long it takes to respond and how
/// much it bounces (0 settles without overshooting).
public struct LoupeSpring: Sendable, Hashable {
    public var response: Double
    public var dampingRatio: Double

    public init(response: Double, dampingRatio: Double = 1) {
        self.response = response
        self.dampingRatio = dampingRatio
    }

    /// Opening and closing: quick, no overshoot.
    public static let transition = LoupeSpring(response: 0.36, dampingRatio: 1)
    /// Going back after a drag that did not close: quick, a hint of bounce.
    public static let restore = LoupeSpring(response: 0.32, dampingRatio: 0.86)

    var stiffness: Double { pow(2 * .pi / max(response, 0.01), 2) }
    var damping: Double { 4 * .pi * dampingRatio / max(response, 0.01) }
}

/// Springs a vector of values toward targets, one frame at a time. Retargeting keeps each
/// value's current velocity, so an animation can change course mid-flight without a jolt.
struct SpringVector {
    private(set) var values: [Double]
    private(set) var velocities: [Double]
    private(set) var targets: [Double]
    var spring: LoupeSpring
    let tolerances: [Double]

    init(values: [Double], tolerances: [Double], spring: LoupeSpring) {
        self.values = values
        self.velocities = Array(repeating: 0, count: values.count)
        self.targets = values
        self.tolerances = tolerances
        self.spring = spring
    }

    mutating func set(values: [Double], velocities: [Double]? = nil) {
        self.values = values
        self.velocities = velocities ?? Array(repeating: 0, count: values.count)
    }

    mutating func retarget(_ targets: [Double], spring: LoupeSpring? = nil) {
        self.targets = targets
        if let spring { self.spring = spring }
    }

    var isSettled: Bool {
        for i in values.indices {
            let tol = tolerances[i]
            if abs(values[i] - targets[i]) > tol || abs(velocities[i]) > tol * 20 { return false }
        }
        return true
    }

    /// Advances by `dt` seconds; returns whether the values have come to rest (and snaps them to the targets if so).
    mutating func step(_ dt: Double) -> Bool {
        let k = spring.stiffness, c = spring.damping
        // Semi-implicit Euler in small fixed steps: stable for stiff springs at any frame rate.
        var remaining = min(dt, 1.0 / 20)
        let h = 1.0 / 960
        while remaining > 1e-9 {
            let s = min(h, remaining)
            for i in values.indices {
                let a = -k * (values[i] - targets[i]) - c * velocities[i]
                velocities[i] += a * s
                values[i] += velocities[i] * s
            }
            remaining -= s
        }
        if isSettled {
            values = targets
            velocities = Array(repeating: 0, count: values.count)
            return true
        }
        return false
    }
}

/// Calls back once per display frame while running, with the time to advance by.
@MainActor
final class FrameTicker: NSObject {
    private let tick: (Double) -> Void
    private var lastTimestamp: CFTimeInterval?
    #if canImport(UIKit)
    private var link: CADisplayLink?
    #else
    private var link: CADisplayLink?
    private weak var view: LoupePlatformView?
    #endif

    #if canImport(UIKit)
    init(tick: @escaping (Double) -> Void) {
        self.tick = tick
    }
    #else
    init(view: LoupePlatformView, tick: @escaping (Double) -> Void) {
        self.view = view
        self.tick = tick
    }
    #endif

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        lastTimestamp = nil
        #if canImport(UIKit)
        let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        #else
        guard let view else { return }
        let link = view.displayLink(target: WeakTarget(self), selector: #selector(WeakTarget.fire(_:)))
        #endif
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = nil
    }

    fileprivate func fire(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = lastTimestamp.map { now - $0 } ?? (link.targetTimestamp - link.timestamp)
        lastTimestamp = now
        tick(max(dt, 1.0 / 240))
    }
}

/// Keeps the display link from retaining the ticker.
private final class WeakTarget: NSObject {
    weak var ticker: FrameTicker?
    init(_ ticker: FrameTicker) { self.ticker = ticker }
    @MainActor @objc func fire(_ link: CADisplayLink) { ticker?.fire(link) }
}
