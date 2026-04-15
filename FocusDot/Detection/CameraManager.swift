import Foundation
import AVFoundation
import CoreMediaIO
import Combine

struct ActiveCamera: Equatable {
    let deviceID: CMIODeviceID
    let name: String
    let isBuiltIn: Bool
}

final class CameraManager: ObservableObject {
    @Published var isCameraActive = false
    @Published var activeCamera: ActiveCamera?

    private var pollTimer: Timer?

    init() {
        // Allow CoreMediaIO to see all devices
        var allow = UInt32(1)
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectSetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &prop,
            0, nil,
            UInt32(MemoryLayout<UInt32>.size),
            &allow
        )

        checkCameraStatus()

        // Poll every 2 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkCameraStatus()
        }
    }

    private func checkCameraStatus() {
        let camera = findActiveCamera()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let nowActive = camera != nil
            if self.activeCamera != camera {
                self.activeCamera = camera
            }
            if self.isCameraActive != nowActive {
                self.isCameraActive = nowActive
            }
        }
    }

    private func findActiveCamera() -> ActiveCamera? {
        let deviceIDs = getCMIODeviceIDs()

        for deviceID in deviceIDs {
            guard isDeviceRunning(deviceID) else { continue }

            let name = getDeviceName(deviceID)
            let isBuiltIn = isDeviceBuiltIn(deviceID, name: name)
            return ActiveCamera(deviceID: deviceID, name: name, isBuiltIn: isBuiltIn)
        }

        return nil
    }

    private func getCMIODeviceIDs() -> [CMIODeviceID] {
        var dataSize: UInt32 = 0
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var result = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address, 0, nil, &dataSize
        )
        guard result == kCMIOHardwareNoError, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var ids = [CMIODeviceID](repeating: 0, count: count)

        result = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address, 0, nil, dataSize, &dataSize, &ids
        )
        guard result == kCMIOHardwareNoError else { return [] }
        return ids
    }

    private func isDeviceRunning(_ deviceID: CMIODeviceID) -> Bool {
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let result = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &size, &isRunning)
        return result == kCMIOHardwareNoError && isRunning != 0
    }

    private func getDeviceName(_ deviceID: CMIODeviceID) -> String {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOObjectPropertyName),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var nameRef: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let result = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &size, &nameRef)
        if result == kCMIOHardwareNoError, let cfStr = nameRef?.takeUnretainedValue() {
            return cfStr as String
        }
        return "Unknown Camera"
    }

    private func isDeviceBuiltIn(_ deviceID: CMIODeviceID, name: String) -> Bool {
        // Check by name heuristics — built-in cameras typically contain these strings
        let lowerName = name.lowercased()
        let builtInKeywords = ["facetime", "isight", "built-in", "builtin", "internal"]
        if builtInKeywords.contains(where: { lowerName.contains($0) }) {
            return true
        }

        // Also check the transport type — built-in cameras use USB on Apple Silicon
        // but we can check the device's "location ID" or manufacturer
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyTransportType),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let result = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, size, &size, &transport)
        if result == kCMIOHardwareNoError {
            // kIOAudioDeviceTransportTypeBuiltIn = 'bltn' = 0x626C746E
            if transport == 0x626C746E {
                return true
            }
        }

        return false
    }

    deinit {
        pollTimer?.invalidate()
    }
}
