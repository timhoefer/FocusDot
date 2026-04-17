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
    /// Press point in unit coordinates (0–1, relative to dot frame) for depression effect
    var pressPoint: UnitPoint? = nil
    /// Depression depth: 0 = none, 1 = full press
    var pressDepth: CGFloat = 0
    /// Depression radius as fraction of dot size (grows with hold duration)
    var pressRadius: CGFloat = 0.22
    /// Positional nudge (moves the whole ball, does not deform it)
    var nudge: CGSize = .zero

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
    private var isShowingHandCursor = false
    private var isShowingClosedHand = false
    private var jiggleCounter = 0
    private var pressTimer: Timer?
    private var pressStartTime: Date?
    private var currentPressPoint: UnitPoint?
    private var grabAngle: CGFloat = 0  // initial pull angle when drag begins
    private var hasLockedAngle = false

    /// Controls how quickly stretch resistance builds up
    /// Equal to maxPull so initial slope = 1:1 (small moves track mouse exactly)
    private let stretchResistance: CGFloat = 6
    /// Maximum pull distance in points (asymptotic limit)
    private let maxPullMagnitude: CGFloat = 14

    var onGrabBegan: (() -> Void)?
    var onGrabEnded: (() -> Void)?
    /// Called when the cursor enters/leaves the dot hit area so the window can toggle ignoresMouseEvents
    var onOverDotChanged: ((Bool) -> Void)?
    /// Called during reposition mode drag with the new screen position
    var onReposition: ((CGPoint) -> Void)?
    /// When true, dragging moves the ball instead of deforming it
    var isRepositionMode = false

    init() {
        startMouseTracking()
    }

    private func startMouseTracking() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            if event.type == .leftMouseDown || event.type == .leftMouseUp {
                // Forward clicks to local handler when window is ignoring events
                self?.handleLocalEvent(event)
            } else {
                self?.handleGlobalMouse()
            }
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

                if isRepositionMode {
                    // Reposition mode: just track, no deformation
                    if isShowingHandCursor { NSCursor.pop() }
                    NSCursor.closedHand.push()
                    isShowingHandCursor = true
                    isShowingClosedHand = true
                } else {
                    // How far from center: 0 at center, 1 at edge
                    let edgeness = min(dist / dotRadius, 1.0)
                    // Quadratic falloff — center grabs are wide, rim grabs pinch sharply
                    let centerness = 1.0 - edgeness
                    currentGrabWidth = 0.05 + centerness * centerness * 0.95

                    // Compute press point in unit coords (0–1) relative to dot frame
                    let unitX = 0.5 + (mouse.x - dotScreenCenter.x) / (dotRadius * 2)
                    let unitY = 0.5 - (mouse.y - dotScreenCenter.y) / (dotRadius * 2) // flip Y for SwiftUI
                    currentPressPoint = UnitPoint(x: min(max(unitX, 0), 1), y: min(max(unitY, 0), 1))

                    // Initial press
                    withAnimation(.spring(response: 0.12, dampingFraction: 0.25)) {
                        deformation = DotDeformation(squish: 1.04, grabWidth: currentGrabWidth, isGrabbed: true, pressPoint: currentPressPoint, pressDepth: 0.3, pressRadius: 0.22)
                    }

                    // Ramp up squish and depression while holding
                    pressStartTime = Date()
                    pressTimer?.invalidate()
                    pressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                        self?.updatePressRamp()
                    }
                }
            }

        case .leftMouseDragged:
            if isDragging {
                if isRepositionMode {
                    onReposition?(mouse)
                } else {
                    stopPressTimer()
                    if !isShowingClosedHand {
                        if isShowingHandCursor { NSCursor.pop() }
                        NSCursor.closedHand.push()
                        isShowingHandCursor = true
                        isShowingClosedHand = true
                    }
                    updateDrag(mouseScreen: mouse)
                }
            }

        case .leftMouseUp:
            if isDragging {
                isDragging = false
                stopPressTimer()
                onGrabEnded?()
                // Pop drag cursor and release window
                if isShowingHandCursor {
                    NSCursor.pop()
                    isShowingHandCursor = false
                }
                isShowingClosedHand = false
                hasLockedAngle = false
                onOverDotChanged?(false)
                // How stretched was the ball at release? 0→1
                let releasePull = deformation.pull
                let releaseMag = sqrt(releasePull.width * releasePull.width + releasePull.height * releasePull.height)
                let energy = min(releaseMag / maxPullMagnitude, 1.0)

                // Snap-back: bouncier and faster with more energy
                let snapDamping = 0.6 - energy * 0.25  // 0.6 → 0.35
                withAnimation(.spring(response: 0.2, dampingFraction: snapDamping)) {
                    deformation = .neutral
                }

                // Residual jitter — small, multi-directional wobbles so it feels like the ball is quivering, not ping-ponging along the drag axis
                jiggleCounter += 1
                let jid = jiggleCounter
                let baseAngle = Double.random(in: 0...(2 * .pi))
                // Three phases ~120° apart with a dash of angular noise — reads as "all directions"
                let phaseAngles: [Double] = [
                    baseAngle + Double.random(in: -0.4...0.4),
                    baseAngle + 2 * .pi / 3 + Double.random(in: -0.4...0.4),
                    baseAngle + 4 * .pi / 3 + Double.random(in: -0.4...0.4),
                ]
                let phaseTimes: [Double] = [0.15, 0.21, 0.27]
                let phaseMags: [CGFloat] = [
                    0.4 + energy * 0.9,
                    0.3 + energy * 0.6,
                    0.2 + energy * 0.35,
                ]

                for i in 0..<3 {
                    let angle = phaseAngles[i]
                    let mag = phaseMags[i]
                    DispatchQueue.main.asyncAfter(deadline: .now() + phaseTimes[i]) { [weak self] in
                        guard let self, self.jiggleCounter == jid, !self.isDragging else { return }
                        withAnimation(.spring(response: 0.06, dampingFraction: 0.3)) {
                            self.deformation = DotDeformation(
                                pull: CGSize(width: CGFloat(cos(angle)) * mag, height: CGFloat(sin(angle)) * mag),
                                jigglePhase: jid
                            )
                        }
                    }
                }

                // Settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) { [weak self] in
                    guard let self, self.jiggleCounter == jid, !self.isDragging else { return }
                    withAnimation(.spring(response: 0.12, dampingFraction: 0.55)) {
                        self.deformation = .neutral
                    }
                }
            }

        default:
            break
        }
    }

    /// Trigger the nudge only when the cursor makes direct contact with the ball.
    private func checkProximity(mouseScreen: CGPoint) {
        let dist = distance(mouseScreen, dotScreenCenter)
        let overDot = dist <= dotRadius + 8

        if overDot && !wasInProximity {
            // Cursor just touched the ball — nudge it away
            triggerJiggle(mouseScreen: mouseScreen)
        }

        wasInProximity = overDot

        // Show hand cursor when hovering over the dot and toggle window passthrough
        if overDot && !isShowingHandCursor {
            onOverDotChanged?(true)
            NSCursor.pointingHand.push()
            isShowingHandCursor = true
        } else if !overDot && isShowingHandCursor {
            NSCursor.pop()
            isShowingHandCursor = false
            onOverDotChanged?(false)
        }
    }

    /// Subtle positional nudge — the ball is pushed opposite to where the cursor entered its field, then snaps back.
    private func triggerJiggle(mouseScreen: CGPoint) {
        jiggleCounter += 1
        let currentJiggle = jiggleCounter

        // Vector from ball center to cursor, flipped into SwiftUI coords (y grows downward)
        let dx = mouseScreen.x - dotScreenCenter.x
        let dy = -(mouseScreen.y - dotScreenCenter.y)
        let mag = sqrt(dx * dx + dy * dy)
        guard mag > 0.01 else { return }

        // Push opposite to the cursor — small so it reads as a soft recoil
        let nudgeMag: CGFloat = 2.5
        let nudgeX = -dx / mag * nudgeMag
        let nudgeY = -dy / mag * nudgeMag

        // Drift out gently — longer response = slower, floatier motion
        withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
            deformation = DotDeformation(
                jigglePhase: currentJiggle,
                nudge: CGSize(width: nudgeX, height: nudgeY)
            )
        }

        // Float back slowly — like a balloon drifting back down onto a fingertip
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.jiggleCounter == currentJiggle, !self.isDragging else { return }
            withAnimation(.spring(response: 1.6, dampingFraction: 0.9)) {
                self.deformation = .neutral
            }
        }
    }

    /// Ramp up squish and depression while holding click.
    private func updatePressRamp() {
        guard let startTime = pressStartTime, isDragging, !isShowingClosedHand else {
            stopPressTimer()
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        // Ease-out curve: ramps quickly at first, asymptotically approaches max over ~1.5s
        let t = min(1.0, 1.0 - exp(-elapsed * 2.5))

        let minSquish: CGFloat = 1.04
        let maxSquish: CGFloat = 1.18
        let minDepth: CGFloat = 0.3
        let maxDepth: CGFloat = 1.0
        let minPressRadius: CGFloat = 0.22
        let maxPressRadius: CGFloat = 0.35

        let squish = minSquish + (maxSquish - minSquish) * t
        let depth = minDepth + (maxDepth - minDepth) * t
        let pressRadius = minPressRadius + (maxPressRadius - minPressRadius) * t

        withAnimation(.interactiveSpring(response: 0.08, dampingFraction: 0.7)) {
            deformation = DotDeformation(
                squish: squish,
                grabWidth: currentGrabWidth,
                isGrabbed: true,
                pressPoint: currentPressPoint,
                pressDepth: depth,
                pressRadius: pressRadius
            )
        }
    }

    private func stopPressTimer() {
        pressTimer?.invalidate()
        pressTimer = nil
        pressStartTime = nil
    }

    /// Drag with exponential resistance and progressive lag.
    /// Close drags: snappy response. Far drags: rubber fights back, deformation lags behind cursor.
    /// Grip slips and snaps back if cursor moves too far around the ball in a circular arc.
    private func updateDrag(mouseScreen: CGPoint) {
        let dx = mouseScreen.x - dotScreenCenter.x
        let dy = -(mouseScreen.y - dotScreenCenter.y)  // flip Y for SwiftUI coords
        let rawDist = sqrt(dx * dx + dy * dy)

        guard rawDist > 1 else { return }

        let currentAngle = atan2(dy, dx)

        // Lock the pull direction once the drag starts moving
        if !hasLockedAngle && rawDist > dotRadius * 0.3 {
            grabAngle = currentAngle
            hasLockedAngle = true
        }

        // Allow the pull direction to drift toward the cursor, but with increasing resistance.
        // Small angular changes follow easily; large ones are dampened and eventually slip.
        var angleDelta = currentAngle - grabAngle
        if angleDelta > .pi { angleDelta -= 2 * .pi }
        if angleDelta < -.pi { angleDelta += 2 * .pi }
        let absAngleDelta = abs(angleDelta)

        // Grip slips entirely beyond ~120°
        let slipFull: CGFloat = 2 * .pi / 3

        if absAngleDelta > slipFull {
            hasLockedAngle = false
            isDragging = false
            isShowingClosedHand = false
            stopPressTimer()
            onGrabEnded?()
            if isShowingHandCursor {
                NSCursor.pop()
                isShowingHandCursor = false
            }
            onOverDotChanged?(false)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                deformation = .neutral
            }
            return
        }

        // Blend toward the cursor angle — small deviations follow freely,
        // large ones are increasingly resisted (cubic falloff).
        // followFraction: 1.0 = fully follows cursor, 0.0 = fully locked
        let normalizedAngle = absAngleDelta / slipFull  // 0→1
        let followFraction = max(0, 1.0 - normalizedAngle * normalizedAngle * normalizedAngle)
        let effectiveAngle = grabAngle + angleDelta * followFraction

        // Tiny drift so the grab angle doesn't feel completely rigid,
        // but slow enough that a circular arc still accumulates and slips
        let driftRate: CGFloat = 0.003
        grabAngle = grabAngle + angleDelta * driftRate

        // Pull magnitude attenuates as angle deviates — harder to stretch sideways
        let gripFactor = followFraction

        let radialDist = rawDist * gripFactor

        guard radialDist > 0 else {
            // Cursor moved behind the ball center relative to grab direction
            withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                deformation = DotDeformation(isGrabbed: true)
            }
            return
        }

        // Exponential resistance — asymptotically approaches maxPullMagnitude
        let resistedMagnitude = maxPullMagnitude * (1 - exp(-radialDist / stretchResistance))

        // Pull along the effective (blended) direction
        let pullX = cos(effectiveAngle) * resistedMagnitude
        let pullY = sin(effectiveAngle) * resistedMagnitude

        // Progressive lag: spring response time increases with stretch.
        let stretchRatio = resistedMagnitude / maxPullMagnitude  // 0→1
        let responseTime = 0.04 + pow(stretchRatio, 4) * 2.0
        let damping = 0.7 + stretchRatio * 0.29

        // Fade depression as pull increases
        let depthFade = max(0, 1.0 - resistedMagnitude / 15.0)

        withAnimation(.spring(response: responseTime, dampingFraction: damping)) {
            deformation = DotDeformation(
                pull: CGSize(width: pullX, height: pullY),
                grabWidth: currentGrabWidth,
                isGrabbed: true,
                pressPoint: depthFade > 0.01 ? deformation.pressPoint : nil,
                pressDepth: depthFade
            )
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    deinit {
        if isShowingHandCursor { NSCursor.pop() }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
