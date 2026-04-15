import Foundation
import AppKit
import Combine

final class AppDetector: ObservableObject {
    @Published var isVideoCallAppRunning = false

    private static let videoCallBundleIDs: Set<String> = [
        "us.zoom.xos",
        "us.zoom.xos.Zoom",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.apple.FaceTime",
        "com.cisco.webexmeetingsapp",
        "com.webex.meetingmanager",
        "com.google.Chrome",           // Meet runs in Chrome
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.apple.Safari",
        "com.skype.skype",
        "com.discord.Discord",
        "com.loom.desktop",
    ]

    private var timer: Timer?

    init() {
        startMonitoring()
    }

    private func startMonitoring() {
        checkRunningApps()

        // Poll every 5 seconds — lightweight check
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkRunningApps()
        }

        // Also respond to app launch/quit
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    @objc private func appChanged(_ notification: Notification) {
        checkRunningApps()
    }

    private func checkRunningApps() {
        let running = NSWorkspace.shared.runningApplications
        let hasVideoApp = running.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return Self.videoCallBundleIDs.contains(bundleID)
        }
        if isVideoCallAppRunning != hasVideoApp {
            isVideoCallAppRunning = hasVideoApp
        }
    }

    deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
