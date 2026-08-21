import SwiftUI

/// A minimal floppy-disk silhouette for the Save button.
///
/// SF Symbols has no floppy disk glyph at all - Apple deliberately never shipped
/// one - so the closest built-ins (`opticaldisc`, `square.and.arrow.down`) read
/// as "CD" or "download," not "save." This draws the two shapes that make the
/// silhouette instantly recognisable: the body and the label.
struct SaveDiskIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        let corner = body.width * 0.16

        path.addRoundedRect(in: body, cornerSize: CGSize(width: corner, height: corner))

        // The shutter: flush with the top edge, narrower than the body - this is
        // the detail that reads as "floppy disk" rather than "nested squares."
        let shutterWidth = body.width * 0.46
        let shutter = CGRect(
            x: body.midX - shutterWidth / 2,
            y: body.minY,
            width: shutterWidth,
            height: body.height * 0.26
        )
        path.addRoundedRect(
            in: shutter,
            cornerSize: CGSize(width: corner * 0.3, height: corner * 0.3)
        )

        // The label: wider than the shutter, sitting just above the bottom edge.
        let labelWidth = body.width * 0.64
        let labelHeight = body.height * 0.32
        let label = CGRect(
            x: body.midX - labelWidth / 2,
            y: body.maxY - labelHeight - body.height * 0.09,
            width: labelWidth,
            height: labelHeight
        )
        path.addRoundedRect(
            in: label,
            cornerSize: CGSize(width: corner * 0.3, height: corner * 0.3)
        )

        return path
    }
}
