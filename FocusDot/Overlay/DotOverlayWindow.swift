import AppKit
import SwiftUI

/// A content view that passes through clicks outside the dot circle.
final class PassthroughView: NSView {
    var dotRadius: CGFloat = 10
    var bounceOffset: CGSize = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let centerX = bounds.midX + bounceOffset.width
        let centerY = bounds.midY + bounceOffset.height
        let dx = point.x - centerX
        let dy = point.y - centerY
        let dist = sqrt(dx * dx + dy * dy)
        guard dist <= dotRadius + 10 else { return nil }
        // Forward to subviews (the hosting view)
        return super.hitTest(point)
    }
}

/// Overlay window that passes through all mouse events EXCEPT on the dot itself.
final class DotOverlayWindow: NSWindow {
    let preferences: PreferencesManager
    private let animator: BounceAnimator
    private let interactionManager: InteractionManager
    private var hostingView: NSHostingView<DotView>!
    private var passthroughView: PassthroughView!

    init(preferences: PreferencesManager, animator: BounceAnimator, interactionManager: InteractionManager) {
        self.preferences = preferences
        self.animator = animator
        self.interactionManager = interactionManager

        let frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true

        let dotView = DotView(preferences: preferences, animator: animator, interaction: interactionManager)
        hostingView = NSHostingView(rootView: dotView)
        hostingView.frame = frame

        passthroughView = PassthroughView(frame: frame)
        passthroughView.dotRadius = preferences.dotSize / 2
        passthroughView.addSubview(hostingView)
        self.contentView = passthroughView

        positionNearCamera(on: nil)
    }


    func positionNearCamera(on camera: ActiveCamera?) {
        let screen = screenForCamera(camera)
        let screenFrame = screen.frame

        let windowSize: CGFloat = 200
        let x = screenFrame.midX - windowSize / 2
        let y = screenFrame.maxY - windowSize

        setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: true)
        updateInteractionCenter()
    }

    func showDot(camera: ActiveCamera? = nil) {
        positionNearCamera(on: camera)
        orderFront(nil)
    }

    func hideDot() {
        orderOut(nil)
    }

    func updateInteractionCenter() {
        let windowFrame = frame
        let center = CGPoint(
            x: windowFrame.midX + animator.offset.width,
            y: windowFrame.midY - animator.offset.height
        )
        interactionManager.dotScreenCenter = center
        interactionManager.dotRadius = preferences.dotSize / 2

        passthroughView?.dotRadius = preferences.dotSize / 2
        passthroughView?.bounceOffset = animator.offset
    }

    // MARK: - Screen mapping

    private func screenForCamera(_ camera: ActiveCamera?) -> NSScreen {
        guard let camera else {
            return NSScreen.main ?? NSScreen.screens[0]
        }
        if camera.isBuiltIn {
            if let builtIn = Self.builtInScreen() { return builtIn }
        } else {
            if let external = Self.firstExternalScreen() { return external }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private static func builtInScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let id, CGDisplayIsBuiltin(id) != 0 { return screen }
        }
        return nil
    }

    private static func firstExternalScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let id, CGDisplayIsBuiltin(id) == 0 { return screen }
        }
        return nil
    }
}
