import SwiftUI
import AppKit

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private let appearanceKey = "appearance"
    private let intervalKey = "pingIntervalSeconds"
    private let showStatusIconsKey = "showStatusIcons"
    private let latencyDecimalsKey = "latencyDecimals"
    private let pushTimeoutsKey = "pushTimeoutsToBottom"
    private let monochromeKey = "monochrome"
    private let dimModeKey = "dimMode"
    private let dimOpacityKey = "dimOpacity"

    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: appearanceKey)
            applyAppearance()
        }
    }

    @Published var pingIntervalSeconds: Int {
        didSet { defaults.set(pingIntervalSeconds, forKey: intervalKey) }
    }

    @Published var showStatusIcons: Bool {
        didSet { defaults.set(showStatusIcons, forKey: showStatusIconsKey) }
    }

    @Published var latencyDecimals: Int {
        didSet { defaults.set(latencyDecimals, forKey: latencyDecimalsKey) }
    }

    @Published var pushTimeoutsToBottom: Bool {
        didSet { defaults.set(pushTimeoutsToBottom, forKey: pushTimeoutsKey) }
    }

    @Published var monochrome: Bool {
        didSet { defaults.set(monochrome, forKey: monochromeKey) }
    }

    @Published var dimMode: Bool {
        didSet { defaults.set(dimMode, forKey: dimModeKey) }
    }

    @Published var dimOpacity: Double {
        didSet { defaults.set(dimOpacity, forKey: dimOpacityKey) }
    }

    init() {
        let stored = defaults.string(forKey: appearanceKey).flatMap(Appearance.init(rawValue:)) ?? .system
        self.appearance = stored
        let interval = defaults.integer(forKey: intervalKey)
        self.pingIntervalSeconds = interval > 0 ? interval : 5
        self.showStatusIcons = defaults.object(forKey: showStatusIconsKey) as? Bool ?? true
        let rawDecimals = defaults.object(forKey: latencyDecimalsKey) as? Int ?? 0
        self.latencyDecimals = max(0, min(3, rawDecimals))
        self.pushTimeoutsToBottom = defaults.object(forKey: pushTimeoutsKey) as? Bool ?? false
        self.monochrome = defaults.object(forKey: monochromeKey) as? Bool ?? false
        self.dimMode = defaults.object(forKey: dimModeKey) as? Bool ?? false
        let rawDim = defaults.object(forKey: dimOpacityKey) as? Double ?? 0.55
        self.dimOpacity = max(0.2, min(0.9, rawDim))
        applyAppearance()
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
