import Foundation
import Combine

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var dotSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(dotSize), forKey: "dotSize") }
    }
    @Published var dotOpacity: Double {
        didSet { UserDefaults.standard.set(dotOpacity, forKey: "dotOpacity") }
    }
    @Published var isAutoModeEnabled: Bool {
        didSet { UserDefaults.standard.set(isAutoModeEnabled, forKey: "isAutoModeEnabled") }
    }
    @Published var isBouncingEnabled: Bool {
        didSet { UserDefaults.standard.set(isBouncingEnabled, forKey: "isBouncingEnabled") }
    }
    @Published var isDotVisible: Bool {
        didSet { UserDefaults.standard.set(isDotVisible, forKey: "isDotVisible") }
    }

    private init() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: "dotSize") == nil {
            defaults.set(20.0, forKey: "dotSize")
        }
        if defaults.object(forKey: "dotOpacity") == nil {
            defaults.set(0.7, forKey: "dotOpacity")
        }
        if defaults.object(forKey: "isAutoModeEnabled") == nil {
            defaults.set(true, forKey: "isAutoModeEnabled")
        }
        if defaults.object(forKey: "isBouncingEnabled") == nil {
            defaults.set(true, forKey: "isBouncingEnabled")
        }

        self.dotSize = CGFloat(defaults.double(forKey: "dotSize"))
        self.dotOpacity = defaults.double(forKey: "dotOpacity")
        self.isAutoModeEnabled = defaults.bool(forKey: "isAutoModeEnabled")
        self.isBouncingEnabled = defaults.bool(forKey: "isBouncingEnabled")
        self.isDotVisible = defaults.bool(forKey: "isDotVisible")
    }
}
