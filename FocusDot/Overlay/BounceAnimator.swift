import Foundation
import SwiftUI
import Combine

final class BounceAnimator: ObservableObject {
    /// Small positional drift (subtle, not the main effect)
    @Published var offset: CGSize = .zero
    /// Organic blob deformation — stretches, pulses, wobbles
    @Published var pull: CGSize = .zero

    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private let preferences: PreferencesManager
    private var isPaused = false
    private var animationID = 0

    init(preferences: PreferencesManager) {
        self.preferences = preferences
        cancellable = preferences.$isBouncingEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.startBouncing()
                } else {
                    self?.stopBouncing()
                }
            }
    }

    func startBouncing() {
        stopBouncing()
        scheduleNext()
    }

    func stopBouncing() {
        timer?.invalidate()
        timer = nil
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            offset = .zero
            pull = .zero
        }
    }

    func bounceNow() {
        performAnimation()
    }

    func pause() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        isPaused = false
        if preferences.isBouncingEnabled {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                pull = .zero
                offset = .zero
            }
            scheduleNext()
        }
    }

    private func scheduleNext() {
        guard !isPaused else { return }
        let interval = Double.random(in: 2.5...5.0)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self, !self.isPaused else { return }
            self.performAnimation()
            self.scheduleNext()
        }
    }

    private func performAnimation() {
        animationID += 1
        let currentID = animationID

        // Pick a random animation type
        let roll = Int.random(in: 0...3)
        switch roll {
        case 0: animateStretch(id: currentID)
        case 1: animatePulse(id: currentID)
        case 2: animateWobble(id: currentID)
        default: animateDrift(id: currentID)
        }
    }

    /// Gentle stretch in a random direction — like the dot is yawning
    private func animateStretch(id: Int) {
        let angle = Double.random(in: 0...(2 * .pi))
        let magnitude = Double.random(in: 1.5...3.0)
        let px = CGFloat(cos(angle) * magnitude)
        let py = CGFloat(sin(angle) * magnitude)

        // Slowly stretch out
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
            pull = CGSize(width: px, height: py)
        }
        // Hold briefly, then release
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.animationID == id, !self.isPaused else { return }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5)) {
                self.pull = .zero
            }
        }
    }

    /// Uniform pulse — dot briefly swells and contracts, like a heartbeat
    private func animatePulse(id: Int) {
        // A small outward pull in all directions approximated by two quick opposing stretches
        let mag: CGFloat = 1.5

        // Slight asymmetric swell
        let angle = Double.random(in: 0...(2 * .pi))
        let px = CGFloat(cos(angle)) * mag
        let py = CGFloat(sin(angle)) * mag

        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            pull = CGSize(width: px, height: py)
        }
        // Quick snap back
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.animationID == id, !self.isPaused else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
                self.pull = .zero
            }
        }
    }

    /// Quick wobble — two rapid direction changes, like a shiver
    private func animateWobble(id: Int) {
        let angle = Double.random(in: 0...(2 * .pi))
        let mag: CGFloat = 2.0

        let p1x = CGFloat(cos(angle)) * mag
        let p1y = CGFloat(sin(angle)) * mag

        // First wobble
        withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) {
            pull = CGSize(width: p1x, height: p1y)
        }
        // Counter-wobble
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.animationID == id, !self.isPaused else { return }
            withAnimation(.spring(response: 0.15, dampingFraction: 0.35)) {
                self.pull = CGSize(width: -p1x * 0.6, height: -p1y * 0.6)
            }
        }
        // Settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self, self.animationID == id, !self.isPaused else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                self.pull = .zero
            }
        }
    }

    /// Tiny positional drift with a gentle stretch — like floating
    private func animateDrift(id: Int) {
        let angle = Double.random(in: 0...(2 * .pi))
        let driftDist = Double.random(in: 1.0...2.0)
        let dx = CGFloat(cos(angle) * driftDist)
        let dy = CGFloat(sin(angle) * driftDist)
        // Slight stretch in drift direction
        let stretchMag = Double.random(in: 0.8...1.5)
        let sx = CGFloat(cos(angle) * stretchMag)
        let sy = CGFloat(sin(angle) * stretchMag)

        withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
            offset = CGSize(width: dx, height: dy)
            pull = CGSize(width: sx, height: sy)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.animationID == id, !self.isPaused else { return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.55)) {
                self.offset = .zero
                self.pull = .zero
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
