import AppKit
import Testing
@testable import MarkdownReader

@MainActor
struct ReaderTests {
    private func fixture(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reader-test-\(UUID()).md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func undoReturnsToSavedStateAndRedoRestoresEdit() throws {
        let url = try fixture("original"); defer { try? FileManager.default.removeItem(at: url) }
        let model = DocumentModel(); try model.open(url)
        model.undoManager.groupsByEvent = false
        model.undoManager.beginUndoGrouping(); model.bufferDidChange(to: "edited"); model.undoManager.endUndoGrouping()
        #expect(model.isDirty)
        model.undoManager.undo()
        #expect(model.text == "original"); #expect(!model.isDirty)
        model.undoManager.redo()
        #expect(model.text == "edited"); #expect(model.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "original")
    }

    @Test func editorKeyboardUndoUsesDocumentHistory() throws {
        let url = try fixture("original"); defer { try? FileManager.default.removeItem(at: url) }
        let model = DocumentModel(); try model.open(url)
        model.undoManager.groupsByEvent = false
        model.undoManager.beginUndoGrouping(); model.bufferDidChange(to: "edited"); model.undoManager.endUndoGrouping()
        let view = MeasuredTextView(usingTextLayoutManager: true); view.history = model.undoManager
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        #expect(view.performKeyEquivalent(with: event)); #expect(model.text == "original")
    }

    @Test func saveAsChangesDestinationWithoutWritingOriginal() throws {
        let original = try fixture("original")
        let destination = original.deletingLastPathComponent().appendingPathComponent("copy-\(UUID()).md")
        defer { try? FileManager.default.removeItem(at: original); try? FileManager.default.removeItem(at: destination) }
        let model = DocumentModel(); try model.open(original); model.bufferDidChange(to: "new version")
        if case .saved = model.saveAs(to: destination) {} else { Issue.record("Save As failed") }
        #expect(model.url == destination); #expect(!model.isDirty)
        #expect(try String(contentsOf: original, encoding: .utf8) == "original")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "new version")
    }

    @Test func typingDoesNotRunAnotherFullRenderingPass() {
        let view = MeasuredTextView(usingTextLayoutManager: true)
        let coordinator = MarkdownTextPane.Coordinator(onEdit: { _ in })
        coordinator.textView = view
        coordinator.incomingKey = "test"
        coordinator.incomingSource = "one"
        var renderCount = 0
        coordinator.install({ renderCount += 1; return SourceHighlighter.highlight("one") }, mode: .editor, token: "1")
        view.textStorage?.setAttributedString(SourceHighlighter.highlight("two"))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        coordinator.incomingSource = "two"
        coordinator.install({ renderCount += 1; return SourceHighlighter.highlight("two") }, mode: .editor, token: "2")
        #expect(renderCount == 1)
        #expect(view.string == "two")
    }

    @Test func detectsConflictEvenWithUnchangedModificationDate() throws {
        let url = try fixture("original"); defer { try? FileManager.default.removeItem(at: url) }
        let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let model = DocumentModel(); try model.open(url); model.bufferDidChange(to: "mine")
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        if case .conflict = model.save() {} else { Issue.record("Expected conflict") }
        #expect(try String(contentsOf: url, encoding: .utf8) == "theirs")
    }

    @Test func externalRefreshProtectsDirtyBuffer() throws {
        let url = try fixture("one"); defer { try? FileManager.default.removeItem(at: url) }
        let model = DocumentModel(); try model.open(url)
        try "two".write(to: url, atomically: true, encoding: .utf8)
        model.checkExternalChanges(); #expect(model.text == "two"); #expect(!model.isDirty)
        model.bufferDidChange(to: "mine")
        try "three".write(to: url, atomically: true, encoding: .utf8)
        model.checkExternalChanges(); #expect(model.text == "mine"); #expect(model.externalChange)
    }

    @Test func deletingFileKeepsUnsavedText() throws {
        let url = try fixture("one")
        let model = DocumentModel(); try model.open(url); model.bufferDidChange(to: "mine")
        try FileManager.default.removeItem(at: url)
        model.checkExternalChanges()
        #expect(model.fileUnavailable); #expect(model.text == "mine")
        if case .conflict = model.save() {} else { Issue.record("Missing file must not silently overwrite") }
    }

    @Test func rendererMapsLinesAndResolvesRelativeLinks() {
        let base = URL(fileURLWithPath: "/tmp/docs/readme.md")
        let html = HTMLRenderer.render("# Title\n\n[Next](next.md)\n", baseURL: base)
        #expect(html.contains("<h1 id=\"title\" data-line=\"1\">Title</h1>"))
        #expect(html.contains("<p data-line=\"3\"><a href=\"file:///tmp/docs/next.md\">Next</a></p>"))
        let anchor = HTMLRenderer.render("[Title](#title)", baseURL: base)
        #expect(anchor.contains("href=\"file:///tmp/docs/readme.md#title\""))
        let unsafe = HTMLRenderer.render("[x](javascript:alert(1)) <b>raw</b>")
        #expect(!unsafe.contains("<a "))
        #expect(!unsafe.contains("<b>"))
        #expect(unsafe.contains("&lt;b&gt;"))
    }

    @Test func codeBlocksKeepWhitespaceAndCarryCopyButton() {
        let html = HTMLRenderer.render("```swift\n  let x = 1\n  let y = <2>\n```")
        #expect(html.contains("<button class=\"copy\""))
        #expect(html.contains("<code class=\"language-swift\">  let x = 1\n  let y = &lt;2&gt;</code>"))
    }

    @Test func taskItemsBecomeCheckboxesOnTheirSourceLine() {
        let html = HTMLRenderer.render("- [ ] One\n- [x] Two\n")
        #expect(html.contains("<ul class=\"tasks\""))
        #expect(html.contains("<input type=\"checkbox\" data-line=\"1\" aria-label=\"Toggle task\">"))
        #expect(html.contains("<input type=\"checkbox\" data-line=\"2\" aria-label=\"Toggle task\" checked>"))
    }

    @Test func tablesAndImagesRender() {
        let base = URL(fileURLWithPath: "/tmp/docs/readme.md")
        let html = HTMLRenderer.render("| a | b |\n|:--|--:|\n| 1 | 2 |\n\n![Diagram](diagram.png)\n", baseURL: base)
        #expect(html.contains("<th style=\"text-align:left\">a</th><th style=\"text-align:right\">b</th>"))
        #expect(html.contains("<td style=\"text-align:left\">1</td>"))
        #expect(html.contains("<img src=\"mdimg:///tmp/docs/diagram.png\" alt=\"Diagram\">"))
        #expect(PreviewImages.source(for: "https://example.com/a.png", baseURL: base) == "https://example.com/a.png")
        #expect(PreviewImages.source(for: "ftp://example.com/a.png", baseURL: base) == nil)
    }

    @Test func headingOutlineIgnoresCodeAndSupportsSetext() {
        let headings = DocumentStructure.headings("# First\n\n```md\n# Not a heading\n```\n\nSecond\n---\n")
        #expect(headings.map(\.title) == ["First", "Second"])
        #expect(headings.map(\.line) == [1, 7])
    }

}

@MainActor
struct AppearanceTests {
    /// Choosing System has to clear the pinned appearance, not leave the window
    /// on whichever explicit one was picked last.
    @Test func systemClearsAnExplicitAppearance() {
        let settings = AppSettings()
        defer { settings.appearance = .system }
        settings.appearance = .light
        #expect(NSApplication.shared.appearance?.name == .aqua)
        settings.appearance = .dark
        #expect(NSApplication.shared.appearance?.name == .darkAqua)
        settings.appearance = .system
        #expect(NSApplication.shared.appearance == nil)
    }
}
