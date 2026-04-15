import AppKit
import SwiftUI

final class DotOverlayWindow: NSWindow {
    private let preferences: PreferencesManager
    private let animator: BounceAnimator

    init(preferences: PreferencesManager, animator: BounceAnimator) {
        self.preferences = preferences
        self.animator = animator

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

        positionNearCamera(on: nil)
    }

    /// Position the dot at top-center of the appropriate screen.
    /// - Parameter camera: The currently active camera. If nil, falls back to main screen.
    func positionNearCamera(on camera: ActiveCamera?) {
        let screen = screenForCamera(camera)
        let screenFrame = screen.frame

        let windowSize: CGFloat = 80
        let x = screenFrame.midX - windowSize / 2
        // Just below the top of the screen (near where the camera physically sits)
        let y = screenFrame.maxY - windowSize - 5

        setFrame(NSRect(x: x, y: y, width: windowSize, height: windowSize), display: true)
    }

    func showDot(camera: ActiveCamera? = nil) {
        positionNearCamera(on: camera)
        orderFront(nil)
    }

    func hideDot() {
        orderOut(nil)
    }

    /// Map a camera to the screen it's physically attached to.
    private func screenForCamera(_ camera: ActiveCamera?) -> NSScreen {
        guard let camera else {
            return NSScreen.main ?? NSScreen.screens[0]
        }

        if camera.isBuiltIn {
            // Built-in camera → built-in display
            if let builtIn = Self.builtInScreen() {
                return builtIn
            }
        } else {
            // External camera → first external display (if any)
            if let external = Self.firstExternalScreen() {
                return external
            }
        }

        // Fallback: main screen
        return NSScreen.main ?? NSScreen.screens[0]
    }

    /// Find the built-in display (MacBook screen, iMac screen).
    private static func builtInScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let displayID = screenNumber, CGDisplayIsBuiltin(displayID) != 0 {
                return screen
            }
        }
        return nil
    }

    /// Find the first external display.
    private static func firstExternalScreen() -> NSScreen? {
        for screen in NSScreen.screens {
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            if let displayID = screenNumber, CGDisplayIsBuiltin(displayID) == 0 {
                return screen
            }
        }
        return nil
    }
}
