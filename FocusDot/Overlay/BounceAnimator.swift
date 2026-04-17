import Foundation
import SwiftUI
import Combine

final class BounceAnimator: ObservableObject {
    /// Vertical floating offset
    @Published var offset: CGSize = .zero
    /// No idle deformation — only interaction drives pull
    @Published var pull: CGSize = .zero

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

    func bounceNow() {
        // No-op — floating is continuous
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
