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
    private var overlayWindow: DotOverlayWindow!
    private var cameraManager: CameraManager!
    private var appDetector: AppDetector!
    private var menuBarManager: MenuBarManager!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        preferences = PreferencesManager.shared
        animator = BounceAnimator(preferences: preferences)
        cameraManager = CameraManager()
        appDetector = AppDetector()

        overlayWindow = DotOverlayWindow(preferences: preferences, animator: animator)

        menuBarManager = MenuBarManager(
            preferences: preferences,
            animator: animator,
            cameraManager: cameraManager,
            appDetector: appDetector,
            onToggleDot: { [weak self] visible in
                if visible {
                    self?.overlayWindow.showDot()
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
                    overlayWindow.showDot()
                } else {
                    overlayWindow.hideDot()
                }
            }
        }
        .store(in: &cancellables)

        // Reset position notification
        NotificationCenter.default.addObserver(
            forName: .resetDotPosition,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.overlayWindow.positionNearCamera()
        }

        // Show dot if it was visible last time and not in auto mode
        if preferences.isDotVisible && !preferences.isAutoModeEnabled {
            overlayWindow.showDot()
        }
    }
}
