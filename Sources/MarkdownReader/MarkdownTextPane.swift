import AppKit
import SwiftUI

/// The source editor: a TextKit 2 `NSTextView` showing highlighted markdown.
///
/// Preview lives in `PreviewWebPane`. The two share source lines as their
/// coordinate, so the place you were reading is the place you start editing.
struct MarkdownTextPane: NSViewRepresentable {
    let mode: ViewMode
    /// Highlighted source.
    let content: () -> NSAttributedString
    let measure: CGFloat
    /// Identifies which document/mode the content belongs to, so the coordinator
    /// can tell a genuine content swap from a redraw.
    let contentToken: String
    let onEdit: (String) -> Void
    /// Distance scrolled from the top, in points. The toolbar's material is
    /// keyed off this: transparent at rest, glass once text is about to slide
    /// under it.
    var onScroll: (CGFloat) -> Void = { _ in }

    var contentStyleToken = ""
    var documentKey = ""
    var source = ""
    var navigation: ReaderNavigation? = nil
    var textScale: Double = 1
    var onFeedback: (String) -> Void = { _ in }
    var history: UndoManager? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MeasuredTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = false
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
        context.coordinator.onScroll = onScroll
        context.coordinator.observeScrolling(of: scrollView)
        configure(context.coordinator)
        context.coordinator.install(content, mode: mode, token: contentToken)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MeasuredTextView else { return }
        context.coordinator.onEdit = onEdit
        context.coordinator.onScroll = onScroll

