import Foundation
import SwiftUI
import Combine
import QuartzCore

final class BounceAnimator: ObservableObject {
    /// Small positional drift (subtle, not the main effect)
    @Published var offset: CGSize = .zero
    /// Stretch vector, derived from the physics simulation each tick.
    @Published var pull: CGSize = .zero

    /// Snapshot of physics state needed for per-pixel shading.
    /// Updated each tick; kept on `BounceAnimator` so SwiftUI views observe a single source.
    @Published var shadingState: BallShadingState = .neutral

    /// The lumped air-balloon physics. Idle anims, drag, and proximity all push into this.
    let physics = AirBallPhysics()

    @Published private(set) var pullAxis: CGVector = .init(dx: 1, dy: 0)
    private var idleTimer: Timer?
    private var physicsTimer: Timer?
    private var lastTickTime: CFTimeInterval = 0
    private var cancellables = Set<AnyCancellable>()
    private let preferences: PreferencesManager
    private var isPaused = false
    private var animationID = 0

    init(preferences: PreferencesManager) {
        self.preferences = preferences
        physics.p.R0 = max(4, preferences.dotSize / 2)
        startPhysicsLoop()

        preferences.$isBouncingEnabled
            .sink { [weak self] enabled in
                if enabled { self?.startBouncing() } else { self?.stopBouncing() }
            }
            .store(in: &cancellables)

        preferences.$dotSize
            .sink { [weak self] size in
                self?.physics.p.R0 = max(4, size / 2)
            }
            .store(in: &cancellables)
    }

    // MARK: - Physics-driven public API (used by InteractionManager)

    func setPullAxis(_ axis: CGVector) {
        let len = sqrt(axis.dx * axis.dx + axis.dy * axis.dy)
        guard len > 1e-4 else { return }
        pullAxis = .init(dx: axis.dx / len, dy: axis.dy / len)
    }

    func setExternalForce(_ f: CGFloat) { physics.externalForce = f }
    func clearExternalForce() { physics.externalForce = 0 }
    func applyStretchImpulse(_ magnitude: CGFloat) { physics.applyImpulse(-abs(magnitude)) }
    func applyCompressionImpulse(_ magnitude: CGFloat) { physics.applyImpulse(abs(magnitude)) }

    // MARK: - Idle animation lifecycle

    func startBouncing() {
        stopBouncing()
        scheduleNext()
    }

    func stopBouncing() {
        idleTimer?.invalidate()
        idleTimer = nil
        physics.reset()
        offset = .zero
    }

    func bounceNow() { performAnimation() }

    func pause() {
        isPaused = true
        idleTimer?.invalidate()
        idleTimer = nil
    }

    func resume() {
        isPaused = false
        if preferences.isBouncingEnabled { scheduleNext() }
    }

    private func scheduleNext() {
        guard !isPaused else { return }
        let interval = Double.random(in: 2.5...5.0)
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.performAnimation()
            self.scheduleNext()
        }
    }

    private func performAnimation() {
        animationID += 1
        let id = animationID
        switch Int.random(in: 0...3) {
        case 0: animateStretch()
        case 1: animatePulse()
        case 2: animateWobble()
        default: animateDrift(id: id)
        }
    }

    // MARK: - Idle anims as physics impulses

    private func randomAxis() -> CGVector {
        let a = Double.random(in: 0...(2 * .pi))
        return .init(dx: cos(a), dy: sin(a))
    }

    /// Slow yawn — stretches out, shell snaps it back.
    private func animateStretch() {
        setPullAxis(randomAxis())
        applyStretchImpulse(CGFloat.random(in: 50...90))
    }

    /// Quick swell.
    private func animatePulse() {
        setPullAxis(randomAxis())
        applyStretchImpulse(CGFloat.random(in: 30...55))
    }

    /// Sharp impulse — underdamped shell rings briefly.
    private func animateWobble() {
        setPullAxis(randomAxis())
        applyStretchImpulse(CGFloat.random(in: 70...130))
    }

    /// Tiny positional drift with a gentle stretch in the same direction.
    private func animateDrift(id: Int) {
        let angle = Double.random(in: 0...(2 * .pi))
        let driftDist = Double.random(in: 1.0...2.0)
        let dx = CGFloat(cos(angle) * driftDist)
        let dy = CGFloat(sin(angle) * driftDist)

        withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
            offset = CGSize(width: dx, height: dy)
        }
        setPullAxis(.init(dx: cos(angle), dy: sin(angle)))
        applyStretchImpulse(CGFloat.random(in: 25...45))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.animationID == id, !self.isPaused else { return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.55)) {
                self.offset = .zero
            }
        }
    }

    // MARK: - Physics loop

    private func startPhysicsLoop() {
        physicsTimer?.invalidate()
        lastTickTime = 0
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        physicsTimer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = lastTickTime == 0 ? 1.0 / 60.0 : now - lastTickTime
        lastTickTime = now
        physics.step(dt: dt)

        // Only stretch (x < 0) shows in the pull channel SceneBallView already consumes.
        // Compression (x > 0) still affects dynamics, so the rebound naturally swings
        // through into visible stretch on the other side.
        let stretch = max(0, -physics.x)
        pull = CGSize(width: pullAxis.dx * stretch, height: pullAxis.dy * stretch)

        shadingState = BallShadingState(
            pullAxis: pullAxis,
            x: physics.x,
            R0: physics.p.R0
        )
    }

    deinit {
        idleTimer?.invalidate()
        physicsTimer?.invalidate()
    }
}
