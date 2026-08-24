import AppKit
import Markdown

extension NSAttributedString.Key {
    /// Range should be painted as one solid rectangle spanning the text column.
    /// `.backgroundColor` cannot do this: it fills each glyph run, so blank and
    /// short lines leave a staircase.
    static let blockFill = NSAttributedString.Key("mdBlockFill")
    /// Range should be painted as a horizontal rule across the text column.
    static let blockRule = NSAttributedString.Key("mdBlockRule")
    /// Range should carry a blockquote bar down its left edge. The value is the
    /// bar's x offset inside the text column, so nested quotes stack.
    static let blockQuoteBar = NSAttributedString.Key("mdBlockQuoteBar")
    /// This range is a task-list checkbox; the value is its 1-based source line.
    ///
    /// Hit-testing goes through this rather than the `.link` attribute. Links
    /// depend on `NSTextView`'s link delegation, which did not fire reliably for
    /// the checkbox runs; a `mouseDown` override reading this attribute is a
    /// direct path with nothing in between.
    static let taskToggleLine = NSAttributedString.Key("mdTaskToggleLine")
}

/// Turns a parsed markdown tree into an `NSAttributedString` for the preview.
///
/// Attributed-string output rather than a SwiftUI view tree is what keeps large
/// documents fluid: the same TextKit 2 text view lays out both modes, so text
/// selection, Find and Writing Tools have a single implementation, and there is
/// no per-block SwiftUI layout cost.
struct PreviewRenderer: MarkupVisitor {
    typealias Result = NSAttributedString

    var face: Theme.BodyFace = .sans
    /// Width of the text column. Tables need it: their columns are sized to fit
    /// the content, and the budget they are fitted into is this.
    var measure: CGFloat = Theme.defaultMeasure
    private var listDepth = 0
    private var quoteDepth = 0

    static func render(
        _ markdown: String,
        face: Theme.BodyFace,
        measure: CGFloat = Theme.defaultMeasure
    ) -> NSAttributedString {
        var renderer = PreviewRenderer(face: face, measure: measure)
        let document = Document(parsing: markdown)
        return renderer.visit(document)
    }

    // MARK: Paragraph styles

    private func paragraphStyle(
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0,
        lineHeight: CGFloat = Theme.bodyLineHeightMultiple,
        indent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.lineHeightMultiple = lineHeight
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    private var blockIndent: CGFloat {
        CGFloat(listDepth) * 22 + CGFloat(quoteDepth) * Theme.quoteIndent
    }

    // MARK: Children

    private mutating func joinChildren(_ markup: Markup) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in markup.children {
            out.append(visit(child))
        }
        return out
    }

