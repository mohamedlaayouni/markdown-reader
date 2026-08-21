import AppKit

/// Colors and metrics shared by the preview renderer and the source highlighter.
///
/// System semantic colors carry text and chrome so light/dark and the
/// accessibility contrast settings come for free. Only the markdown syntax
/// palette is custom, and each entry is declared as a dynamic pair.
enum Theme {

    // MARK: Metrics

    /// Default reading width in points. Wide on purpose - narrower than the
    /// window but well past the ~65-character measure a typography-first
    /// editor would use.
    static let defaultMeasure: CGFloat = 880
    static let measureRange: ClosedRange<CGFloat> = 620...1040

    static let bodySize: CGFloat = 15.5
    static let bodyLineHeightMultiple: CGFloat = 1.30
    static let monoSize: CGFloat = 13
    static let sourceSize: CGFloat = 13.5
    static let sourceLineHeightMultiple: CGFloat = 1.42

    static let textInset = NSSize(width: 34, height: 18)

    /// Gap above and below a fenced code block. Applied as paragraph spacing on
    /// the block's first and last lines, which means it lands INSIDE the line
    /// fragment - so `MeasuredTextView` subtracts it back out when painting the
    /// block ground. Changing one without the other misaligns the fill.
    static let codeBlockOuterGap: CGFloat = 22
    /// Padding between the block ground's edge and the code itself.
    static let codeBlockInnerPadding: CGFloat = 9

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

    static let codeBackground = dynamic(light: "F2F1EE", dark: "26262B")
    static let ruleColor: NSColor = .separatorColor
    static let gutterColor: NSColor = .tertiaryLabelColor
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
