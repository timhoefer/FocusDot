import Foundation
import SwiftUI
import Combine

enum DotColor: String, CaseIterable {
    case green, red, blue, yellow, white, cyan, orange, pink, peach, coffee

    var color: Color {
        switch self {
        case .green:  return .green
        case .red:    return .red
        case .blue:   return .blue
        case .yellow: return .yellow
        case .white:  return .white
        case .cyan:   return .cyan
        case .orange: return .orange
        case .pink:   return .pink
        case .peach:  return Color(red: 0.93, green: 0.76, blue: 0.65)
        case .coffee: return Color(red: 0.55, green: 0.35, blue: 0.22)
        }
    }

    var label: String { rawValue.capitalized }
}

enum Backdrop: String, CaseIterable {
    case none, dark, light

    var label: String {
        switch self {
        case .none:  return "None"
        case .dark:  return "Dark"
        case .light: return "Light"
        }
    }
}

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var dotSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(dotSize), forKey: "dotSize") }
    }
    @Published var dotOpacity: Double {
        didSet { UserDefaults.standard.set(dotOpacity, forKey: "dotOpacity") }
    }
    @Published var dotColor: DotColor {
        didSet { UserDefaults.standard.set(dotColor.rawValue, forKey: "dotColor") }
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
    @Published var backdrop: Backdrop {
        didSet { UserDefaults.standard.set(backdrop.rawValue, forKey: "backdrop") }
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
        self.dotColor = DotColor(rawValue: defaults.string(forKey: "dotColor") ?? "") ?? .green
        self.isAutoModeEnabled = defaults.bool(forKey: "isAutoModeEnabled")
        self.isBouncingEnabled = defaults.bool(forKey: "isBouncingEnabled")
        self.isDotVisible = defaults.bool(forKey: "isDotVisible")
        self.backdrop = Backdrop(rawValue: defaults.string(forKey: "backdrop") ?? "") ?? .none
    }
}
