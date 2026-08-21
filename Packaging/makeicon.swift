// Draws the app icon at 1024pt. Run via `swift Packaging/makeicon.swift <out.png>`.
import AppKit
import CoreGraphics

let side = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

guard let context = CGContext(
    data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let full = CGRect(x: 0, y: 0, width: side, height: side)

// Rounded-rect ground with a vertical gradient, matching the app's paper tone.
let inset: CGFloat = 84
let plate = full.insetBy(dx: inset, dy: inset)
let radius: CGFloat = 190
let path = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

context.saveGState()
context.addPath(path)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.267, green: 0.412, blue: 0.784, alpha: 1),
        CGColor(srgbRed: 0.157, green: 0.278, blue: 0.612, alpha: 1),
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: plate.minX, y: plate.maxY),
    end: CGPoint(x: plate.maxX, y: plate.minY),
    options: []
)
context.restoreGState()

// Three text lines, the third short: the universal "document" read, and it
// stays legible at 16pt where a literal page outline turns to mush.
context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
context.setLineCap(.round)
context.setLineWidth(60)

let lines: [(CGFloat, CGFloat)] = [(0.62, 0.60), (0.50, 0.60), (0.38, 0.34)]
for (yFraction, widthFraction) in lines {
    let y = plate.minY + plate.height * yFraction
    let lineWidth = plate.width * widthFraction
    let x = plate.midX - lineWidth / 2
    context.move(to: CGPoint(x: x, y: y))
    context.addLine(to: CGPoint(x: x + lineWidth, y: y))
    context.strokePath()
}

// The toggle: a small capsule, the one control the app is built around.
let capsule = CGRect(x: plate.midX - 150, y: plate.minY + plate.height * 0.20, width: 300, height: 92)
context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
context.addPath(CGPath(roundedRect: capsule, cornerWidth: 46, cornerHeight: 46, transform: nil))
context.fillPath()
let knob = CGRect(x: capsule.minX + 10, y: capsule.minY + 10, width: 136, height: 72)
context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
context.addPath(CGPath(roundedRect: knob, cornerWidth: 36, cornerHeight: 36, transform: nil))
context.fillPath()

guard let image = context.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(filePath: outPath))
