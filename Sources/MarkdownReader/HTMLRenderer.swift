import Foundation
import Markdown

/// Turns a parsed markdown tree into the HTML the preview web view shows.
///
/// HTML rather than an attributed string because block styling (code grounds,
/// checkboxes, table rules, link affordances) is a box-model problem, and
/// WebKit has a box model. Every block carries `data-line`, the 1-based source
/// line it starts on: that is the coordinate the reader uses to keep its place
/// across mode switches, outline jumps and relaunches.
///
/// Nothing from the document reaches the page unescaped. Raw HTML in the
/// source is shown as source, matching the editor, and link targets are
/// limited to schemes the app knows how to open.
struct HTMLRenderer: MarkupVisitor {
    typealias Result = String

    var baseURL: URL? = nil

    static func render(_ markdown: String, baseURL: URL? = nil) -> String {
        var renderer = HTMLRenderer(baseURL: baseURL)
        return renderer.visit(Document(parsing: markdown))
    }

    static let allowedLinkSchemes: Set<String> = ["http", "https", "file", "mailto"]

    /// Resolves a link destination the way the reader always has: fragments
    /// against the document itself, everything else against its folder.
    static func resolve(_ destination: String, baseURL: URL?) -> URL? {
        let base = destination.hasPrefix("#") ? baseURL : baseURL?.deletingLastPathComponent().appendingPathComponent("")
        guard let url = URL(string: destination, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), allowedLinkSchemes.contains(scheme) else { return nil }
        return url
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: Helpers

    private func line(_ markup: Markup) -> String {
        guard let line = markup.range?.lowerBound.line else { return "" }
        return " data-line=\"\(line)\""
    }

    private mutating func children(_ markup: Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    mutating func defaultVisit(_ markup: Markup) -> String { children(markup) }

    // MARK: Blocks

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p\(line(paragraph))>\(children(paragraph))</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        let slug = Self.escape(DocumentStructure.slug(heading.plainText))
        return "<h\(level) id=\"\(slug)\"\(line(heading))>\(children(heading))</h\(level)>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote\(line(blockQuote))>\n\(children(blockQuote))</blockquote>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        var code = codeBlock.code
        while code.hasSuffix("\n") { code.removeLast() }
        let language = codeBlock.language?.trimmingCharacters(in: .whitespaces) ?? ""
        let languageAttribute = language.isEmpty ? "" : " class=\"language-\(Self.escape(language))\""
        return "<div class=\"code\"\(line(codeBlock))><button class=\"copy\" type=\"button\" aria-label=\"Copy code\">Copy</button>"
            + "<pre><code\(languageAttribute)>\(Self.escape(code))</code></pre></div>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        "<pre class=\"raw\"\(line(html))>\(Self.escape(html.rawHTML.trimmingCharacters(in: .newlines)))</pre>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr\(line(thematicBreak))>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        let hasTasks = unorderedList.children.contains { ($0 as? ListItem)?.checkbox != nil }
        return "<ul\(hasTasks ? " class=\"tasks\"" : "")\(line(unorderedList))>\n\(children(unorderedList))</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        let start = orderedList.startIndex
        return "<ol\(start == 1 ? "" : " start=\"\(start)\"")\(line(orderedList))>\n\(children(orderedList))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        guard let checkbox = listItem.checkbox else {
            return "<li\(line(listItem))>\(children(listItem))</li>\n"
        }
        let checked = checkbox == .checked
        let sourceLine = listItem.range?.lowerBound.line ?? 0
        return "<li class=\"task\" data-checked=\"\(checked)\"\(line(listItem))>"
            + "<input type=\"checkbox\" data-line=\"\(sourceLine)\" aria-label=\"Toggle task\"\(checked ? " checked" : "")>"
            + "<div class=\"task-body\">\(children(listItem))</div></li>\n"
    }

    mutating func visitTable(_ table: Markdown.Table) -> String {
        let alignments = table.columnAlignments
        func style(_ column: Int) -> String {
            guard column < alignments.count, let alignment = alignments[column] else { return "" }
            switch alignment {
            case .left: return " style=\"text-align:left\""
            case .center: return " style=\"text-align:center\""
            case .right: return " style=\"text-align:right\""
            }
        }
        func row(_ cells: MarkupChildren, tag: String) -> String {
            var out = "<tr>"
            for (column, cell) in cells.enumerated() {
                guard let cell = cell as? Markdown.Table.Cell, cell.colspan > 0, cell.rowspan > 0 else { continue }
                let span = (cell.colspan > 1 ? " colspan=\"\(cell.colspan)\"" : "") + (cell.rowspan > 1 ? " rowspan=\"\(cell.rowspan)\"" : "")
                out += "<\(tag)\(span)\(style(column))>\(children(cell))</\(tag)>"
            }
            return out + "</tr>\n"
        }
        var out = "<div class=\"table-wrap\"\(line(table))><table>\n<thead>\(row(table.head.children, tag: "th"))</thead>\n"
        let body = table.body.children.map { $0 }
        if !body.isEmpty {
            out += "<tbody>\n"
            for case let bodyRow as Markdown.Table.Row in body { out += row(bodyRow.children, tag: "td") }
            out += "</tbody>\n"
        }
        return out + "</table></div>\n"
    }

    // MARK: Inlines

    mutating func visitText(_ text: Markdown.Text) -> String { Self.escape(text.string) }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }
    mutating func visitEmphasis(_ emphasis: Emphasis) -> String { "<em>\(children(emphasis))</em>" }
    mutating func visitStrong(_ strong: Strong) -> String { "<strong>\(children(strong))</strong>" }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String { "<s>\(children(strikethrough))</s>" }
    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String { "<code>\(Self.escape(inlineCode.code))</code>" }
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String { "<span class=\"raw\">\(Self.escape(inlineHTML.rawHTML))</span>" }
    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String { "<code>\(Self.escape(symbolLink.destination ?? ""))</code>" }

    mutating func visitLink(_ link: Markdown.Link) -> String {
        let inner = children(link)
        guard let destination = link.destination, let url = Self.resolve(destination, baseURL: baseURL) else { return inner }
        let title = link.title.map { " title=\"\(Self.escape($0))\"" } ?? ""
        return "<a href=\"\(Self.escape(url.absoluteString))\"\(title)>\(inner)</a>"
    }

    mutating func visitImage(_ image: Markdown.Image) -> String {
        let label = image.plainText.isEmpty ? "Image" : image.plainText
        guard let source = image.source, let src = PreviewImages.source(for: source, baseURL: baseURL) else {
            return "<span class=\"img-missing\">Image unavailable: \(Self.escape(label))</span>"
        }
        let title = image.title.map { " title=\"\(Self.escape($0))\"" } ?? ""
        return "<img src=\"\(Self.escape(src))\" alt=\"\(Self.escape(label))\"\(title)>"
    }
}
