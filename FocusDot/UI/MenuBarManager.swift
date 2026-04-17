import AppKit
import Combine

final class MenuBarManager {
    private var statusItem: NSStatusItem!
    private let preferences: PreferencesManager
    private let animator: BounceAnimator
    private let cameraManager: CameraManager
    private let appDetector: AppDetector
    private var onToggleDot: ((Bool) -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: PreferencesManager,
        animator: BounceAnimator,
        cameraManager: CameraManager,
        appDetector: AppDetector,
        onToggleDot: @escaping (Bool) -> Void
    ) {
        self.preferences = preferences
        self.animator = animator
        self.cameraManager = cameraManager
        self.appDetector = appDetector
        self.onToggleDot = onToggleDot

        setupStatusItem()

        // Rebuild menu when state changes
        Publishers.MergeMany(
            preferences.$isDotVisible.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isAutoModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isBouncingEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$dotSize.map { _ in () }.eraseToAnyPublisher(),
            preferences.$dotOpacity.map { _ in () }.eraseToAnyPublisher(),
            preferences.$dotColor.map { _ in () }.eraseToAnyPublisher(),
            preferences.$backdrop.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isRepositionMode.map { _ in () }.eraseToAnyPublisher(),
            cameraManager.$isCameraActive.map { _ in () }.eraseToAnyPublisher(),
            appDetector.$isVideoCallAppRunning.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] in self?.rebuildMenu() }
        .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "FocusDot")
            button.image?.size = NSSize(width: 14, height: 14)
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Toggle dot
        let toggleTitle = preferences.isDotVisible ? "Hide Dot" : "Show Dot"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleDot), keyEquivalent: "d")
        toggleItem.target = self
        menu.addItem(toggleItem)

        // Auto mode
        let autoItem = NSMenuItem(title: "Auto Mode", action: #selector(toggleAutoMode), keyEquivalent: "a")
        autoItem.target = self
        autoItem.state = preferences.isAutoModeEnabled ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(NSMenuItem.separator())

        // Bouncing
        let bounceItem = NSMenuItem(title: "Auto-Bounce", action: #selector(toggleBouncing), keyEquivalent: "b")
        bounceItem.target = self
        bounceItem.state = preferences.isBouncingEnabled ? .on : .off
        menu.addItem(bounceItem)

        let bounceNowItem = NSMenuItem(title: "Bounce Now", action: #selector(bounceNow), keyEquivalent: "")
        bounceNowItem.target = self
        menu.addItem(bounceNowItem)

        menu.addItem(NSMenuItem.separator())

        // Size submenu
        let sizeMenu = NSMenu()
        for (label, size) in [("Small (15px)", 15.0), ("Medium (20px)", 20.0), ("Large (30px)", 30.0)] {
            let item = NSMenuItem(title: label, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(size)
            item.state = abs(Double(preferences.dotSize) - size) < 0.5 ? .on : .off
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Opacity submenu
        let opacityMenu = NSMenu()
        for (label, opacity) in [("Low (30%)", 0.3), ("Medium (70%)", 0.7), ("High (100%)", 1.0)] {
            let item = NSMenuItem(title: label, action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(opacity * 100)
            item.state = abs(preferences.dotOpacity - opacity) < 0.05 ? .on : .off
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        menu.addItem(opacityItem)

        // Color submenu
        let colorMenu = NSMenu()
        for dotColor in DotColor.allCases {
            let item = NSMenuItem(title: dotColor.label, action: #selector(setColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = dotColor.rawValue
            item.state = preferences.dotColor == dotColor ? .on : .off
            colorMenu.addItem(item)
        }
        let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        // Backdrop submenu
        let backdropMenu = NSMenu()
        for bd in Backdrop.allCases {
            let item = NSMenuItem(title: bd.label, action: #selector(setBackdrop(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bd.rawValue
            item.state = preferences.backdrop == bd ? .on : .off
            backdropMenu.addItem(item)
        }
        let backdropItem = NSMenuItem(title: "Backdrop", action: nil, keyEquivalent: "")
        backdropItem.submenu = backdropMenu
        menu.addItem(backdropItem)

        menu.addItem(NSMenuItem.separator())

        if preferences.isRepositionMode {
            let confirmItem = NSMenuItem(title: "Confirm Position", action: #selector(confirmReposition), keyEquivalent: "\r")
            confirmItem.target = self
            menu.addItem(confirmItem)

            let cancelItem = NSMenuItem(title: "Cancel Reposition", action: #selector(cancelReposition), keyEquivalent: "\u{1b}")
            cancelItem.target = self
            menu.addItem(cancelItem)
        } else {
            let repoItem = NSMenuItem(title: "Reposition Dot…", action: #selector(enterRepositionMode), keyEquivalent: "p")
            repoItem.target = self
            menu.addItem(repoItem)

            // Reset position (only visible when a custom position is set)
            if preferences.customPosition != nil {
                let resetItem = NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: "r")
                resetItem.target = self
                menu.addItem(resetItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Status
        let cameraStatus = cameraManager.isCameraActive ? "Camera: Active" : "Camera: Inactive"
        let cameraItem = NSMenuItem(title: cameraStatus, action: nil, keyEquivalent: "")
        cameraItem.isEnabled = false
        menu.addItem(cameraItem)

        let appStatus = appDetector.isVideoCallAppRunning ? "Video App: Detected" : "Video App: None"
        let appItem = NSMenuItem(title: appStatus, action: nil, keyEquivalent: "")
        appItem.isEnabled = false
        menu.addItem(appItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit FocusDot", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleDot() {
        preferences.isDotVisible.toggle()
        onToggleDot?(preferences.isDotVisible)
    }

    @objc private func toggleAutoMode() {
        preferences.isAutoModeEnabled.toggle()
    }

    @objc private func toggleBouncing() {
        preferences.isBouncingEnabled.toggle()
    }

    @objc private func bounceNow() {
        animator.bounceNow()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        preferences.dotSize = CGFloat(sender.tag)
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        preferences.dotOpacity = Double(sender.tag) / 100.0
    }

    @objc private func setColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let color = DotColor(rawValue: raw) else { return }
        preferences.dotColor = color
    }

    @objc private func setBackdrop(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let bd = Backdrop(rawValue: raw) else { return }
        preferences.backdrop = bd
    }

    @objc private func enterRepositionMode() {
        // Save current position so we can revert on cancel
        preferences.preRepositionPosition = preferences.customPosition
        preferences.pendingPosition = nil
        preferences.isRepositionMode = true
    }

    @objc private func confirmReposition() {
        // Save the pending position as the new custom position
        if let pending = preferences.pendingPosition {
            preferences.customPosition = pending
        }
        preferences.pendingPosition = nil
        preferences.preRepositionPosition = nil
        preferences.isRepositionMode = false
    }

    @objc private func cancelReposition() {
        // Revert to the position before entering reposition mode
        preferences.customPosition = preferences.preRepositionPosition
        preferences.pendingPosition = nil
        preferences.preRepositionPosition = nil
        preferences.isRepositionMode = false
        NotificationCenter.default.post(name: .resetDotPosition, object: nil)
    }

    @objc private func resetPosition() {
        preferences.customPosition = nil
        preferences.isRepositionMode = false
        NotificationCenter.default.post(name: .resetDotPosition, object: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension Notification.Name {
    static let resetDotPosition = Notification.Name("resetDotPosition")
}
