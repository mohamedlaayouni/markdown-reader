// Draws the app icon at 1024pt. Run via `swift Packaging/makeicon.swift <out.png>`.
//
// The icon is the file extension the app exists to open: `.md`, set as a
// wordmark. The leading dot is the one deliberate liberty - drawn as its own
// circle, far larger than any period, in the accent the preview uses for list
// markers and quote bars. It is what makes the mark legible at 16pt, where the
// letters alone would close up, and what keeps it from reading as a generic
// document.
import AppKit
import CoreGraphics
import CoreText

let side = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let context = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let full = CGRect(x: 0, y: 0, width: side, height: side)

// Rounded-rect ground, inset and radiused to macOS proportions.
let inset: CGFloat = 84
let plate = full.insetBy(dx: inset, dy: inset)
let radius: CGFloat = 190
let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Paper, not chrome: this is a reader, and the warm off-white is the same
// ground the preview puts text on.
context.saveGState()
context.addPath(platePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.996, green: 0.992, blue: 0.984, alpha: 1),
        CGColor(srgbRed: 0.937, green: 0.925, blue: 0.906, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: plate.midX, y: plate.maxY),
    end: CGPoint(x: plate.midX, y: plate.minY),
    options: []
)
context.restoreGState()

// A hairline inside the edge so the plate still has a shape against a white
// background in the Finder's list and column views.
context.saveGState()
context.addPath(platePath)
context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08))
context.setLineWidth(4)
context.strokePath()
context.restoreGState()

// The wordmark. Rounded rather than mono: mono says "code", and markdown is
// prose that happens to be plain text.
let ink = CGColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1)
let accent = CGColor(srgbRed: 0.898, green: 0.282, blue: 0.302, alpha: 1)

// Sized by fitting, not by a guessed point size: the group is laid out once at
// a reference size, measured, and scaled so it occupies a fixed share of the
// plate. That keeps the optical margin right whatever the system face does.
func makeLine(size: CGFloat) -> (line: CTLine, ink: CGRect) {
    let base = NSFont.systemFont(ofSize: size, weight: .semibold)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    let font = NSFont(descriptor: descriptor, size: size) ?? base
    let letters = NSAttributedString(string: "md", attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: ink)!,
        // Tightened: at this size the default fit leaves the pair looking loose.
        .kern: -size * 0.03,
    ])
    let line = CTLineCreateWithAttributedString(letters)
    // Glyph path bounds, not typographic bounds: the mark is centred on the ink
    // that is actually drawn, which is what the eye reads.
    return (line, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
}

// Proportions of the letter height, so the three parts scale together.
let dotShare: CGFloat = 0.40
let gapShare: CGFloat = 0.20
/// Share of the plate the whole mark spans. The remainder is the optical
/// margin, which the rounded corners need more of than a square plate would.
let markShare: CGFloat = 0.60

let probe = makeLine(size: 100)
let probeWidth = probe.ink.height * (dotShare + gapShare) + probe.ink.width
let (line, inkBounds) = makeLine(size: 100 * (plate.width * markShare) / probeWidth)

let dotDiameter = inkBounds.height * dotShare
let gap = inkBounds.height * gapShare
let groupWidth = dotDiameter + gap + inkBounds.width

let originX = plate.midX - groupWidth / 2
// Centring on the ink alone sits the mark low: the `d` ascender is counted in
// full, but the eye weights the x-height mass, which is all below it. Lifting
// by a share of the overshoot puts the optical centre on the plate's centre.
let baselineY = plate.midY - inkBounds.height / 2 - inkBounds.minY + inkBounds.height * 0.06

// The dot sits on the baseline, sized against the letters so it reads as a
// deliberate mark rather than a period that got away.
context.setFillColor(accent)
context.fillEllipse(in: CGRect(x: originX, y: baselineY, width: dotDiameter, height: dotDiameter))

context.textPosition = CGPoint(x: originX + dotDiameter + gap - inkBounds.minX, y: baselineY)
CTLineDraw(line, context)

guard let image = context.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(filePath: outPath))
