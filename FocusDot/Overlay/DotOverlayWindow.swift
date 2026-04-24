import AppKit
import SwiftUI

/// A content view that passes through clicks outside the dot circle.
final class PassthroughView: NSView {
    var dotRadius: CGFloat = 10
    var bounceOffset: CGSize = .zero
    /// During reposition mode the placeholder + confirm button extend beyond the
    /// dot radius, so accept clicks anywhere in our bounds.
    var isRepositionMode = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isRepositionMode {
            return super.hitTest(point)
        }
        let centerX = bounds.midX + bounceOffset.width
        let centerY = bounds.midY + bounceOffset.height
        let dx = point.x - centerX
        let dy = point.y - centerY
        let dist = sqrt(dx * dx + dy * dy)
        guard dist <= dotRadius + 10 else { return nil }
        return super.hitTest(point)
    }
}

/// Overlay window that passes through all mouse events EXCEPT on the dot itself.
final class DotOverlayWindow: NSWindow {
    let preferences: PreferencesManager
    private let animator: BounceAnimator
    private let interactionManager: InteractionManager
    private let wallpaperSampler: WallpaperSampler
    private var hostingView: NSHostingView<DotView>!
    private var passthroughView: PassthroughView!

    init(preferences: PreferencesManager,
         animator: BounceAnimator,
         interactionManager: InteractionManager,
         wallpaperSampler: WallpaperSampler) {
        self.preferences = preferences
        self.animator = animator
        self.interactionManager = interactionManager
        self.wallpaperSampler = wallpaperSampler

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
        self.ignoresMouseEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.isMovable = false

        let dotView = DotView(preferences: preferences,
                              animator: animator,
                              interaction: interactionManager,
                              wallpaperSampler: wallpaperSampler)
        hostingView = NSHostingView(rootView: dotView)
        hostingView.frame = frame

        passthroughView = PassthroughView(frame: frame)
        passthroughView.dotRadius = preferences.dotSize / 2
        passthroughView.addSubview(hostingView)
        self.contentView = passthroughView

        positionNearCamera(on: nil)

        interactionManager.onOverDotChanged = { [weak self] overDot in
            guard let self else { return }
            // Reposition mode keeps the window click-receptive across the whole
            // 200pt area (placeholder + ✓ button), so don't let the hover toggle
            // re-enable passthrough.
            if self.preferences.isRepositionMode { return }
            self.ignoresMouseEvents = !overDot
        }
    }

    /// During reposition: stop being click-through, expand hit area to whole window.
    func setRepositionMode(_ on: Bool) {
        passthroughView.isRepositionMode = on
        if on {
            ignoresMouseEvents = false
        }
        // Off-state ignoresMouseEvents is reset by the normal hover toggle.
    }

    /// Window numbers are -1 until ordered front, so call this after showDot.
    private func registerWindowExclusion() {
        if windowNumber > 0 {
            wallpaperSampler.excludeWindow(CGWindowID(windowNumber))
        }
    }


    // Prevent macOS from constraining the window to the visible screen area
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func positionNearCamera(on camera: ActiveCamera?) {
        // Use pending position during reposition, or saved custom position
        let custom = preferences.pendingPosition ?? preferences.customPosition
        if let custom {
            let windowSize: CGFloat = 200
            let x = custom.x - windowSize / 2
            let y = custom.y - windowSize / 2
            setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: true)
            updateInteractionCenter()
            return
        }

        let screen = screenForCamera(camera)
        let screenFrame = screen.frame

        let windowSize: CGFloat = 200
        let x = screenFrame.midX - windowSize / 2
        let y = screen.visibleFrame.maxY - windowSize / 2 - 30

        setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: true)
        updateInteractionCenter()
        refreshAmbient()
    }

    func showDot(camera: ActiveCamera? = nil) {
        positionNearCamera(on: camera)
        orderFront(nil)
        registerWindowExclusion()
        animator.animateShow()
    }

    /// Move the dot center to a screen coordinate (stores as pending until confirmed)
    func moveDotTo(screenPoint: CGPoint) {
        let windowSize: CGFloat = 200
        let x = screenPoint.x - windowSize / 2
        let y = screenPoint.y - windowSize / 2
        setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: true)
        updateInteractionCenter()
        refreshAmbient()
        preferences.pendingPosition = screenPoint
    }

    func hideDot() {
        animator.animateHide { [weak self] in
            self?.orderOut(nil)
        }
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

    /// Sample the wallpaper under the current dot position.
    func refreshAmbient() {
        let c = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = self.screen ?? NSScreen.main else { return }
        wallpaperSampler.sample(near: c, on: screen)
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
        NSScreen.screens.first { screen in
            guard let id = screen.displayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    private static func firstExternalScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.displayID else { return false }
            return CGDisplayIsBuiltin(id) == 0
        }
    }
}
