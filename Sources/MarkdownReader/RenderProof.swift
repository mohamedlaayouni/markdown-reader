import AppKit
import SwiftUI
import WebKit

/// Development tool: lays out a markdown file through the real renderer and the
/// real text view offscreen, then writes a PNG.
///
///     Markdown\ Reader --render-proof <in.md> <out.png> [preview|editor] [width]
///
/// It uses `MeasuredTextView`, not a plain text view, so the drawn block
/// decorations (code grounds, rules) are exercised too.
@MainActor
enum RenderProof {
    static func run(arguments: [String]) -> Int32 {
        guard arguments.count >= 2 else {
            fail("usage: --render-proof <in.md> <out.png> [preview|editor] [width]")
            return 2
        }

        let inputPath = arguments[0]
        let outputPath = arguments[1]
        let mode: ViewMode = (arguments.count > 2 && arguments[2] == "editor") ? .editor : .preview
        let measure = CGFloat(arguments.count > 3 ? Double(arguments[3]) ?? 880 : 880)

        guard let markdown = try? String(contentsOf: URL(filePath: inputPath), encoding: .utf8) else {
            fail("cannot read \(inputPath)")
            return 1
        }

        if mode == .preview {
            return renderPreview(markdown: markdown, baseURL: URL(filePath: inputPath), measure: measure, outputPath: outputPath)
        }
        let content = SourceHighlighter.highlight(markdown)

        let width = measure + Theme.textInset.width * 2
        let textView = MeasuredTextView(usingTextLayoutManager: true)
        textView.measure = measure
        textView.isRichText = false
        textView.drawsBackground = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        textView.textStorage?.setAttributedString(content)
        textView.layout()

        guard let layoutManager = textView.textLayoutManager else {
            fail("no TextKit 2 layout manager")
            return 1
        }

        // Height is the bottom of the last laid-out fragment; TextKit 2 has no
        // usedRect equivalent.
        var contentHeight: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            contentHeight = max(contentHeight, fragment.layoutFragmentFrame.maxY)
            return true
        }

        let height = ceil(contentHeight) + Theme.textInset.height * 2
        guard height > 0 else {
            fail("nothing laid out")
            return 1
        }
        textView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        textView.layout()

        guard let rep = textView.bitmapImageRepForCachingDisplay(in: textView.bounds) else {
            fail("cannot allocate bitmap")
            return 1
        }
        textView.cacheDisplay(in: textView.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fail("cannot encode png")
            return 1
        }

        do {
            try data.write(to: URL(filePath: outputPath))
        } catch {
            fail("cannot write \(outputPath): \(error)")
            return 1
        }

        print("rendered \(mode.rawValue): \(Int(width))x\(Int(height)) -> \(outputPath)")
        return 0
    }

    /// The preview is a web view, so it is laid out by WebKit in a borderless
    /// window sized to the page, then snapshotted. WebKit does not paint views
    /// that are not on screen, which is why the window is ordered in.
    private static func renderPreview(markdown: String, baseURL: URL, measure: CGFloat, outputPath: String) -> Int32 {
        _ = NSApplication.shared
        let width = measure + Theme.textInset.width * 2
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(PreviewImageHandler(), forURLScheme: PreviewImages.scheme)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 600), configuration: configuration)
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .textBackgroundColor
        window.contentView = webView
        window.orderFrontRegardless()

        let state = ProofState()
        let delegate = ProofNavigationDelegate { [weak webView] in
            guard let webView else { state.finish(1); return }
            let html = HTMLRenderer.render(markdown, baseURL: baseURL)
            webView.callAsyncJavaScript(
                "window.reader.setStyle({measure, zoom, face, accent}); window.reader.setContent({html, line, keepScroll}); return document.documentElement.scrollHeight",
                arguments: ["measure": Double(measure), "zoom": 1.0, "face": "sans", "accent": NSColor.controlAccentColor.cssHex,
                            "html": html, "line": 1, "keepScroll": false],
                in: nil, in: .page
            ) { result in
                MainActor.assumeIsolated {
                    let height = ceil((try? result.get()) as? Double ?? 0)
                    guard height > 0 else { fail("nothing laid out"); state.finish(1); return }
                    window.setContentSize(NSSize(width: width, height: height))
                    webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        let snapshot = WKSnapshotConfiguration()
                        snapshot.rect = webView.bounds
                        webView.takeSnapshot(with: snapshot) { image, error in
                            MainActor.assumeIsolated {
                                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                                      let data = rep.representation(using: .png, properties: [:]) else {
                                    fail("snapshot failed: \(error?.localizedDescription ?? "unknown")"); state.finish(1); return
                                }
                                do { try data.write(to: URL(filePath: outputPath)) } catch { fail("cannot write \(outputPath): \(error)"); state.finish(1); return }
                                print("rendered preview: \(Int(width))x\(Int(height)) -> \(outputPath)")
                                state.finish(0)
                            }
                        }
                    }
                }
            }
        }
        webView.navigationDelegate = delegate
        webView.loadHTMLString(PreviewPage.shell, baseURL: nil)
        let deadline = Date(timeIntervalSinceNow: 20)
        while !state.done, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        if !state.done { fail("timed out waiting for WebKit") }
        window.orderOut(nil)
        return state.done ? state.code : 1
    }

    @MainActor private final class ProofState {
        var done = false
        var code: Int32 = 0
        func finish(_ code: Int32) { self.code = code; done = true }
    }

    @MainActor private final class ProofNavigationDelegate: NSObject, @preconcurrency WKNavigationDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish() }
    }

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

// MARK: - Icon proof

