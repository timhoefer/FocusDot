import AppKit
import SwiftUI

final class DotOverlayWindow: NSWindow {
    private let preferences: PreferencesManager
    private let animator: BounceAnimator

    init(preferences: PreferencesManager, animator: BounceAnimator) {
        self.preferences = preferences
        self.animator = animator

        // Start with a generous frame; we'll position it properly
        let frame = NSRect(x: 0, y: 0, width: 80, height: 80)
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

        let dotView = DotView(preferences: preferences, animator: animator)
        let hostingView = NSHostingView(rootView: dotView)
        hostingView.frame = frame
        self.contentView = hostingView

        positionNearCamera()
    }

    func positionNearCamera() {
        // Default: top-center of the main screen (where built-in camera typically is)
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame

        let windowSize: CGFloat = 80
        let x = screenFrame.midX - windowSize / 2
        // Position just below the top of the screen (menu bar area), offset down a bit
        let y = screenFrame.maxY - windowSize - 5

        setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: true)
    }

    func showDot() {
        positionNearCamera()
        orderFront(nil)
    }

    func hideDot() {
        orderOut(nil)
    }
}
