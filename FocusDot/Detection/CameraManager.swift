import Foundation
import AVFoundation
import CoreMediaIO
import Combine

final class CameraManager: ObservableObject {
    @Published var isCameraActive = false

    private var pollTimer: Timer?

    init() {
        // Allow CoreMediaIO to see all devices (needed outside sandbox for some cameras)
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

        // Poll every 2 seconds — lightweight CoreMediaIO check
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkCameraStatus()
        }
    }

    private func checkCameraStatus() {
        let active = isAnyCameraRunning()
        if isCameraActive != active {
            DispatchQueue.main.async { [weak self] in
                self?.isCameraActive = active
            }
        }
    }

    private func isAnyCameraRunning() -> Bool {
        // Get all CoreMediaIO device IDs
        var dataSize: UInt32 = 0
        var devicesAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var result = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0, nil,
            &dataSize
        )
        guard result == kCMIOHardwareNoError, dataSize > 0 else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var deviceIDs = [CMIODeviceID](repeating: 0, count: deviceCount)

        result = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &devicesAddress,
            0, nil,
            dataSize,
            &dataSize,
            &deviceIDs
        )
        guard result == kCMIOHardwareNoError else { return false }

        // Check each device for "is running somewhere"
        for deviceID in deviceIDs {
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )

            let readResult = CMIOObjectGetPropertyData(
                deviceID,
                &runningAddress,
                0, nil,
                runningSize,
                &runningSize,
                &isRunning
            )

            if readResult == kCMIOHardwareNoError && isRunning != 0 {
                return true
            }
        }

        return false
    }

    deinit {
        pollTimer?.invalidate()
    }
}