/// Renders `SaveDiskIcon` offscreen so its silhouette can be checked without a
/// running app window.
@MainActor
enum IconProof {
    static func run(outputPath: String) -> Int32 {
        // Render several sizes side by side, including real toolbar scale
        // (15pt @2x = 30px), since fine detail can merge at small sizes even
        // when it reads fine at a large preview.
        let sizes: [CGFloat] = [30, 60, 128]
        let gap: CGFloat = 20
        let totalWidth = sizes.reduce(0, +) + gap * CGFloat(sizes.count + 1)
        let height = sizes.max()! + gap * 2

        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: totalWidth, height: height))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.black.cgColor

        var x: CGFloat = gap
        for size in sizes {
            let view = SaveDiskIcon()
                .stroke(style: StrokeStyle(lineWidth: max(size * 0.05, 1.4), lineCap: .round, lineJoin: .round))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: x, y: (height - size) / 2, width: size, height: size)
            canvas.addSubview(hosting)
            x += size + gap
        }
        canvas.layoutSubtreeIfNeeded()

        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return 1 }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }

        do {
            try data.write(to: URL(filePath: outputPath))
        } catch {
            FileHandle.standardError.write(Data("cannot write \(outputPath): \(error)\n".utf8))
            return 1
        }
        print("icon (30/60/128px) -> \(outputPath)")
        return 0
    }
}

// MARK: - Cursor-preservation proof

/// Directly exercises `MarkdownTextPane.Coordinator` the way SwiftUI does on a
/// keystroke: an edit lands in the live text storage, the resulting model
/// change is reflected back down as freshly-rendered `content`, and `install()`
/// is called again exactly as `updateNSView` would call it.
///
/// This is what regressed before the `pendingLocalEdit` fix: `install()` could
/// not tell that second call apart from a genuine external change, replaced the
/// text storage wholesale, and lost the caret. Prints PASS/FAIL rather than
/// asserting, so a regression here shows up as CLI output, not a crash.
@MainActor
enum CursorProof {
    static func run() -> Int32 {
        let initial = "Hello world"
        let textView = MeasuredTextView(usingTextLayoutManager: true)
        textView.measure = 880
        textView.textContainer?.lineFragmentPadding = 0

        var latestText = initial
        let coordinator = MarkdownTextPane.Coordinator(onEdit: { latestText = $0 })
        coordinator.textView = textView
        coordinator.incomingKey = "cursor-proof"
        coordinator.incomingSource = initial
        textView.delegate = coordinator

        coordinator.install(
            SourceHighlighter.highlight(initial),
            mode: .editor,
            token: "doc|editor|sans|\(initial.count)"
        )

        // Simulate typing "X" right after "Hello" (position 5), landing the
        // caret at position 6 - exactly what NSTextView does on a real keystroke.
        guard let storage = textView.textStorage else {
            print("FAIL: no text storage")
            return 1
        }
        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "X")
        let expectedCaret = NSRange(location: 6, length: 0)
        textView.setSelectedRange(expectedCaret)

        // What `textDidChange` does on every keystroke.
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        // What RootView's `updateNSView` does on the SwiftUI re-render the edit
        // just triggered: recompute `content` from the (now-updated) model text
        // and call `install()` again.
        coordinator.incomingSource = latestText
        coordinator.install(
            SourceHighlighter.highlight(latestText),
            mode: .editor,
            token: "doc|editor|sans|\(latestText.count)"
        )

        let expectedText = "HelloX world"
        let actualText = textView.textStorage?.string ?? ""
        let actualCaret = textView.selectedRange()

        var ok = true
        if actualText != expectedText {
            print("FAIL: text = \"\(actualText)\", expected \"\(expectedText)\"")
            ok = false
        }
        if actualCaret != expectedCaret {
            print("FAIL: caret = \(actualCaret), expected \(expectedCaret)")
            ok = false
        }
        if ok {
            print("PASS: text and caret both preserved across the post-edit re-render")
        }
        return ok ? 0 : 1
    }
}


// MARK: - Checkbox hit-target proof

/// Confirms every task item renders as a real checkbox carrying the source line
/// the toggle handler will edit, and that the line really holds a task marker.
@MainActor
enum CheckboxProof {
    static func run(path: String) -> Int32 {
        guard let markdown = try? String(contentsOf: URL(filePath: path), encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
            return 1
        }
        let html = HTMLRenderer.render(markdown)
        let sourceLines = markdown.components(separatedBy: "\n")
        let pattern = try! NSRegularExpression(pattern: #"<input type="checkbox" data-line="(\d+)"[^>]*?( checked)?>"#)
        let matches = pattern.matches(in: html, range: NSRange(location: 0, length: (html as NSString).length))
        guard !matches.isEmpty else {
            print("FAIL: no checkboxes in the rendered output")
            return 1
        }
        var ok = true
        for match in matches {
            let line = Int((html as NSString).substring(with: match.range(at: 1))) ?? 0
            let checked = match.range(at: 2).location != NSNotFound
            let source = sourceLines.indices.contains(line - 1) ? sourceLines[line - 1] : "<out of range>"
            let hasMarker = source.contains("[ ]") || source.contains("[x]") || source.contains("[X]")
            let stateMatches = checked ? !source.contains("[ ]") : source.contains("[ ]")
            let good = hasMarker && stateMatches
            if !good { ok = false }
            print("\(good ? "ok  " : "BAD ")line=\(line) checked=\(checked) source=\(source.trimmingCharacters(in: .whitespaces).debugDescription)")
        }
        print(ok ? "PASS: \(matches.count) checkbox(es), all mapped to real task lines" : "FAIL: some checkboxes did not line up")
        return ok ? 0 : 1
    }
}
