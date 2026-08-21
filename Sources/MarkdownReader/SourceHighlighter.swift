import AppKit

/// Syntax colouring for the editor's raw markdown.
///
/// Deliberately line-oriented. Markdown's block syntax is decided per line, so
/// an edit only invalidates the lines it touched - which is what lets the editor
/// re-colour incrementally instead of re-attributing the whole document on every
/// keystroke. That distinction is the difference between fluid and sluggish on a
/// long file; the language it is written in is not.
enum SourceHighlighter {

    // Compiled once. Building these per keystroke would defeat the point.
    private static let heading = regex(#"^(#{1,6})[ \t]+(.*)$"#)
    private static let fence = regex(#"^[ \t]*(```|~~~)(.*)$"#)
    private static let bullet = regex(#"^([ \t]*)([-*+])([ \t]+)"#)
    private static let ordered = regex(#"^([ \t]*)(\d{1,9}[.)])([ \t]+)"#)
    private static let quote = regex(#"^[ \t]*(>+)"#)
    private static let rule = regex(#"^[ \t]*((-[ \t]*){3,}|(\*[ \t]*){3,}|(_[ \t]*){3,})$"#)
    private static let task = regex(#"^[ \t]*[-*+][ \t]+(\[[ xX]\])"#)
    private static let strong = regex(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let emphasis = regex(#"(?<![*_\w])([*_])(?=\S)([^*_]+?)(?<=\S)\1(?![*_\w])"#)
    private static let inlineCode = regex(#"(`+)([^`]+?)\1"#)
    private static let link = regex(#"(!?\[)([^\]]*)(\]\()([^)\s]+)(\))"#)
    private static let bareURL = regex(#"<(https?://[^>\s]+)>"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals verified at build time; a failure here is a bug,
        // not a runtime condition.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    // MARK: Base attributes

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Theme.sourceLineHeightMultiple
        return [
            .font: Theme.mono(Theme.sourceSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
    }

    // MARK: Full pass

    static func highlight(_ text: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: text, attributes: baseAttributes())
        apply(to: output, in: NSRange(location: 0, length: output.length), fullText: text)
        return output
    }

    // MARK: Incremental pass

    /// Re-colour only `range`, expanded to whole lines. `storage` must already
    /// contain the current text.
    static func rehighlight(_ storage: NSTextStorage, editedRange: NSRange) {
        let text = storage.string as NSString
        let lineRange = text.lineRange(for: editedRange)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: lineRange)
        apply(to: storage, in: lineRange, fullText: storage.string)
        storage.endEditing()
    }

    /// Whether the character at `location` sits inside a fenced code block.
    /// Counts fence markers from the top; cheap string scanning, no attribute work.
    private static func insideFence(_ text: String, before location: Int) -> Bool {
        let ns = text as NSString
        var open = false
        var cursor = 0
        while cursor < location {
            let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
            if line.location >= location { break }
            let content = ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.hasPrefix("```") || content.hasPrefix("~~~") {
                open.toggle()
            }
            guard line.length > 0 else { break }
            cursor = line.location + line.length
        }
        return open
    }

    // MARK: Rules

    private static func apply(to storage: NSMutableAttributedString, in range: NSRange, fullText: String) {
        let ns = storage.string as NSString
        var fenced = insideFence(fullText, before: range.location)

        // Walk the affected lines one at a time.
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end {
            let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let line = ns.substring(with: lineRange)
            let lineNS = line as NSString
            let localRange = NSRange(location: 0, length: lineNS.length)

            let isFenceMarker = fence.firstMatch(in: line, range: localRange) != nil

            if isFenceMarker {
                storage.addAttribute(.foregroundColor, value: Theme.synCode, range: lineRange)
                fenced.toggle()
            } else if fenced {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
            } else {
                colourBlockSyntax(line, lineRange: lineRange, localRange: localRange, into: storage)
                colourInlineSyntax(line, lineRange: lineRange, localRange: localRange, into: storage)
            }

            guard lineRange.length > 0 else { break }
            cursor = lineRange.location + lineRange.length
        }
    }

    private static func colourBlockSyntax(
        _ line: String,
        lineRange: NSRange,
        localRange: NSRange,
        into storage: NSMutableAttributedString
    ) {
        func absolute(_ r: NSRange) -> NSRange {
            NSRange(location: lineRange.location + r.location, length: r.length)
        }

        if let match = heading.firstMatch(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synHeading, range: absolute(match.range(at: 1)))
            let body = absolute(match.range(at: 2))
            storage.addAttributes(
                [.font: Theme.mono(Theme.sourceSize, weight: .semibold), .foregroundColor: NSColor.labelColor],
                range: body
            )
            return
        }

        if rule.firstMatch(in: line, range: localRange) != nil {
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: lineRange)
            return
        }

        if let match = quote.firstMatch(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synList, range: absolute(match.range(at: 1)))
            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: lineRange)
            storage.addAttribute(.foregroundColor, value: Theme.synList, range: absolute(match.range(at: 1)))
            return
        }

        if let match = task.firstMatch(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synCode, range: absolute(match.range(at: 1)))
        }

        if let match = bullet.firstMatch(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synList, range: absolute(match.range(at: 2)))
        } else if let match = ordered.firstMatch(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synList, range: absolute(match.range(at: 2)))
        }
    }

    private static func colourInlineSyntax(
        _ line: String,
        lineRange: NSRange,
        localRange: NSRange,
        into storage: NSMutableAttributedString
    ) {
        func absolute(_ r: NSRange) -> NSRange {
            NSRange(location: lineRange.location + r.location, length: r.length)
        }

        for match in inlineCode.matches(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synCode, range: absolute(match.range))
        }

        for match in strong.matches(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synEmphasis, range: absolute(match.range(at: 1)))
            storage.addAttributes(
                [.font: Theme.mono(Theme.sourceSize, weight: .semibold)],
                range: absolute(match.range(at: 2))
            )
        }

        for match in emphasis.matches(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synEmphasis, range: absolute(match.range(at: 1)))
        }

        for match in link.matches(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synFunction, range: absolute(match.range(at: 2)))
            storage.addAttribute(.foregroundColor, value: Theme.synLink, range: absolute(match.range(at: 4)))
        }

        for match in bareURL.matches(in: line, range: localRange) {
            storage.addAttribute(.foregroundColor, value: Theme.synLink, range: absolute(match.range(at: 1)))
        }
    }
}

private extension NSRegularExpression {
    func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: string, options: [], range: range)
    }

    func firstMatch(in string: String, range: NSRange) -> NSTextCheckingResult? {
        firstMatch(in: string, options: [], range: range)
    }
}