    /// Blocks separate themselves with a single newline; vertical rhythm comes
    /// from paragraph spacing, not from blank lines.
    private mutating func joinBlocks(_ markup: Markup) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for (index, child) in markup.children.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(visit(child))
        }
        return out
    }

    // MARK: Visitor

    mutating func defaultVisit(_ markup: Markup) -> NSAttributedString {
        joinChildren(markup)
    }

    mutating func visitDocument(_ document: Document) -> NSAttributedString {
        joinBlocks(document)
    }

    mutating func visitText(_ text: Markdown.Text) -> NSAttributedString {
        NSAttributedString(
            string: text.string,
            attributes: [
                .font: Theme.body(face, size: Theme.bodySize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> NSAttributedString {
        NSAttributedString(string: " ", attributes: [.font: Theme.body(face, size: Theme.bodySize)])
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> NSAttributedString {
        NSAttributedString(string: "\n", attributes: [.font: Theme.body(face, size: Theme.bodySize)])
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let out = joinChildren(paragraph)
        out.addAttribute(
            .paragraphStyle,
            value: paragraphStyle(spacingAfter: Theme.paragraphGap, indent: blockIndent),
            range: NSRange(location: 0, length: out.length)
        )
        return out
    }

    mutating func visitHeading(_ heading: Heading) -> NSAttributedString {
        let size = Theme.headingSizes[min(max(heading.level, 1), 6) - 1]
        let weight: NSFont.Weight = heading.level == 1 ? .bold : .semibold

        let out = joinChildren(heading)
        let full = NSRange(location: 0, length: out.length)
        out.addAttributes(
            [
                .font: Theme.body(face, size: size, weight: weight),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle(
                    spacingBefore: heading.level <= 2 ? 26 : 18,
                    spacingAfter: 8,
                    lineHeight: 1.14,
                    indent: blockIndent
                ),
                .kern: heading.level <= 2 ? -0.4 : 0,
            ],
            range: full
        )
        return out
    }

    mutating func visitStrong(_ strong: Strong) -> NSAttributedString {
        let out = joinChildren(strong)
        out.enumerateAttribute(.font, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? Theme.bodySize
            out.addAttribute(.font, value: Theme.body(face, size: size, weight: .semibold), range: range)
        }
        return out
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> NSAttributedString {
        let out = joinChildren(emphasis)
        out.enumerateAttribute(.font, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            let font = (value as? NSFont) ?? Theme.body(face, size: Theme.bodySize)
            let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            out.addAttribute(.font, value: italic, range: range)
        }
        return out
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> NSAttributedString {
        let out = joinChildren(strikethrough)
        out.addAttributes(
            [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
             .strikethroughColor: NSColor.tertiaryLabelColor],
            range: NSRange(location: 0, length: out.length)
        )
        return out
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> NSAttributedString {
        NSAttributedString(
            string: inlineCode.code,
            attributes: [
                .font: Theme.mono(Theme.bodySize - 1.5),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: Theme.codeBackground,
            ]
        )
    }

    mutating func visitLink(_ link: Markdown.Link) -> NSAttributedString {
        let out = joinChildren(link)
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: Theme.synLink,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: Theme.synLink.withAlphaComponent(0.4),
        ]
        if let destination = link.destination, let url = URL(string: destination) {
            attributes[.link] = url
        }
        out.addAttributes(attributes, range: NSRange(location: 0, length: out.length))
        return out
    }

    mutating func visitImage(_ image: Markdown.Image) -> NSAttributedString {
        // Images are not laid out inline yet. Showing the alt text keeps the
        // document readable instead of dropping content silently.
        let label = image.plainText.isEmpty ? (image.source ?? "image") : image.plainText
        return NSAttributedString(
            string: "[\(label)]",
            attributes: [
                .font: Theme.body(face, size: Theme.bodySize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        var code = codeBlock.code
        while code.hasSuffix("\n") { code.removeLast() }

        let indent = blockIndent + 16
        // Every newline inside the block is a paragraph break, so spacing has to
        // live on the first and last lines only - otherwise each line of code
        // gets its own gap.
        func style(first: Bool, last: Bool) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.16
            style.paragraphSpacingBefore = first ? Theme.codeBlockOuterGap : 0
            style.paragraphSpacing = last ? Theme.codeBlockOuterGap : 0
            style.firstLineHeadIndent = indent
            style.headIndent = indent
            style.tailIndent = -16
            return style
        }

        let lines = code.isEmpty ? [""] : code.components(separatedBy: "\n")
        let out = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(
                NSAttributedString(
                    string: line,
                    attributes: [
                        .font: Theme.mono(Theme.monoSize),
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: style(first: index == 0, last: index == lines.count - 1),
                    ]
                )
            )
        }

        // Drawn, not attributed.
        out.addAttribute(
            .blockFill,
            value: Theme.codeBackground,
            range: NSRange(location: 0, length: out.length)
        )
        return out
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        // Raw HTML is shown as source rather than interpreted. Round-tripping it
        // through a renderer is how HTML comments get eaten.
        NSAttributedString(
            string: html.rawHTML.trimmingCharacters(in: .newlines),
            attributes: [
                .font: Theme.mono(Theme.monoSize - 0.5),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraphStyle(spacingAfter: 12, indent: blockIndent),
            ]
        )
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> NSAttributedString {
        NSAttributedString(
            string: inlineHTML.rawHTML,
            attributes: [
                .font: Theme.mono(Theme.bodySize - 2),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        quoteDepth += 1
        let barX = CGFloat(quoteDepth - 1) * Theme.quoteIndent
        let out = joinBlocks(blockQuote)
        quoteDepth -= 1

        let full = NSRange(location: 0, length: out.length)
        out.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: full)

        // Only where a deeper quote has not already claimed the gutter, so a
        // nested quote keeps its own bar instead of the outer one erasing it.
        out.enumerateAttribute(.blockQuoteBar, in: full) { existing, range, _ in
            guard existing == nil else { return }
            out.addAttribute(.blockQuoteBar, value: NSNumber(value: Double(barX)), range: range)
        }
        return out
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 16
        style.paragraphSpacing = 16
        style.lineHeightMultiple = 1

        return NSAttributedString(
            string: " ",
            attributes: [
                .font: Theme.body(face, size: 2),
                .paragraphStyle: style,
                .blockRule: Theme.ruleColor,
            ]
        )
    }

    // MARK: Lists

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> NSAttributedString {
        listDepth += 1
        defer { listDepth -= 1 }

        let out = NSMutableAttributedString()
        for (index, child) in unorderedList.children.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            let marker = listDepth > 1 ? "\u{25E6}" : "\u{2022}"
            out.append(listRow(child, marker: marker))
        }
        return out
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> NSAttributedString {
        listDepth += 1
        defer { listDepth -= 1 }

        let start = Int(orderedList.startIndex)
        let out = NSMutableAttributedString()
        for (index, child) in orderedList.children.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(listRow(child, marker: "\(start + index)."))
        }
        return out
    }

    private mutating func listRow(_ child: Markup, marker: String) -> NSAttributedString {
        let out = NSMutableAttributedString()

        var bullet = marker
        var checkbox: Checkbox?
        if let item = child as? ListItem, let box = item.checkbox {
            checkbox = box
            bullet = box == .checked ? "\u{2611}" : "\u{2610}"
        }

        var bulletAttributes: [NSAttributedString.Key: Any] = [
            .font: Theme.body(face, size: Theme.bodySize),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        if let checkbox {
            // Checkboxes are interactive: bigger, higher contrast, and carrying a
            // link so a click can toggle them.
            bulletAttributes[.font] = Theme.body(face, size: Theme.bodySize + 2)
            bulletAttributes[.foregroundColor] = checkbox == .checked
                ? NSColor.controlAccentColor
                : NSColor.secondaryLabelColor
            if let line = child.range?.lowerBound.line {
                bulletAttributes[.taskToggleLine] = line
            }
        }

        out.append(NSAttributedString(string: bullet + "\t", attributes: bulletAttributes))
        out.append(visit(child))

        // Hanging indent so wrapped lines align with the text, not the bullet.
        let indent = blockIndent
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.bodyLineHeightMultiple
        style.paragraphSpacing = 4
        style.firstLineHeadIndent = indent
        style.headIndent = indent + 20
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 20)]

        // Apply the row style everywhere EXCEPT filled blocks. A fenced code
        // block inside a list item carries its own indent and its own first/last
        // line spacing, and the fill geometry is computed from that spacing -
        // overwriting it here is what made those blocks lose their background
        // entirely.
        applySkippingFilledBlocks(style, to: out)
        return out
    }

    mutating func visitListItem(_ listItem: ListItem) -> NSAttributedString {
        // The row's bullet and indent are applied by `listRow`; here we only
        // flatten the item's own blocks.
        let out = NSMutableAttributedString()
        for (index, child) in listItem.children.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(visit(child))
        }

        // A paragraph inside a list item should not add its own trailing gap -
        // but a filled block must keep its spacing, for the reason above, and a
        // NESTED ROW must keep its indent. Zeroing the indent here unconditionally
        // is what flattened sub-lists onto their parent's left edge: the nested
        // row had already set the deeper indent, and this ran afterwards and
        // erased it. Tab stops are the tell - only a row or a table sets them.
        let full = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.blockFill, in: full) { fill, fillRange, _ in
            guard fill == nil else { return }
            out.enumerateAttribute(.paragraphStyle, in: fillRange) { value, range, _ in
                guard let existing = value as? NSParagraphStyle,
                      existing.tabStops.isEmpty,
                      let mutable = existing.mutableCopy() as? NSMutableParagraphStyle else { return }
                mutable.paragraphSpacing = 0
                mutable.firstLineHeadIndent = 0
                mutable.headIndent = 0
                out.addAttribute(.paragraphStyle, value: mutable, range: range)
            }
        }
        return out
    }

    /// Sets `style` on every part of `text` that is not inside a painted block
    /// and has not already been indented further by a deeper level.
    ///
    /// The second condition is what lets sub-lists nest. A parent row applies its
    /// style to everything it contains, and everything it contains includes any
    /// list nested inside it - so without this the sub-list is dragged back out
    /// to the parent's indent and the nesting becomes invisible.
    private func applySkippingFilledBlocks(_ style: NSParagraphStyle, to text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.blockFill, in: full) { fill, range, _ in
            guard fill == nil else { return }
            text.enumerateAttribute(.paragraphStyle, in: range) { value, inner, _ in
                if let existing = value as? NSParagraphStyle, existing.headIndent > style.headIndent {
                    return
                }
                text.addAttribute(.paragraphStyle, value: style, range: inner)
            }
        }
    }

    // MARK: Tables

    /// Gap between the end of one column's text and the start of the next.
    private static let tableGutter: CGFloat = 20
    /// A column narrower than this is unreadable, so compression stops here even
    /// if that means the table is wider than the text column.
    private static let tableMinColumn: CGFloat = 64

    /// Lays the table out on tab stops sized to the content.
    ///
    /// The previous version put every stop at a fixed 150pt. That is wrong in
    /// both directions at once: a cell longer than 150pt runs straight through
    /// its stop and shoves the rest of the row one column right - which is how a
    /// table turns into a paragraph of run-together words - while a column of
    /// short cells leaves a 100pt hole. Measuring first costs one pass and makes
    /// both failures impossible.
    mutating func visitTable(_ table: Markdown.Table) -> NSAttributedString {
        let columns = max(table.maxColumnCount, 1)

        let head = cellsOfRow(table.head, columns: columns)
        for cell in head {
            let full = NSRange(location: 0, length: cell.length)
            cell.enumerateAttribute(.font, in: full) { value, range, _ in
                let size = (value as? NSFont)?.pointSize ?? Theme.bodySize
                cell.addAttribute(.font, value: Theme.body(face, size: size, weight: .semibold), range: range)
            }
        }

        var body: [[NSMutableAttributedString]] = []
        for row in table.body.children {
            body.append(cellsOfRow(row, columns: columns))
        }

        let widths = columnWidths(head: head, body: body, columns: columns)

        // Anything that still does not fit gets an ellipsis rather than being
        // allowed to run into its neighbour.
        for index in 0..<columns {
            let limit = widths[index] - Self.tableGutter
            truncate(head[index], to: limit)
            for row in 0..<body.count { truncate(body[row][index], to: limit) }
        }

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 2
        style.lineHeightMultiple = 1.24
        style.firstLineHeadIndent = blockIndent
        style.headIndent = blockIndent
        var x = blockIndent
        style.tabStops = widths.dropLast().map { width in
            x += width
            return NSTextTab(textAlignment: .left, location: x)
        }

        let out = NSMutableAttributedString()
        out.append(joinWithTabs(head))
        for row in body {
            out.append(NSAttributedString(string: "\n"))
            out.append(joinWithTabs(row))
        }
        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return out
    }

    /// Natural width per column, compressed to the text column when the sum of
    /// the natural widths overflows it.
    ///
    /// Compression is proportional-with-a-floor rather than a flat scale:
    /// columns that already fit inside an even share keep their exact width, and
    /// only the greedy ones give space back. A column of one-digit counts should
    /// not shrink because the column of prose beside it is long.
    private func columnWidths(
        head: [NSMutableAttributedString],
        body: [[NSMutableAttributedString]],
        columns: Int
    ) -> [CGFloat] {
        var natural = [CGFloat](repeating: 0, count: columns)
        for index in 0..<columns {
            natural[index] = ceil(head[index].size().width)
            for row in body {
                natural[index] = max(natural[index], ceil(row[index].size().width))
            }
            natural[index] += Self.tableGutter
        }

        let budget = max(measure - blockIndent, Self.tableMinColumn * CGFloat(columns))
        guard natural.reduce(0, +) > budget else { return natural }

        var result = natural
        var flexible = Set(0..<columns)
        var remaining = budget

        while !flexible.isEmpty {
            let share = remaining / CGFloat(flexible.count)
            let settled = flexible.filter { natural[$0] <= share }
            guard !settled.isEmpty else {
                for index in flexible { result[index] = max(share, Self.tableMinColumn) }
                break
            }
            for index in settled {
                result[index] = natural[index]
                remaining -= natural[index]
                flexible.remove(index)
            }
        }
        return result
    }

    /// Clips `cell` to `limit` points, ending it with an ellipsis.
    private func truncate(_ cell: NSMutableAttributedString, to limit: CGFloat) {
        guard limit > 0, cell.length > 0, cell.size().width > limit else { return }
        while cell.length > 1 {
            cell.deleteCharacters(in: NSRange(location: cell.length - 1, length: 1))
            let probe = NSMutableAttributedString(attributedString: cell)
            probe.append(NSAttributedString(
                string: "\u{2026}",
                attributes: cell.attributes(at: probe.length - 1, effectiveRange: nil)
            ))
            if probe.size().width <= limit {
                cell.setAttributedString(probe)
                return
            }
        }
    }

    private mutating func cellsOfRow(_ container: Markup, columns: Int) -> [NSMutableAttributedString] {
        var out: [NSMutableAttributedString] = []
        for cell in container.children {
            let rendered = NSMutableAttributedString()
            rendered.append(visit(cell))
            out.append(rendered)
        }
        // Ragged rows are legal markdown; pad so every row has the same stops.
        while out.count < columns { out.append(NSMutableAttributedString()) }
        return Array(out.prefix(columns))
    }

    private func joinWithTabs(_ cells: [NSMutableAttributedString]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, cell) in cells.enumerated() {
            if index > 0 {
                out.append(NSAttributedString(
                    string: "\t",
                    attributes: [.font: Theme.body(face, size: Theme.bodySize)]
                ))
            }
            out.append(cell)
        }
        return out
    }

    mutating func visitTableCell(_ cell: Markdown.Table.Cell) -> NSAttributedString {
        joinChildren(cell)
    }
}
