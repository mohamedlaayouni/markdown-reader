import Foundation
import Observation
import SwiftUI

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

    /// `nil` defers to the system, matching `.preferredColorScheme`'s own contract.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// User-facing display preferences, persisted so the app opens how you left it.
@MainActor
@Observable
final class AppSettings {
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var mode: ViewMode {
        didSet { defaults.set(mode.rawValue, forKey: Keys.mode) }
    }
    var face: Theme.BodyFace {
        didSet { defaults.set(face.rawValue, forKey: Keys.face) }
    }
    var measure: Double {
        didSet { defaults.set(measure, forKey: Keys.measure) }
    }
    var sidebarVisible: Bool {
        didSet { defaults.set(sidebarVisible, forKey: Keys.sidebar) }
    }
    var alwaysOpenInPreview: Bool {
        didSet { defaults.set(alwaysOpenInPreview, forKey: Keys.alwaysPreview) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appearance = "appearance"
        static let mode = "viewMode"
        static let face = "bodyFace"
        static let measure = "measure"
        static let sidebar = "sidebarVisible"
        static let alwaysPreview = "alwaysOpenInPreview"
    }

    init() {
        self.appearance = defaults.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        // Preview is the default: this is a reader that can edit, not an editor
        // that can preview.
        let storedMode = defaults.string(forKey: Keys.mode).flatMap(ViewMode.init(rawValue:))
        self.mode = storedMode ?? .preview
        self.face = defaults.string(forKey: Keys.face).flatMap(Theme.BodyFace.init(rawValue:)) ?? .sans
        let storedMeasure = defaults.double(forKey: Keys.measure)
        self.measure = storedMeasure == 0 ? Double(Theme.defaultMeasure) : storedMeasure
        self.sidebarVisible = defaults.object(forKey: Keys.sidebar) as? Bool ?? true
        self.alwaysOpenInPreview = defaults.object(forKey: Keys.alwaysPreview) as? Bool ?? true
    }

    /// Symmetric by construction: one function, both directions, always available.
    func toggleMode() {
        mode = (mode == .preview) ? .editor : .preview
    }
}
