import AppKit
import Markdown

extension NSAttributedString.Key {
    /// Range should be painted as one solid rectangle spanning the text column.
    /// `.backgroundColor` cannot do this: it fills each glyph run, so blank and
    /// short lines leave a staircase.
    static let blockFill = NSAttributedString.Key("mdBlockFill")
    /// Range should be painted as a horizontal rule across the text column.
    static let blockRule = NSAttributedString.Key("mdBlockRule")
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
    private var listDepth = 0
    private var quoteDepth = 0

    static func render(_ markdown: String, face: Theme.BodyFace) -> NSAttributedString {
        var renderer = PreviewRenderer(face: face)
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
        CGFloat(listDepth) * 22 + CGFloat(quoteDepth) * 18
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
            value: paragraphStyle(spacingAfter: 12, indent: blockIndent),
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
        let out = joinBlocks(blockQuote)
        quoteDepth -= 1

        out.addAttributes(
            [.foregroundColor: NSColor.secondaryLabelColor],
            range: NSRange(location: 0, length: out.length)
        )
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
        // but a filled block must keep its spacing, for the reason above.
        let full = NSRange(location: 0, length: out.length)
        out.enumerateAttribute(.blockFill, in: full) { fill, fillRange, _ in
            guard fill == nil else { return }
            out.enumerateAttribute(.paragraphStyle, in: fillRange) { value, range, _ in
                guard let existing = value as? NSParagraphStyle,
                      let mutable = existing.mutableCopy() as? NSMutableParagraphStyle else { return }
                mutable.paragraphSpacing = 0
                mutable.firstLineHeadIndent = 0
                mutable.headIndent = 0
                out.addAttribute(.paragraphStyle, value: mutable, range: range)
            }
        }
        return out
    }

    /// Sets `style` on every part of `text` that is not inside a painted block.
    private func applySkippingFilledBlocks(_ style: NSParagraphStyle, to text: NSMutableAttributedString) {
        let full = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.blockFill, in: full) { fill, range, _ in
            guard fill == nil else { return }
            text.addAttribute(.paragraphStyle, value: style, range: range)
        }
    }

    // MARK: Tables

    mutating func visitTable(_ table: Markdown.Table) -> NSAttributedString {
        let columns = max(table.maxColumnCount, 1)
        let columnWidth: CGFloat = 150

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 12
        style.paragraphSpacing = 2
        style.lineHeightMultiple = 1.24
        style.tabStops = (1...columns).map {
            NSTextTab(textAlignment: .left, location: CGFloat($0) * columnWidth)
        }
        style.firstLineHeadIndent = blockIndent
        style.headIndent = blockIndent

        let out = NSMutableAttributedString()
        out.append(visit(table.head))
        out.append(NSAttributedString(string: "\n"))
        out.append(visit(table.body))

        out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: out.length))
        return out
    }

    mutating func visitTableHead(_ head: Markdown.Table.Head) -> NSAttributedString {
        let out = rowOfCells(head)
        out.enumerateAttribute(.font, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            let size = (value as? NSFont)?.pointSize ?? Theme.bodySize
            out.addAttribute(.font, value: Theme.body(face, size: size, weight: .semibold), range: range)
        }
        return out
    }

    mutating func visitTableBody(_ body: Markdown.Table.Body) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (index, row) in body.children.enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(visit(row))
        }
        return out
    }

    mutating func visitTableRow(_ row: Markdown.Table.Row) -> NSAttributedString {
        rowOfCells(row)
    }

    private mutating func rowOfCells(_ container: Markup) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for (index, cell) in container.children.enumerated() {
            if index > 0 {
                out.append(NSAttributedString(string: "\t", attributes: [.font: Theme.body(face, size: Theme.bodySize)]))
            }
            out.append(visit(cell))
        }
        return out
    }

    mutating func visitTableCell(_ cell: Markdown.Table.Cell) -> NSAttributedString {
        joinChildren(cell)
    }
}
