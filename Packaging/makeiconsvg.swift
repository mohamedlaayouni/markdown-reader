// Emits the .md mark as two SVG layers for the Icon Composer bundle
// (Packaging/AppIcon.icon): dot.svg and letters.svg. Geometry matches makeicon.swift.
import AppKit
import CoreText
let dir = CommandLine.arguments[1]
let side: CGFloat = 1024, inset: CGFloat = 84
let plate = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset)
func makeLine(size: CGFloat) -> (CTLine, CGRect, NSFont) {
    let base = NSFont.systemFont(ofSize: size, weight: .semibold)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "md", attributes: [.font: font, .kern: -size * 0.03]))
    return (line, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds), font)
}
let dotShare: CGFloat = 0.40, gapShare: CGFloat = 0.20, markShare: CGFloat = 0.60
let probe = makeLine(size: 100)
let probeWidth = probe.1.height * (dotShare + gapShare) + probe.1.width
let (line, ink, _) = makeLine(size: 100 * (plate.width * markShare) / probeWidth)
let dot = ink.height * dotShare, gap = ink.height * gapShare
let originX = plate.midX - (dot + gap + ink.width) / 2
let baselineY = plate.midY - ink.height / 2 - ink.minY + ink.height * 0.06
// SVG is y-down: flip around the canvas.
let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: side)
let path = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    let font = unsafeBitCast(CFDictionaryGetValue(CTRunGetAttributes(run), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque()), to: CTFont.self)
    for (glyph, position) in zip(glyphs, positions) {
        var transform = CGAffineTransform(translationX: originX + dot + gap - ink.minX + position.x, y: baselineY + position.y).concatenating(flip)
        if let glyphPath = CTFontCreatePathForGlyph(font, glyph, &transform) { path.addPath(glyphPath) }
    }
}
var d = ""
path.applyWithBlock { element in
    let p = element.pointee.points
    func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
    switch element.pointee.type {
    case .moveToPoint: d += "M\(f(p[0].x)) \(f(p[0].y))"
    case .addLineToPoint: d += "L\(f(p[0].x)) \(f(p[0].y))"
    case .addQuadCurveToPoint: d += "Q\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y))"
    case .addCurveToPoint: d += "C\(f(p[0].x)) \(f(p[0].y)) \(f(p[1].x)) \(f(p[1].y)) \(f(p[2].x)) \(f(p[2].y))"
    case .closeSubpath: d += "Z"
    @unknown default: break
    }
}
let head = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\" width=\"1024\" height=\"1024\">"
try! "\(head)\n  <path d=\"\(d)\" fill=\"#FFFFFF\" fill-rule=\"nonzero\"/>\n</svg>\n".write(toFile: dir + "/letters.svg", atomically: true, encoding: .utf8)
let cy = side - (baselineY + dot / 2)
try! "\(head)\n  <circle cx=\"\(originX + dot / 2)\" cy=\"\(cy)\" r=\"\(dot / 2)\" fill=\"#E5484D\"/>\n</svg>\n".write(toFile: dir + "/dot.svg", atomically: true, encoding: .utf8)