        if textView.measure != measure {
            textView.measure = measure
            textView.needsLayout = true
        }
        configure(context.coordinator)
        context.coordinator.install(content, mode: mode, token: contentToken)
    }

    /// The pane is going away (a mode switch): write the reading position now
    /// rather than waiting for the debounce, so the preview picks it up.
    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.rememberPosition()
    }

    private func configure(_ coordinator: Coordinator) {
        coordinator.textView?.history = history
        coordinator.incomingStyle = contentStyleToken
        coordinator.incomingKey = documentKey
        coordinator.incomingSource = source
        coordinator.textScale = textScale
        coordinator.onFeedback = onFeedback
        if let navigation { coordinator.navigation = navigation }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onEdit: (String) -> Void
        var onScroll: (CGFloat) -> Void = { _ in }
        weak var textView: MeasuredTextView?
        var incomingStyle = ""
        private var installedStyle = ""
        private var installedSource = ""
        var incomingKey = ""
        var incomingSource = ""
        var textScale: Double = 1
        var onFeedback: (String) -> Void = { _ in }
        /// A jump requested before this pane existed belongs to the pane that
        /// was showing then; only later requests are acted on.
        var navigation: ReaderNavigation? {
            didSet { if oldValue == nil, let navigation { lastJump = navigation.jumpID; lastFind = navigation.findID } }
        }
        private var activeKey = ""
        private var lastJump: UUID?
        private var lastFind: UUID?
        private var restoring = false
        private var positionSaveTask: Task<Void, Never>?

        private func line(at index: Int) -> Int {
            guard let textView else { return 1 }
            let prefix = (textView.string as NSString).substring(to: min(max(0, index), (textView.string as NSString).length))
            return prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        }
        private func visibleLine() -> Int {
            guard let view = textView, let clip = view.enclosingScrollView?.contentView else { return 1 }
            return line(at: view.characterIndexForInsertion(at: NSPoint(x: view.textContainerInset.width + 2, y: clip.bounds.minY + 8)))
        }
        func rememberPosition() {
            guard !restoring, !activeKey.isEmpty else { return }
            var positions = UserDefaults.standard.dictionary(forKey: "readingLines") as? [String: Int] ?? [:]
            let line = visibleLine()
            guard positions[activeKey] != line else { return }
            positions[activeKey] = line
            UserDefaults.standard.set(positions, forKey: "readingLines")
        }
        private func index(for line: Int) -> Int {
            guard let view = textView else { return 0 }
            var offset = 0
            for (n, part) in view.string.components(separatedBy: "\n").enumerated() {
                if n + 1 >= line { return offset }
                offset += (part as NSString).length + 1
            }
            return (view.string as NSString).length
        }
        func go(to line: Int, caret: Bool) {
            guard let view = textView else { return }
            let location = index(for: line)
            let range = NSRange(location: location, length: 0)
            view.layoutSubtreeIfNeeded()
            view.scrollRangeToVisible(range)
            if caret { view.setSelectedRange(range) }
            guard let clip = view.enclosingScrollView?.contentView,
                  let manager = view.textLayoutManager,
                  let contentManager = manager.textContentManager else { return }
            // Use TextKit document coordinates. firstRect(forCharacterRange:)
            // is a screen-space IME API and can return zero for offscreen text.
            var targetY: CGFloat = 0
            if line > 1 {
                manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
                    let end = contentManager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.endLocation)
                    targetY = fragment.layoutFragmentFrame.minY + view.textContainerInset.height - 12
                    return end <= location
                }
            }
            clip.scroll(to: NSPoint(x: 0, y: max(0, targetY)))
            view.enclosingScrollView?.reflectScrolledClipView(clip)
        }
        private func processNavigation() {
            guard let navigation, let view = textView else { return }
            if lastJump != navigation.jumpID, let line = navigation.jumpLine {
                lastJump = navigation.jumpID
                go(to: line, caret: true)
                view.window?.makeFirstResponder(view)
            }
            if lastFind != navigation.findID, let action = navigation.findAction {
                lastFind = navigation.findID
                view.window?.makeFirstResponder(view)
                let item = NSMenuItem(); item.tag = action
                view.performTextFinderAction(item)
            }
        }

        // `nonisolated(unsafe)` only so `deinit` can hand it back to the
        // notification center: it is written once, on the main actor, and read
        // nowhere else.
        nonisolated(unsafe) private var scrollObserver: (any NSObjectProtocol)?

        private var installedToken: String?
        /// Guards against the delegate callback re-entering during a programmatic swap.
        private var isInstalling = false
        /// Set right before `onEdit` fires from `textDidChange`. The edit already
        /// lives, correctly highlighted, in the live text storage; the SwiftUI
        /// re-render it triggers hands that same content straight back down as
        /// `content`. Without this flag `install()` cannot tell that apart from a
        /// genuine external change, replaces the storage wholesale on every
        /// keystroke, and the caret gets discarded in the process - which is the
        /// "cursor jumps to the end" bug.
        private var pendingLocalEdit = false

        init(onEdit: @escaping (String) -> Void) {
            self.onEdit = onEdit
        }

        deinit { if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) } }

        /// Report the clip view's offset as the reader scrolls.
        ///
        /// Bounds-change notifications rather than a `NSScrollView` delegate:
        /// they fire for programmatic scrolls and Find-bar jumps too, not only
        /// for the wheel, so the toolbar cannot get stuck in the wrong state.
        func observeScrolling(of scrollView: NSScrollView) {
            let clip = scrollView.contentView
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clip,
                queue: .main
            ) { [weak self, weak clip] _ in
                guard let self, let clip else { return }
                // The queue is `.main`, so this is the main actor - but the
                // notification block's signature does not say so.
                MainActor.assumeIsolated {
                    self.onScroll(max(0, clip.bounds.origin.y))
                    self.positionSaveTask?.cancel()
                    self.positionSaveTask = Task { [weak self] in
                        try? await Task.sleep(for: .milliseconds(300))
                        guard !Task.isCancelled else { return }
                        self?.rememberPosition()
                    }
                }
            }
        }

        /// Swap in a new attributed string, preserving the reader's place.
        func install(_ content: NSAttributedString, mode: ViewMode, token: String) {
            install({ content }, mode: mode, token: token)
        }

        func install(_ makeContent: () -> NSAttributedString, mode: ViewMode, token: String) {
            guard let textView else { return }
            if pendingLocalEdit {
                pendingLocalEdit = false
                if activeKey == incomingKey && textView.string == incomingSource {
                    installedToken = token
                    processNavigation(); return
                }
            }
            guard installedToken != token else { processNavigation(); return }
            let content = makeContent()
            rememberPosition()
            let changedFile = activeKey != incomingKey
            let position = changedFile
                ? ((UserDefaults.standard.dictionary(forKey: "readingLines") as? [String: Int])?[incomingKey] ?? 1)
                : visibleLine()
            let previousSelection = textView.selectedRange()
            isInstalling = true; restoring = true
            installedSource = incomingSource; installedStyle = incomingStyle
            let previousOffset = textView.enclosingScrollView?.contentView.bounds.origin
            textView.textStorage?.setAttributedString(content)
            textView.isEditable = mode == .editor
            textView.isSelectable = true
            textView.setAccessibilityLabel("Markdown source")
            activeKey = incomingKey
            installedToken = token; isInstalling = false
            textView.needsDisplay = true
            if changedFile {
                textView.setSelectedRange(NSRange(location: index(for: position), length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: min(previousSelection.location, content.length), length: 0))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.installedToken == token else { return }
                if !changedFile, let offset = previousOffset, let clip = self.textView?.enclosingScrollView?.contentView {
                    self.textView?.layoutSubtreeIfNeeded()
                    clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: offset, size: clip.bounds.size)).origin)
                    self.textView?.enclosingScrollView?.reflectScrolledClipView(clip)
                } else { self.go(to: position, caret: false) }
                self.restoring = false
                self.processNavigation()
            }
        }

        // MARK: NSTextViewDelegate

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
            if textScale != 1 {
                let range = (storage.string as NSString).lineRange(for: NSRange(location: min(caret.location, storage.length), length: 0))
                let scaled = storage.attributedSubstring(from: range).scaledFonts(by: textScale)
                scaled.enumerateAttribute(.font, in: NSRange(location: 0, length: scaled.length)) { value, local, _ in
                    if let value { storage.addAttribute(.font, value: value, range: NSRange(location: range.location + local.location, length: local.length)) }
                }
            }
            pendingLocalEdit = true
            onEdit(storage.string)
        }
    }
}

