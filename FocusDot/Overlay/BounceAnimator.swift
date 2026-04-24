import Foundation
import SwiftUI
import Combine

final class BounceAnimator: ObservableObject {
    /// Vertical floating offset
    @Published var offset: CGSize = .zero
    /// No idle deformation — only interaction drives pull
    @Published var pull: CGSize = .zero
    /// Show/hide scale. 1 = visible, 0 = collapsed. Animated by show/hide flow.
    @Published var visibilityScale: CGFloat = 1.0

    private var displayLink: CVDisplayLink?
    private var cancellable: AnyCancellable?
    private let preferences: PreferencesManager
    private var isPaused = false
    private var startTime: CFTimeInterval = CACurrentMediaTime()

    /// Floating amplitude in points
    private let amplitude: CGFloat = 1.2
    /// Full cycle duration in seconds
    private let period: CGFloat = 4.0

    init(preferences: PreferencesManager) {
        self.preferences = preferences
        cancellable = preferences.$isBouncingEnabled
            .sink { [weak self] enabled in
                if enabled {
                    self?.startFloating()
                } else {
                    self?.stopFloating()
                }
            }
    }

    func startFloating() {
        stopFloating()
        startTime = CACurrentMediaTime()
        startDisplayLink()
    }

    private func startDisplayLink() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self._timer = timer
    }

    private var _timer: Timer?

    func stopFloating() {
        _timer?.invalidate()
        _timer = nil
        withAnimation(.easeInOut(duration: 0.5)) {
            offset = .zero
            pull = .zero
        }
    }

    /// Pop from 0 → slight overshoot → settle to 1.
    func animateShow() {
        // Snap to 0 instantly so the spring has somewhere to grow from.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { visibilityScale = 0 }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
            visibilityScale = 1.0
        }
    }

    /// Anticipation bounce → shrink to 0. `completion` runs after the shrink finishes.
    func animateHide(completion: @escaping () -> Void) {
        let bounceDuration: TimeInterval = 0.18
        let shrinkDuration: TimeInterval = 0.22

        withAnimation(.spring(response: bounceDuration, dampingFraction: 0.5)) {
            visibilityScale = 1.20
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration) { [weak self] in
            withAnimation(.easeIn(duration: shrinkDuration)) {
                self?.visibilityScale = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + bounceDuration + shrinkDuration + 0.02,
                                      execute: completion)
    }

    func bounceNow() {
        let angle = Double.random(in: 0...(2 * .pi))
        let mag: CGFloat = 1.6
        let dx = CGFloat(cos(angle))
        let dy = CGFloat(sin(angle))

        let steps: [(scale: CGFloat, delay: TimeInterval)] = [
            ( 1.00, 0.00),
            (-0.75, 0.06),
            ( 0.50, 0.12),
            (-0.28, 0.18),
            ( 0.00, 0.26),
        ]

        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self] in
                withAnimation(.spring(response: 0.07, dampingFraction: 0.55)) {
                    self?.pull = CGSize(width: dx * mag * step.scale,
                                        height: dy * mag * step.scale)
                }
            }
        }
    }

    func pause() {
        isPaused = true
        _timer?.invalidate()
        _timer = nil
    }

    func resume() {
        isPaused = false
        if preferences.isBouncingEnabled {
            withAnimation(.easeInOut(duration: 0.4)) {
                pull = .zero
            }
            startDisplayLink()
        }
    }

    private func tick() {
        guard !isPaused else { return }
        let elapsed = CACurrentMediaTime() - startTime
        let phase = CGFloat(elapsed) / period * 2 * .pi
        let y = sin(phase) * amplitude
        // Use a direct assignment — the sine is already smooth
        offset = CGSize(width: 0, height: y)
    }

    deinit {
        _timer?.invalidate()
    }
}
