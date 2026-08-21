import AppKit
import SwiftUI

/// The single text engine behind both modes.
///
/// Preview and Editor are not two views. They are one TextKit 2 `NSTextView`
/// with a different attributed string installed, which is what makes the toggle
/// cheap, keeps one implementation of selection / Find / Writing Tools, and lets
/// scroll position carry across the switch.
struct MarkdownTextPane: NSViewRepresentable {
    let mode: ViewMode
    /// Rendered preview attributes, or highlighted source, depending on `mode`.
    let content: NSAttributedString
    let measure: CGFloat
    /// Identifies which document/mode the content belongs to, so the coordinator
    /// can tell a genuine content swap from a redraw.
    let contentToken: String
    let onEdit: (String) -> Void
    /// A task-list checkbox was clicked; the argument is its 1-based source line.
    let onToggleTask: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onToggleTask: onToggleTask)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MeasuredTextView(usingTextLayoutManager: true)
        textView.disableDefaultLinkChrome()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.measure = measure

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.install(content, mode: mode, token: contentToken)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MeasuredTextView else { return }
        context.coordinator.onEdit = onEdit
        context.coordinator.onToggleTask = onToggleTask

        if textView.measure != measure {
            textView.measure = measure
            textView.needsLayout = true
        }
        context.coordinator.install(content, mode: mode, token: contentToken)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onEdit: (String) -> Void
        var onToggleTask: (Int) -> Void
        weak var textView: MeasuredTextView?

        private var installedToken: String?
        /// Guards against the delegate callback re-entering during a programmatic swap.
        private var isInstalling = false
        /// Set right before `onEdit` fires from `textDidChange`. The edit already
        /// lives, correctly highlighted, in the live text storage; the SwiftUI
        /// re-render it triggers hands that same content straight back down as
        /// `content`. Without this flag `install()` cannot tell that apart from a
        /// genuine external change, replaces the storage wholesale on every
        /// keystroke, and the caret gets discarded in the process - which is the
        /// "cursor jumps to the end" bug. Only consumed while still in Editor
        /// mode: a mode switch that lands in the same render must still reinstall.
        private var pendingLocalEdit = false

        init(onEdit: @escaping (String) -> Void, onToggleTask: @escaping (Int) -> Void = { _ in }) {
            self.onEdit = onEdit
            self.onToggleTask = onToggleTask
        }

        /// Swap in a new attributed string, preserving the reader's place.
        func install(_ content: NSAttributedString, mode: ViewMode, token: String) {
            guard let textView else { return }

            if pendingLocalEdit {
                pendingLocalEdit = false
                if mode == .editor {
                    // Storage already matches; touching it would only cost us the
                    // caret position the user just typed their way into.
                    installedToken = token
                    return
                }
            }

            guard installedToken != token else { return }

            let fraction = scrollFraction(of: textView)

            isInstalling = true
            textView.textStorage?.setAttributedString(content)
            textView.isEditable = (mode == .editor)
            textView.isSelectable = true
            isInstalling = false

            installedToken = token
            textView.needsDisplay = true

            // The two representations differ in length, so an absolute offset is
            // meaningless across the switch. Proportional restore keeps you in
            // roughly the same part of the document; a source-line map would make
            // it exact and is the natural next step.
            restore(fraction: fraction, in: textView)
        }

        private func scrollFraction(of textView: NSTextView) -> CGFloat {
            guard let clip = textView.enclosingScrollView?.contentView else { return 0 }
            guard textView.bounds.height > clip.bounds.height else { return 0 }
            let travel = max(textView.bounds.height - clip.bounds.height, 1)
            return max(0, min(1, clip.bounds.origin.y / travel))
        }

        private func restore(fraction: CGFloat, in textView: NSTextView) {
            guard fraction > 0, let scrollView = textView.enclosingScrollView else { return }
            DispatchQueue.main.async {
                let clip = scrollView.contentView
                let travel = max(textView.bounds.height - clip.bounds.height, 0)
                guard travel > 0 else { return }
                clip.scroll(to: NSPoint(x: 0, y: travel * fraction))
                scrollView.reflectScrolledClipView(clip)
            }
        }

        // MARK: NSTextViewDelegate

        /// Intercepts our private checkbox scheme; everything else (real links in
        /// the document) falls through to the default handler, which opens it.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL? = switch link {
            case let url as URL: url
            case let string as String: URL(string: string)
            default: nil
            }
            guard let url, let line = TaskToggleLink.line(from: url) else { return false }
            onToggleTask(line)
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isInstalling, let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage else { return }

            // Re-colour only the lines the edit touched. This is the whole reason
            // the highlighter is line-oriented.
            let caret = textView.selectedRange()
            SourceHighlighter.rehighlight(
                storage,
                editedRange: NSRange(location: max(0, caret.location - 1), length: 0)
            )

            // The next `install()` call will just be this same edit reflected
            // back down through SwiftUI - see `pendingLocalEdit`.
            pendingLocalEdit = true
            onEdit(storage.string)
        }
    }
}

