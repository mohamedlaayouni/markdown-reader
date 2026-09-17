import AppKit
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

    /// `nil` defers to the system, matching `NSApplication.appearance`'s own
    /// contract.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// User-facing display preferences, persisted so the app opens how you left it.
@MainActor
@Observable
final class AppSettings {
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance); applyAppearance() }
    }

    /// Appearance is applied to `NSApplication`, not through
    /// `.preferredColorScheme`.
    ///
    /// SwiftUI pins `NSWindow.appearance` when the scheme is explicit but does
    /// not clear it when the scheme goes back to nil - so choosing System after
    /// Light or Dark left every window stuck on whichever was picked last.
    /// `NSApplication.appearance` has a real nil, and it reaches the Settings
    /// window and the menus too, which a per-view modifier cannot.
    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
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

    var textSize: Double = UserDefaults.standard.object(forKey: "textSize") as? Double ?? 16 {
        didSet { defaults.set(textSize, forKey: "textSize") }
    }
    var sidebarWidth: Double = UserDefaults.standard.object(forKey: "sidebarWidth") as? Double ?? 262 {
        didSet { defaults.set(sidebarWidth, forKey: "sidebarWidth") }
    }
    func preset(_ name: String) {
        switch name {
        case "Book": face = .serif; measure = 560; textSize = 18
        case "Technical": face = .sans; measure = 880; textSize = 16
        default: face = .sans; measure = 560; textSize = 16
        }
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
        applyAppearance()
    }

    /// Symmetric by construction: one function, both directions, always available.
    func toggleMode() {
        mode = (mode == .preview) ? .editor : .preview
    }
}
