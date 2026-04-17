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
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = PreferencesManager.shared
        animator = BounceAnimator(preferences: preferences)
        interactionManager = InteractionManager(animator: animator)
        cameraManager = CameraManager()
        appDetector = AppDetector()

        overlayWindow = DotOverlayWindow(
            preferences: preferences,
            animator: animator,
            interactionManager: interactionManager
        )

        // Pause bouncing during grab, resume on release
        interactionManager.onGrabBegan = { [weak self] in
            self?.animator.pause()
        }
        interactionManager.onGrabEnded = { [weak self] in
            self?.animator.resume()
        }

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
