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
    static let defaultMeasure: CGFloat = 720
    static let measureRange: ClosedRange<CGFloat> = 480...1040

    static let bodySize: CGFloat = 15.5
    /// Leading has to grow with the measure, not stay fixed against it: the
    /// longer the line, the more help the eye needs finding the start of the
    /// next one. At 1.30 across a 100+ character line, it was losing its place.
    static let bodyLineHeightMultiple: CGFloat = 1.50

    /// Heading sizes, h1 through h6.
    ///
    /// Every level stays above `bodySize`. A heading that renders at or below
    /// the size of the text it introduces stops being a heading - it reads as
    /// bold body text, and the document can no longer be understood by scanning.
    /// The steps shrink as the level deepens (1.28, 1.19, 1.14, 1.09, 1.06)
    /// because the top levels need to carve the page while the bottom ones only
    /// need to be tellable apart from their neighbour.
    static let headingSizes: [CGFloat] = [32, 25, 21, 18.5, 17, 16]
    static let monoSize: CGFloat = 13
    static let sourceSize: CGFloat = 13.5
    static let sourceLineHeightMultiple: CGFloat = 1.42

    static let textInset = NSSize(width: 34, height: 32)

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
    /// The bar down the left of a blockquote.
    static let quoteBarColor: NSColor = .tertiaryLabelColor
    static let quoteBarWidth: CGFloat = 2.5
    /// Indent added per level of quote nesting. The bar sits in this gutter, so
    /// the two have to agree.
    static let quoteIndent: CGFloat = 18
    /// Trailing gap under a paragraph.
    static let paragraphGap: CGFloat = 12
    static let gutterColor: NSColor = .tertiaryLabelColor
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