// MARK: - Text view

/// Keeps the text column at `measure` points wide and centred, and routes
/// Undo to the document's history rather than the view's own.
final class MeasuredTextView: NSTextView {
    var history: UndoManager?
    override var undoManager: UndoManager? { history ?? super.undoManager }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z", let history {
            if event.modifierFlags.contains(.shift) { history.redo() } else { history.undo() }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    var measure: CGFloat = Theme.defaultMeasure {
        didSet { if measure != oldValue { needsLayout = true } }
    }

    @objc func undo(_ sender: Any?) { history?.undo() }
    @objc func redo(_ sender: Any?) { history?.redo() }
    override func doCommand(by selector: Selector) {
        if selector == NSSelectorFromString("undo:"), let history { history.undo(); return }
        if selector == NSSelectorFromString("redo:"), let history { history.redo(); return }
        super.doCommand(by: selector)
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z", let history {
            if event.modifierFlags.contains(.shift) { history.redo() } else { history.undo() }
            return
        }
        super.keyDown(with: event)
    }

    override func layout() {
        let available = bounds.width
        let column = min(measure, max(available - Theme.textInset.width * 2, 200))
        let side = max((available - column) / 2, Theme.textInset.width)

        if abs(textContainerInset.width - side) > 0.5 || textContainerInset.height != Theme.textInset.height {
            textContainerInset = NSSize(width: side, height: Theme.textInset.height)
        }
        if textContainer?.containerSize.width != column {
            textContainer?.containerSize = NSSize(width: column, height: .greatestFiniteMagnitude)
        }
        super.layout()
    }
}
