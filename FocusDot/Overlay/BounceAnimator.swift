import Foundation
import SwiftUI
import Combine

final class BounceAnimator: ObservableObject {
    @Published var offset: CGSize = .zero

    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private let preferences: PreferencesManager

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
        scheduleNextBounce()
    }

    func stopBouncing() {
        timer?.invalidate()
        timer = nil
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            offset = .zero
        }
    }

    func bounceNow() {
        performBounce()
    }

    private func scheduleNextBounce() {
        let interval = Double.random(in: 2.0...5.0)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.performBounce()
            self?.scheduleNextBounce()
        }
    }

    private func performBounce() {
        let angle = Double.random(in: 0...(2 * .pi))
        let distance = Double.random(in: 15...30)
        let dx = CGFloat(cos(angle) * distance)
        let dy = CGFloat(sin(angle) * distance)

        // Phase 1: Bounce out
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            offset = CGSize(width: dx, height: dy)
        }

        // Phase 2: Overshoot + Phase 3: Settle back to center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                self?.offset = .zero
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
