import SwiftUI
import Combine

@main
struct FocusDotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: PreferencesManager!
    private var animator: BounceAnimator!
    private var interactionManager: InteractionManager!
    private var overlayWindow: DotOverlayWindow!
    private var cameraManager: CameraManager!
    private var appDetector: AppDetector!
    private var menuBarManager: MenuBarManager!
    private var wallpaperSampler: WallpaperSampler!
    private var cancellables = Set<AnyCancellable>()

    static let ambientPollingInterval: TimeInterval = 0.15   // ~6–7 fps

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = PreferencesManager.shared
        animator = BounceAnimator(preferences: preferences)
        interactionManager = InteractionManager()
        cameraManager = CameraManager()
        appDetector = AppDetector()
        wallpaperSampler = WallpaperSampler()

        overlayWindow = DotOverlayWindow(
            preferences: preferences,
            animator: animator,
            interactionManager: interactionManager,
            wallpaperSampler: wallpaperSampler
        )

        // Re-sample when displays change (screen arrangement, resolution, wallpaper swap often coincides)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.wallpaperSampler.invalidateFilterCache()
            self?.overlayWindow.refreshAmbient()
        }

        // After waking from sleep, dynamic wallpapers may have shifted to a different
        // time-of-day variant. macOS may also have invalidated our poll timer.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.preferences.isAmbientShadingEnabled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.wallpaperSampler.startPolling(every: AppDelegate.ambientPollingInterval)
                self.overlayWindow.refreshAmbient()
            }
        }

        preferences.$isAmbientShadingEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.wallpaperSampler.startPolling(every: AppDelegate.ambientPollingInterval)
                    self.overlayWindow.refreshAmbient()
                } else {
                    self.wallpaperSampler.stopPolling()
                }
            }
            .store(in: &cancellables)

        // Pause bouncing during grab, resume on release
        interactionManager.onGrabBegan = { [weak self] in
            self?.animator.pause()
        }
        interactionManager.onGrabEnded = { [weak self] in
            self?.animator.resume()
        }

        // Reposition mode: dragging moves the ball
        interactionManager.onReposition = { [weak self] screenPoint in
            self?.overlayWindow.moveDotTo(screenPoint: screenPoint)
        }

        preferences.$isRepositionMode
            .sink { [weak self] mode in
                self?.interactionManager.isRepositionMode = mode
                self?.overlayWindow.setRepositionMode(mode)
            }
            .store(in: &cancellables)

        preferences.$isColorPickerOpen
            .sink { [weak self] open in
                self?.overlayWindow.setColorPickerOpen(open)
            }
            .store(in: &cancellables)

        // Keep interaction manager in sync with dot position
        animator.$offset
            .sink { [weak self] _ in
                self?.overlayWindow.updateInteractionCenter()
            }
            .store(in: &cancellables)

        menuBarManager = MenuBarManager(
            preferences: preferences,
            animator: animator,
            cameraManager: cameraManager,
            appDetector: appDetector,
            onToggleDot: { [weak self] visible in
                if visible {
                    self?.overlayWindow.showDot(camera: self?.cameraManager.activeCamera)
                } else {
                    self?.overlayWindow.hideDot()
                }
            },
            onRefreshAmbient: { [weak self] in
                self?.wallpaperSampler.invalidateFilterCache()
                self?.overlayWindow.refreshAmbient()
            }
        )

        // Auto mode: show/hide dot based on camera activity
        Publishers.CombineLatest3(
            preferences.$isAutoModeEnabled,
            cameraManager.$isCameraActive,
            appDetector.$isVideoCallAppRunning
        )
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] autoMode, cameraActive, videoAppRunning in
            guard let self, autoMode else { return }
            let shouldShow = cameraActive || videoAppRunning
            if shouldShow != preferences.isDotVisible {
                preferences.isDotVisible = shouldShow
                if shouldShow {
                    overlayWindow.showDot(camera: cameraManager.activeCamera)
                } else {
                    overlayWindow.hideDot()
                }
            }
        }
        .store(in: &cancellables)

        // Reposition dot when the active camera changes
        cameraManager.$activeCamera
            .removeDuplicates()
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] camera in
                guard let self, preferences.isDotVisible, camera != nil else { return }
                overlayWindow.positionNearCamera(on: camera)
            }
            .store(in: &cancellables)

        // Reset position notification
        NotificationCenter.default.addObserver(
            forName: .resetDotPosition,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.overlayWindow.positionNearCamera(on: self?.cameraManager.activeCamera)
        }

        // Always show the dot on launch
        preferences.isDotVisible = true
        overlayWindow.showDot(camera: cameraManager.activeCamera)

        // Ensure interaction center is set after window is fully positioned
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.overlayWindow.updateInteractionCenter()
        }

        // If auto mode is on, re-evaluate after camera manager has time to poll
        if preferences.isAutoModeEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.evaluateAutoMode()
            }
        }
    }

    private func evaluateAutoMode() {
        guard preferences.isAutoModeEnabled else { return }
        let shouldShow = cameraManager.isCameraActive || appDetector.isVideoCallAppRunning
        if shouldShow != preferences.isDotVisible {
            preferences.isDotVisible = shouldShow
            if shouldShow {
                overlayWindow.showDot(camera: cameraManager.activeCamera)
            } else {
                overlayWindow.hideDot()
            }
        }
    }
}