// MARK: - Text view

/// Keeps the text column at `measure` points wide and centred, and paints the
/// block decorations that attributed strings cannot express.
final class MeasuredTextView: NSTextView {
    var measure: CGFloat = Theme.defaultMeasure {
        didSet { if measure != oldValue { needsLayout = true } }
    }

    /// `NSTextView.linkTextAttributes` has a system default (blue + underline)
    /// that overrides whatever color/underline a run already carries - which is
    /// what made task-checkbox links (styled explicitly, on purpose, to look
    /// like checkboxes rather than links) render with a blue underline anyway.
    /// Clearing it puts styling back in the renderer's hands: real markdown
    /// links keep their look because `PreviewRenderer.visitLink` sets color and
    /// underline explicitly on those runs.
    ///
    /// `NSTextView(usingTextLayoutManager:)` is a convenience initializer that
    /// cannot be overridden, so this is applied at each construction site
    /// instead of in an initializer.
    func disableDefaultLinkChrome() {
        linkTextAttributes = [:]
    }

    override func layout() {
        let available = bounds.width
        let column = min(measure, max(available - Theme.textInset.width * 2, 200))
        let side = max((available - column) / 2, Theme.textInset.width)

        if abs(textContainerInset.width - side) > 0.5 || textContainerInset.height != Theme.textInset.height {
            textContainerInset = NSSize(width: side, height: Theme.textInset.height)
        }
        textContainer?.containerSize = NSSize(width: column, height: .greatestFiniteMagnitude)
        super.layout()
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawBlockDecorations(clip: rect)
    }

    /// Paints code-block grounds and horizontal rules.
    ///
    /// Both need to span the text column regardless of how long the text on each
    /// line is, which is precisely what a glyph-run attribute cannot do.
    private func drawBlockDecorations(clip: NSRect) {
        guard let storage = textStorage, storage.length > 0,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let container = textContainer
        else { return }

        let full = NSRange(location: 0, length: storage.length)
        var fills: [(NSRange, NSColor)] = []
        var rules: [(NSRange, NSColor)] = []

        storage.enumerateAttribute(.blockFill, in: full) { value, range, _ in
            if let color = value as? NSColor { fills.append((range, color)) }
        }
        storage.enumerateAttribute(.blockRule, in: full) { value, range, _ in
            if let color = value as? NSColor { rules.append((range, color)) }
        }
        guard !fills.isEmpty || !rules.isEmpty else { return }

        let originX = textContainerInset.width
        let originY = textContainerInset.height
        let width = container.size.width

        // One pass over the laid-out fragments, accumulating the union rect of
        // each decorated range.
        var fillRects = [CGRect?](repeating: nil, count: fills.count)
        var ruleRects = [CGRect?](repeating: nil, count: rules.count)

        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + originY > clip.maxY { return false }
            if frame.maxY + originY < clip.minY { return true }

            let start = contentManager.offset(
                from: layoutManager.documentRange.location,
                to: fragment.rangeInElement.location
            )
            let end = contentManager.offset(
                from: layoutManager.documentRange.location,
                to: fragment.rangeInElement.endLocation
            )
            let fragmentRange = NSRange(location: start, length: max(end - start, 0))

            for (index, entry) in fills.enumerated() where NSIntersectionRange(entry.0, fragmentRange).length > 0 {
                fillRects[index] = fillRects[index].map { $0.union(frame) } ?? frame
            }
            for (index, entry) in rules.enumerated() where NSIntersectionRange(entry.0, fragmentRange).length > 0 {
                ruleRects[index] = ruleRects[index].map { $0.union(frame) } ?? frame
            }
            return true
        }

        // The block's first and last lines carry `codeBlockOuterGap` as paragraph
        // spacing, and that spacing is part of their fragment frames. Trim it back
        // off so the visible padding is `codeBlockInnerPadding`, not the sum.
        let trim = Theme.codeBlockOuterGap - Theme.codeBlockInnerPadding

        for (index, entry) in fills.enumerated() {
            guard let box = fillRects[index] else { continue }
            let top = box.minY + trim
            let bottom = box.maxY - trim
            guard bottom > top else { continue }
            let rect = CGRect(
                x: originX,
                y: top + originY,
                width: width,
                height: bottom - top
            )
            entry.1.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }

        for (index, entry) in rules.enumerated() {
            guard let box = ruleRects[index] else { continue }
            let rect = CGRect(
                x: originX,
                y: (box.midY + originY).rounded(),
                width: width,
                height: 1
            )
            entry.1.setFill()
            rect.fill()
        }
    }
}
