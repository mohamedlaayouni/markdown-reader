import SwiftUI

/// Metrics shared by the app's control family.
///
/// Save (toolbar) and `+` (sidebar) are siblings. Spelling their diameter once
/// is what stops them drifting into a rounded square and a circle again.
enum Controls {
    static let circleDiameter: CGFloat = 30
    /// Gap between the Save button and the Preview/Editor picker. Also the
    /// `GlassEffectContainer` spacing, so the two shapes merge as they approach.
    static let toolbarGap: CGFloat = 14
    /// Stroke weight for drawn glyphs, matching `SaveDiskIcon`.
    static let glyphStroke: CGFloat = 1.5
}

/// The `+` glyph, drawn rather than typed.
///
/// A text "+" at `line-height: 1` sits above the optical centre of its box, so
/// it never quite lines up with the disk beside it. A stroked cross is centred
/// geometrically and needs no nudge.
struct PlusCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm = min(rect.width, rect.height) / 2
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - arm))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + arm))
        path.move(to: CGPoint(x: rect.midX - arm, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + arm, y: rect.midY))
        return path
    }
}

/// The magnifier in the sidebar's filter field.
struct MagnifierGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.30
        let centre = CGPoint(x: rect.minX + radius + 0.8, y: rect.minY + radius + 0.8)
        path.addEllipse(
            in: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        let diagonal = radius * 0.7071
        path.move(to: CGPoint(x: centre.x + diagonal, y: centre.y + diagonal))
        path.addLine(to: CGPoint(x: rect.maxX - 0.6, y: rect.maxY - 0.6))
        return path
    }
}

/// The document glyph that gives every library row an identity at rest.
///
/// A rounded outline with three interior rules, the last at 60% width. The
/// proportions are the point: at 17x21 it reads as a page rather than as a
/// generic icon, and it is legible at the tertiary fill it sits at by default.
struct DocumentGlyph: View {
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 17, height: 21)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(color, lineWidth: 1.2)

            VStack(spacing: 2.5) {
                rule(width: 1)
                rule(width: 1)
                rule(width: 0.6)
            }
            .padding(.horizontal, 3.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(reduceMotion ? nil : Motion.hover, value: color)
    }

    private func rule(width: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: proxy.size.width * width, height: 1.2)
        }
        .frame(height: 1.2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Press and hover feedback

/// Hover-only growth.
///
/// There is deliberately no press treatment here. Every button in the app wears
/// `.glassEffect(.regular.interactive())`, and interactive glass owns its own
/// press: it deforms the material rather than scaling the layer, which a hand
/// written `scaleEffect` cannot reproduce and would only fight. Hover is the
/// one state the material does not cover on macOS.
struct HoverGrow: ViewModifier {
    var scale: CGFloat = 1.07
    var lift: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? scale : 1)
            .offset(y: hovering && !reduceMotion ? lift : 0)
            .animation(reduceMotion ? nil : Motion.press, value: hovering)
            .onHover { hovering = $0 && isEnabled }
    }
}

extension View {
    func hoverGrow(scale: CGFloat = 1.07, lift: CGFloat = 0) -> some View {
        modifier(HoverGrow(scale: scale, lift: lift))
    }
}

// MARK: - Motion

/// Shared Apple spring presets for custom interactions. Native controls and
/// scrolling retain their own system motion; callers respect Reduce Motion.
enum Motion {
    static let press = Animation.smooth(duration: 0.18)
    static let hover = Animation.smooth(duration: 0.18)
    static let sidebar = Animation.smooth(duration: 0.28)
}

// MARK: - Glass segmented control

/// A capsule, glass replacement for `.pickerStyle(.segmented)`.
///
/// Native segmented controls pick up the Tahoe capsule/glass treatment when
/// they sit in a toolbar, but not inside a `Form` - Settings' two pickers stay
/// the old 8pt-radius, solid-fill style there regardless of `.pickerStyle`.
/// This is what actually gets them onto glass.
struct GlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(option)
            }
        }
        .padding(2)
        .glassEffect(.regular, in: .capsule)
    }

    private func segment(_ option: (value: Value, label: String)) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.label)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule().glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .animation(reduceMotion ? nil : Motion.press, value: isSelected)
    }
}
