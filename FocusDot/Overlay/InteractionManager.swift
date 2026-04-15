import Foundation
import AppKit
import SwiftUI
import Combine

struct DotDeformation: Equatable {
    /// Pull vector in SwiftUI coordinates — the blob stretches toward this direction
    var pull: CGSize = .zero
    /// Squish: 1.0 = normal, >1.0 = expanded (balloon press)
    var squish: CGFloat = 1.0
    /// How wide the grab is: 0 = edge (thin pull), 1 = center (wide pull)
    var grabWidth: CGFloat = 0.5
    /// Whether a jiggle animation should play
    var jigglePhase: Int = 0
    var isGrabbed: Bool = false

    static let neutral = DotDeformation()
}

final class InteractionManager: ObservableObject {
    @Published var deformation: DotDeformation = .neutral

    /// Set by DotOverlayWindow to report the dot's center in screen coordinates
    var dotScreenCenter: CGPoint = .zero
    var dotRadius: CGFloat = 10

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDragging = false
    private var currentGrabWidth: CGFloat = 0.5
    private var wasInProximity = false
    private var jiggleCounter = 0

    private let proximityRadius: CGFloat = 50
    /// Controls how quickly stretch resistance builds up
    /// Equal to maxPull so initial slope = 1:1 (small moves track mouse exactly)
    private let stretchResistance: CGFloat = 80
    /// Maximum pull distance in points (asymptotic limit)
    private let maxPullMagnitude: CGFloat = 80

    var onGrabBegan: (() -> Void)?
    var onGrabEnded: (() -> Void)?

    init() {
        startMouseTracking()
    }

    private func startMouseTracking() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleGlobalMouse()
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleLocalEvent(event)
            return event
        }
    }

    private func handleGlobalMouse() {
        guard !isDragging else { return }
        let mouse = NSEvent.mouseLocation
        checkProximity(mouseScreen: mouse)
    }

    private func handleLocalEvent(_ event: NSEvent) {
        let mouse = NSEvent.mouseLocation

        switch event.type {
        case .mouseMoved:
            if !isDragging {
                checkProximity(mouseScreen: mouse)
            }

        case .leftMouseDown:
            let dist = distance(mouse, dotScreenCenter)
            if dist <= dotRadius + 8 {
                isDragging = true
                onGrabBegan?()

                // How far from center: 0 at center, 1 at edge
                let edgeness = min(dist / dotRadius, 1.0)
                // Invert: edge click = narrow grab (0.15), center click = wide grab (0.9)
                currentGrabWidth = 0.9 - edgeness * 0.75

                // Tap: flatten like pressing a balloon
                withAnimation(.spring(response: 0.12, dampingFraction: 0.25)) {
                    deformation = DotDeformation(squish: 1.12, grabWidth: currentGrabWidth, isGrabbed: true)
                }
            }

        case .leftMouseDragged:
            if isDragging {
                updateDrag(mouseScreen: mouse)
            }

        case .leftMouseUp:
            if isDragging {
                isDragging = false
                onGrabEnded?()
                // Quick snap-back with a little bounce
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    deformation = .neutral
                }

                // Residual jitter — energy dissipating after snap-back
                jiggleCounter += 1
                let jid = jiggleCounter
                let jitterAngle = Double.random(in: 0...(2 * .pi))

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    guard let self, self.jiggleCounter == jid, !self.isDragging else { return }
                    let m: CGFloat = 1.8
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        self.deformation = DotDeformation(
                            pull: CGSize(width: CGFloat(cos(jitterAngle)) * m, height: CGFloat(sin(jitterAngle)) * m),
                            jigglePhase: jid
                        )
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, self.jiggleCounter == jid, !self.isDragging else { return }
                    let m: CGFloat = 0.8
                    withAnimation(.spring(response: 0.08, dampingFraction: 0.3)) {
                        self.deformation = DotDeformation(
                            pull: CGSize(width: CGFloat(cos(jitterAngle + .pi)) * m, height: CGFloat(sin(jitterAngle + .pi)) * m),
                            jigglePhase: jid
                        )
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
                    guard let self, self.jiggleCounter == jid, !self.isDragging else { return }
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                        self.deformation = .neutral
                    }
                }
            }

        default:
            break
        }
    }

    /// Check if cursor just entered or is in proximity, trigger jiggle on enter.
    private func checkProximity(mouseScreen: CGPoint) {
        let dist = distance(mouseScreen, dotScreenCenter)
        let inProximity = dist < proximityRadius

        if inProximity && !wasInProximity {
            // Cursor just entered proximity — trigger jiggle
            triggerJiggle()
        }

        if !inProximity && wasInProximity {
            // Left proximity — settle back
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                deformation = .neutral
            }
        }

        wasInProximity = inProximity
    }

    /// Single-spring jiggle — poke then let the spring's natural overshoot create the wobble.
    private func triggerJiggle() {
        jiggleCounter += 1
        let currentJiggle = jiggleCounter

        // Small poke — stays well within elliptical mode (no neck geometry)
        let angle = Double.random(in: 0...(2 * .pi))
        let mag: CGFloat = 2.5
        let pokeX = CGFloat(cos(angle)) * mag
        let pokeY = CGFloat(sin(angle)) * mag

        // Quick poke out
        withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
            deformation = DotDeformation(pull: CGSize(width: pokeX, height: pokeY), jigglePhase: currentJiggle)
        }

        // Let the spring settle back naturally — the low damping (0.3) creates the wobble
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.jiggleCounter == currentJiggle, !self.isDragging else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.35)) {
                self.deformation = .neutral
            }
        }
    }

    /// Drag with exponential resistance and progressive lag.
    /// Close drags: snappy response. Far drags: rubber fights back, deformation lags behind cursor.
    private func updateDrag(mouseScreen: CGPoint) {
        let dx = mouseScreen.x - dotScreenCenter.x
        let dy = -(mouseScreen.y - dotScreenCenter.y)  // flip Y for SwiftUI coords
        let rawDist = sqrt(dx * dx + dy * dy)

        guard rawDist > 1 else { return }

        // Exponential resistance — asymptotically approaches maxPullMagnitude
        let resistedMagnitude = maxPullMagnitude * (1 - exp(-rawDist / stretchResistance))

        // Direction preserved, magnitude limited
        let scale = resistedMagnitude / rawDist
        let pullX = dx * scale
        let pullY = dy * scale

        // Progressive lag: spring response time increases with stretch.
        // Near the ball: 0.06s (snappy). Far away: up to 0.5s (sluggish, rubber fighting back).
        let stretchRatio = resistedMagnitude / maxPullMagnitude  // 0→1
        let responseTime = 0.06 + stretchRatio * stretchRatio * 0.45
        let damping = 0.85 + stretchRatio * 0.1  // slightly less bouncy at high stretch

        withAnimation(.spring(response: responseTime, dampingFraction: damping)) {
            deformation = DotDeformation(
                pull: CGSize(width: pullX, height: pullY),
                grabWidth: currentGrabWidth,
                isGrabbed: true
            )
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
