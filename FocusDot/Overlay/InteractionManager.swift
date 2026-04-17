import Foundation
import AppKit
import SwiftUI
import Combine

struct DotDeformation: Equatable {
    /// How wide the grab is: 0 = edge (thin pull), 1 = center (wide pull)
    var grabWidth: CGFloat = 0.5
    /// Whole-dot scale tweak (e.g. press flattening). Pull/wobble live in animator.pull.
    var squish: CGFloat = 1.0
    var isGrabbed: Bool = false

    static let neutral = DotDeformation()
}

final class InteractionManager: ObservableObject {
    @Published var deformation: DotDeformation = .neutral

    /// Set by DotOverlayWindow to report the dot's center in screen coordinates
    var dotScreenCenter: CGPoint = .zero
    var dotRadius: CGFloat = 10

    private let animator: BounceAnimator
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDragging = false
    private var currentGrabWidth: CGFloat = 0.5
    private var wasInProximity = false

    private let proximityRadius: CGFloat = 50
    /// Gain mapping cursor distance → external pulling force on the physics ball.
    private let pullForceGain: CGFloat = 6.0
    /// Compression impulse on press, in units of physics-velocity.
    private let pressImpulse: CGFloat = 70
    /// Stretch impulse on hover entry.
    private let hoverImpulse: CGFloat = 35

    var onGrabBegan: (() -> Void)?
    var onGrabEnded: (() -> Void)?

    init(animator: BounceAnimator) {
        self.animator = animator
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
            if !isDragging { checkProximity(mouseScreen: mouse) }

        case .leftMouseDown:
            let dist = distance(mouse, dotScreenCenter)
            if dist <= dotRadius + 8 {
                isDragging = true
                onGrabBegan?()

                // edge click = narrow grab (0.15), center click = wide grab (0.9)
                let edgeness = min(dist / dotRadius, 1.0)
                currentGrabWidth = 0.9 - edgeness * 0.75
                withAnimation(.spring(response: 0.12, dampingFraction: 0.25)) {
                    deformation = DotDeformation(grabWidth: currentGrabWidth, squish: 1.12, isGrabbed: true)
                }

                // Press = compression impulse. Physics rebounds into a visible wobble.
                animator.applyCompressionImpulse(pressImpulse)
            }

        case .leftMouseDragged:
            if isDragging { updateDrag(mouseScreen: mouse) }

        case .leftMouseUp:
            if isDragging {
                isDragging = false
                onGrabEnded?()
                animator.clearExternalForce()
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    deformation = .neutral
                }
                // No hand-coded snap-back — the underdamped physics handles recoil.
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
            triggerJiggle(towards: mouseScreen)
        }
        wasInProximity = inProximity
    }

    /// Hover poke — small stretch impulse along the cursor direction.
    private func triggerJiggle(towards mouseScreen: CGPoint) {
        let dx = mouseScreen.x - dotScreenCenter.x
        let dy = -(mouseScreen.y - dotScreenCenter.y)   // flip Y for SwiftUI coords
        let len = sqrt(dx * dx + dy * dy)
        guard len > 0.5 else { return }
        animator.setPullAxis(.init(dx: dx / len, dy: dy / len))
        animator.applyStretchImpulse(hoverImpulse)
    }

    /// Drag: cursor pulls outward on the physics ball.
    /// Direction → pull axis. Distance → external force (negative = stretch).
    private func updateDrag(mouseScreen: CGPoint) {
        let dx = mouseScreen.x - dotScreenCenter.x
        let dy = -(mouseScreen.y - dotScreenCenter.y)   // flip Y for SwiftUI coords
        let rawDist = sqrt(dx * dx + dy * dy)
        guard rawDist > 0.5 else {
            animator.clearExternalForce()
            return
        }
        animator.setPullAxis(.init(dx: dx / rawDist, dy: dy / rawDist))
        animator.setExternalForce(-pullForceGain * rawDist)
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
