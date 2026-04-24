import AppKit
import Combine

final class MenuBarManager {
    private var statusItem: NSStatusItem!
    private let preferences: PreferencesManager
    private let animator: BounceAnimator
    private let cameraManager: CameraManager
    private let appDetector: AppDetector
    private var onToggleDot: ((Bool) -> Void)?
    private var onRefreshAmbient: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: PreferencesManager,
        animator: BounceAnimator,
        cameraManager: CameraManager,
        appDetector: AppDetector,
        onToggleDot: @escaping (Bool) -> Void,
        onRefreshAmbient: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.animator = animator
        self.cameraManager = cameraManager
        self.appDetector = appDetector
        self.onToggleDot = onToggleDot
        self.onRefreshAmbient = onRefreshAmbient

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
            preferences.$appearanceMode.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isSystemDark.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isAmbientShadingEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isRepositionMode.map { _ in () }.eraseToAnyPublisher(),
            preferences.$isColorPickerOpen.map { _ in () }.eraseToAnyPublisher(),
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

        let colorItem = NSMenuItem(title: preferences.isColorPickerOpen ? "Close Color Picker" : "Pick Color…",
                                   action: #selector(toggleColorPicker), keyEquivalent: "")
        colorItem.target = self
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

        let appearanceMenu = NSMenu()
        for mode in AppearanceMode.allCases {
            let item = NSMenuItem(title: mode.label, action: #selector(setAppearanceMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = preferences.appearanceMode == mode ? .on : .off
            appearanceMenu.addItem(item)
        }
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        if #available(macOS 14, *) {
            let ambientItem = NSMenuItem(title: "Ambient from Desktop", action: #selector(toggleAmbient), keyEquivalent: "")
            ambientItem.target = self
            ambientItem.state = preferences.isAmbientShadingEnabled ? .on : .off
            menu.addItem(ambientItem)

            if preferences.isAmbientShadingEnabled {
                let refreshItem = NSMenuItem(title: "Refresh Ambient", action: #selector(refreshAmbient), keyEquivalent: "")
                refreshItem.target = self
                menu.addItem(refreshItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        if preferences.isRepositionMode {
            // Confirm is the inline check button on the placeholder; only Cancel here as a safety hatch.
            let cancelItem = NSMenuItem(title: "Cancel Reposition", action: #selector(cancelReposition), keyEquivalent: "\u{1b}")
            cancelItem.target = self
            menu.addItem(cancelItem)
        } else {
            let repoItem = NSMenuItem(title: "Reposition Dot…", action: #selector(enterRepositionMode), keyEquivalent: "p")
            repoItem.target = self
            menu.addItem(repoItem)

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

    @objc private func toggleColorPicker() {
        preferences.isColorPickerOpen.toggle()
    }

    @objc private func setBackdrop(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let bd = Backdrop(rawValue: raw) else { return }
        preferences.backdrop = bd
    }

    @objc private func setAppearanceMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AppearanceMode(rawValue: raw) else { return }
        preferences.appearanceMode = mode
    }

    @objc private func toggleAmbient() {
        if preferences.isAmbientShadingEnabled {
            preferences.isAmbientShadingEnabled = false
            return
        }

        // Prime once before triggering the system Screen Recording prompt.
        let alreadyGranted = CGPreflightScreenCaptureAccess()
        if !alreadyGranted && !preferences.hasSeenAmbientPriming {
            let alert = NSAlert()
            alert.messageText = "Enable Ambient Shading?"
            alert.informativeText = """
                FocusDot will read a small patch of pixels around the dot from your desktop and tint the dot's shadow side with that color — like an object catching light from its surroundings.

                macOS will ask you to grant Screen Recording permission. FocusDot only reads pixels around the dot, never any audio, and nothing is sent anywhere — all processing happens locally on your Mac.

                After granting permission you may need to quit and relaunch FocusDot.
                """
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            preferences.hasSeenAmbientPriming = true
            guard response == .alertFirstButtonReturn else { return }
        }

        preferences.isAmbientShadingEnabled = true
        onRefreshAmbient?()
    }

    @objc private func refreshAmbient() {
        onRefreshAmbient?()
    }

    @objc private func enterRepositionMode() {
        preferences.enterRepositionMode()
    }

    @objc private func cancelReposition() {
        preferences.cancelReposition()
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
