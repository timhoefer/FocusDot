import AppKit
import Combine
import SwiftUI
import ScreenCaptureKit

extension NSScreen {
    /// CGDirectDisplayID for this NSScreen, if available.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Samples the desktop near a screen point and publishes the average color as
/// an ambient light cue. Uses ScreenCaptureKit on macOS 14+ — no-op on 13.
///
/// Triggers the Screen Recording permission prompt on first capture. If denied,
/// subsequent captures fail silently and the published color stays grey.
final class WallpaperSampler: ObservableObject {
    /// Current ambient color. Grey until the first successful sample.
    @Published private(set) var ambientColor: Color = Color(white: 0.5)

    private(set) var excludedWindowIDs: Set<CGWindowID> = []

    private var lastSampled: (screen: NSScreen, point: CGPoint)?
    private var pollTimer: Timer?
    private var inFlight = false
    // Cached so we don't re-enumerate every on-screen window 7×/sec.
    // Invalidated on display change or window-exclusion change.
    private var cachedFilter: (displayID: CGDirectDisplayID, filter: Any)?
    private var lastPixel: (UInt8, UInt8, UInt8)?

    func excludeWindow(_ id: CGWindowID) {
        excludedWindowIDs.insert(id)
        invalidateFilterCache()
    }

    func invalidateFilterCache() {
        cachedFilter = nil
    }

    /// Sample around `dotCenter` (global screen coords, y-up) on the given screen.
    /// No-op on macOS < 14.
    func sample(near dotCenter: CGPoint, on screen: NSScreen) {
        lastSampled = (screen, dotCenter)
        guard #available(macOS 14, *) else { return }
        guard !inFlight else { return }
        inFlight = true
        Task { [weak self] in
            await self?.captureAndSample(near: dotCenter, on: screen)
            self?.inFlight = false
        }
    }

    /// Resample at the last known dot/screen pair.
    func refresh() {
        guard let (screen, point) = lastSampled else { return }
        sample(near: point, on: screen)
    }

    /// Start periodic resampling at the given interval. No-op on macOS < 14.
    func startPolling(every interval: TimeInterval) {
        pollTimer?.invalidate()
        guard #available(macOS 14, *) else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - ScreenCaptureKit

    @available(macOS 14, *)
    private func resolvedFilter(for displayID: CGDirectDisplayID) async throws -> SCContentFilter? {
        if let cached = cachedFilter, cached.displayID == displayID, let f = cached.filter as? SCContentFilter {
            return f
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                            onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let excluded = content.windows.filter { excludedWindowIDs.contains(CGWindowID($0.windowID)) }
        let f = SCContentFilter(display: scDisplay, excludingWindows: excluded)
        cachedFilter = (displayID, f)
        return f
    }

    @available(macOS 14, *)
    private func captureAndSample(near point: CGPoint, on screen: NSScreen) async {
        guard let displayID = screen.displayID else { return }
        do {
            guard let filter = try await resolvedFilter(for: displayID) else { return }

            // Crop server-side to a small patch around the dot — minimal bandwidth.
            // Convert from NSScreen (bottom-left, y-up) to display-local (top-left, y-down).
            let patch: CGFloat = 240
            let lx = point.x - screen.frame.minX
            let ly = screen.frame.height - (point.y - screen.frame.minY)
            let sourceRect = CGRect(
                x: max(0, lx - patch / 2),
                y: max(0, ly - patch / 2),
                width: patch,
                height: patch
            )

            let cfg = SCStreamConfiguration()
            cfg.sourceRect = sourceRect
            cfg.width = max(1, Int(sourceRect.width))
            cfg.height = max(1, Int(sourceRect.height))
            cfg.showsCursor = false
            cfg.capturesAudio = false

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                      configuration: cfg)

            var pxBuf: [UInt8] = [0, 0, 0, 0]
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let ctx = CGContext(data: &pxBuf,
                                      width: 1, height: 1,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4,
                                      space: cs,
                                      bitmapInfo: bi) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

            let key = (pxBuf[0], pxBuf[1], pxBuf[2])
            if let last = lastPixel, last == key { return }
            lastPixel = key

            let nsColor = NSColor(red: CGFloat(pxBuf[0]) / 255,
                                  green: CGFloat(pxBuf[1]) / 255,
                                  blue: CGFloat(pxBuf[2]) / 255,
                                  alpha: 1.0)
            await MainActor.run {
                self.ambientColor = Color(nsColor: nsColor)
            }
        } catch {
            // Once permission is granted macOS doesn't re-prompt, so retrying on
            // transient failures (sleep/wake, transient SC errors) is harmless.
            NSLog("[AmbientSampler] capture failed: %@", error.localizedDescription)
        }
    }
}
