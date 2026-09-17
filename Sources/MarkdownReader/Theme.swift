import AppKit

/// Colors and metrics shared by the preview renderer and the source highlighter.
///
/// System semantic colors carry text and chrome so light/dark and the
/// accessibility contrast settings come for free. Only the markdown syntax
/// palette is custom, and each entry is declared as a dynamic pair.
enum Theme {

    // MARK: Metrics

    /// Default reading width in points. Wide on purpose - this is a technical
    /// reader, not a novel - but 880pt put ~122 characters on a line, and the
    /// old 620pt floor meant the "Narrow" end of the slider was still ~86. The
    /// range now reaches a real book measure at the bottom and keeps the wide
    /// end for anyone who wants it.
    static let defaultMeasure: CGFloat = 560
    static let measureRange: ClosedRange<CGFloat> = 480...1040

    static let bodySize: CGFloat = 15.5
    /// Leading has to grow with the measure, not stay fixed against it: the
    /// longer the line, the more help the eye needs finding the start of the
    /// next one. At 1.30 across a 100+ character line, it was losing its place.
    static let bodyLineHeightMultiple: CGFloat = 1.50

    static let monoSize: CGFloat = 13
    static let sourceSize: CGFloat = 13.5
    static let sourceLineHeightMultiple: CGFloat = 1.42

    static let textInset = NSSize(width: 34, height: 32)

    // MARK: Fonts

    /// The body face. Sans is the default; the other two are user-selectable.
    enum BodyFace: String, CaseIterable, Identifiable {
        case sans, serif, mono
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sans: return "Sans"
            case .serif: return "Serif"
            case .mono: return "Mono"
            }
        }
    }

    static func body(_ face: BodyFace, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch face {
        case .sans:
            return .systemFont(ofSize: size, weight: weight)
        case .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let serif = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
            return NSFont(descriptor: serif, size: size) ?? base
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    // MARK: Syntax palette

    /// A translucent overlay whose alpha differs between appearances. Black
    /// over light, white over dark - the same trick a material uses.
    private static func layer(light: CGFloat, dark: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark ? NSColor(white: 1, alpha: dark) : NSColor(white: 0, alpha: light)
        }
    }

    private static func dynamic(light: String, dark: String) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }

    /// Matched-lightness palette; only the hue varies between roles.
    static let synHeading  = dynamic(light: "A8422A", dark: "E8956F")
    static let synEmphasis = dynamic(light: "8A6100", dark: "D9A94A")
    static let synCode     = dynamic(light: "00786A", dark: "4FC0AE")
    static let synLink     = dynamic(light: "2D6BB8", dark: "6FA8E8")
    static let synList     = dynamic(light: "8B4BAF", dark: "C48FE0")
    static let synKeyword  = dynamic(light: "A03A96", dark: "DE8ED6")
    static let synFunction = dynamic(light: "10648F", dark: "63AEDA")

    // MARK: Sidebar

    static let sidebarWidth: CGFloat = 262
    /// Ground under an unselected row the pointer is over. Unselected rows had
    /// no hover state at all; the row only acknowledged you after the click.
    static let sidebarRowHover: NSColor = layer(light: 0.035, dark: 0.07)
    /// `List(selection:)`'s own highlight is a solid accent fill - correct for
    /// an ordinary list, wrong for a reference library where the row's own
    /// content (the glyph, the missing-file amber) needs to stay legible
    /// through it. Applied as the List's `.tint()`, which is what actually
    /// drives its selection color on macOS, rather than as a background this
    /// spec would just paint over.
    static let sidebarSelectionTint: NSColor = layer(light: 0.065, dark: 0.13)
    /// A reference whose file no longer resolves. Amber, not red: the row is
    /// recoverable through Locate, and red would read as an error.
    static let missingReference = dynamic(light: "D97706", dark: "D97706")
}

extension Theme {
    /// Roughly how many characters fit on a line at `measure`.
    ///
    /// Points are not a reading decision; characters per line are. Measured from
    /// a real sample rather than assumed, so it stays true across the three
    /// selectable faces.
    static func charactersPerLine(measure: CGFloat, face: BodyFace) -> Int {
        let sample = "The quick brown fox jumps over the lazy dog. "
        let width = (sample as NSString)
            .size(withAttributes: [.font: body(face, size: bodySize)])
            .width
        guard width > 0 else { return 0 }
        return Int((measure / (width / CGFloat(sample.count))).rounded())
    }
}

extension NSColor {
    /// Six-digit RRGGBB. Falls back to label color on a malformed string
    /// rather than trapping, since these are compile-time literals.
    convenience init(hex: String) {
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value), hex.count == 6 else {
            self.init(white: 0.5, alpha: 1)
            return
        }
        self.init(
            srgbRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
