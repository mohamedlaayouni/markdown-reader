import AppKit
import SwiftUI
import WebKit

/// The rendered preview: one `WKWebView` that loads `PreviewPage.shell` once
/// and is then driven through `window.reader`.
///
/// Content swaps do not reload the page, so there is no flash and scroll
/// state survives. Source lines are the shared coordinate with the editor:
/// the page reports the line at the top of the viewport, and that is what is
/// remembered per document and handed across a mode switch.
struct PreviewWebPane: NSViewRepresentable {
    let html: () -> String
    /// Identifies which document/revision the HTML belongs to.
    let contentToken: String
    let documentKey: String
    let measure: CGFloat
    let textScale: Double
    let face: Theme.BodyFace
    var imageRevision = 0
    var navigation: ReaderNavigation? = nil
    /// The find bar's text. Empty clears the search.
    var findQuery = ""
    var onScroll: (CGFloat) -> Void = { _ in }
    var onToggleTask: (Int) -> Void = { _ in }
    var onLink: (URL) -> Void = { NSWorkspace.shared.open($0) }
    var onFeedback: (String) -> Void = { _ in }
    var onFindResult: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PreviewWebView {
        let coordinator = context.coordinator
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(PreviewImageHandler(), forURLScheme: PreviewImages.scheme)
        configuration.userContentController.add(ScriptMessageProxy(coordinator), name: "native")
        let webView = PreviewWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.setAccessibilityLabel("Document preview")
        coordinator.webView = webView
        apply(to: coordinator)
        webView.loadHTMLString(PreviewPage.shell, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: PreviewWebView, context: Context) {
        apply(to: context.coordinator)
    }

    static func dismantleNSView(_ webView: PreviewWebView, coordinator: Coordinator) {
        coordinator.rememberPosition()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "native")
        webView.navigationDelegate = nil
    }

    private func apply(to coordinator: Coordinator) {
        coordinator.onScroll = onScroll
        coordinator.onToggleTask = onToggleTask
        coordinator.onLink = onLink
        coordinator.onFeedback = onFeedback
        coordinator.onFindResult = onFindResult
        coordinator.navigation = navigation
        coordinator.setStyle(measure: measure, zoom: textScale, face: face)
        coordinator.setContent(html, token: contentToken, key: documentKey)
        coordinator.reloadImages(revision: imageRevision)
        coordinator.find(findQuery)
        coordinator.processNavigation()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, @preconcurrency WKNavigationDelegate {
        weak var webView: WKWebView?
        var onScroll: (CGFloat) -> Void = { _ in }
        var onToggleTask: (Int) -> Void = { _ in }
        var onLink: (URL) -> Void = { _ in }
        var onFeedback: (String) -> Void = { _ in }
        var onFindResult: (Bool) -> Void = { _ in }
        /// A jump requested before this pane existed belongs to the pane that
        /// was showing then; only later requests are acted on.
        var navigation: ReaderNavigation? {
            didSet { if oldValue == nil, let navigation { lastJump = navigation.jumpID; lastFind = navigation.findID } }
        }

        private var isReady = false
        private var queue: [() -> Void] = []
        private var installedToken: String?
        private var installedStyle = ""
        private var installedImageRevision = 0
        private var installedFind = ""
        private var activeKey = ""
        private var currentLine = 1
        private var lastJump: UUID?
        private var lastFind: UUID?
        private var positionSaveTask: Task<Void, Never>?

        private func whenReady(_ block: @escaping () -> Void) { isReady ? block() : queue.append(block) }

        private func call(_ body: String, _ arguments: [String: Any] = [:]) {
            webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { _ in }
        }

        func setContent(_ make: () -> String, token: String, key: String) {
            guard installedToken != token else { return }
            installedToken = token
            let html = make()
            let changedFile = activeKey != key
            if changedFile {
                rememberPosition()
                currentLine = (UserDefaults.standard.dictionary(forKey: "readingLines") as? [String: Int])?[key] ?? 1
                activeKey = key
            }
            let line = currentLine
            whenReady { [weak self] in
                self?.call("window.reader.setContent({html, line, keepScroll})", ["html": html, "line": line, "keepScroll": !changedFile])
            }
        }

        func setStyle(measure: CGFloat, zoom: Double, face: Theme.BodyFace) {
            let accent = NSColor.controlAccentColor.cssHex
            let token = "\(measure)|\(zoom)|\(face.rawValue)|\(accent)"
            guard installedStyle != token else { return }
            installedStyle = token
            whenReady { [weak self] in
                self?.call("window.reader.setStyle({measure, zoom, face, accent})",
                           ["measure": Double(measure), "zoom": zoom, "face": face.rawValue, "accent": accent])
            }
        }

        func reloadImages(revision: Int) {
            guard installedImageRevision != revision else { return }
            let first = installedImageRevision == 0 && installedToken == nil
            installedImageRevision = revision
            if !first { whenReady { [weak self] in self?.call("window.reader.reloadImages()") } }
        }

        func find(_ query: String) {
            guard installedFind != query else { return }
            installedFind = query
            guard !query.isEmpty else { whenReady { [weak self] in self?.call("window.reader.clearSelection()") }; return }
            findStep(forward: true)
        }

        private func findStep(forward: Bool) {
            guard !installedFind.isEmpty, let webView else { return }
            let configuration = WKFindConfiguration()
            configuration.backwards = !forward
            configuration.caseSensitive = false
            configuration.wraps = true
            webView.find(installedFind, configuration: configuration) { [weak self] result in
                self?.onFindResult(result.matchFound)
            }
        }

        func processNavigation() {
            guard let navigation else { return }
            if lastJump != navigation.jumpID, let line = navigation.jumpLine {
                lastJump = navigation.jumpID
                whenReady { [weak self] in self?.call("window.reader.jump({line})", ["line": line]) }
            }
            if lastFind != navigation.findID, let raw = navigation.findAction, let action = NSTextFinder.Action(rawValue: raw) {
                lastFind = navigation.findID
                switch action {
                case .nextMatch: findStep(forward: true)
                case .previousMatch: findStep(forward: false)
                default: break
                }
            }
        }

        func rememberPosition() {
            guard !activeKey.isEmpty else { return }
            var positions = UserDefaults.standard.dictionary(forKey: "readingLines") as? [String: Int] ?? [:]
            guard positions[activeKey] != currentLine else { return }
            positions[activeKey] = currentLine
            UserDefaults.standard.set(positions, forKey: "readingLines")
        }

        // MARK: Messages from the page

        func receive(_ body: Any) {
            guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
            switch type {
            case "scroll":
                if let line = message["line"] as? Int, line > 0 { currentLine = line }
                onScroll(CGFloat(message["y"] as? Double ?? 0))
                positionSaveTask?.cancel()
                positionSaveTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    self?.rememberPosition()
                }
            case "toggleTask":
                if let line = message["line"] as? Int, line > 0 { onToggleTask(line) }
            case "copyCode":
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message["code"] as? String ?? "", forType: .string)
                onFeedback("Code copied")
                if let webView {
                    NSAccessibility.post(element: webView, notification: .announcementRequested,
                                         userInfo: [.announcement: "Code copied", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                }
            default:
                break
            }
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            let pending = queue
            queue.removeAll()
            for block in pending { block() }
        }

        /// Only the shell itself may load. Every link click is handed to the
        /// app, which is where relative `.md` links and anchors are resolved.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                if let url = navigationAction.request.url {
                    onFeedback("Opened link")
                    onLink(url)
                }
                return
            }
            let isShell = navigationAction.request.url?.absoluteString == "about:blank"
            decisionHandler(isShell && navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}

/// Breaks the retain cycle `WKUserContentController` would otherwise form with
/// the coordinator.
private final class ScriptMessageProxy: NSObject, @preconcurrency WKScriptMessageHandler {
    private weak var coordinator: PreviewWebPane.Coordinator?
    init(_ coordinator: PreviewWebPane.Coordinator) { self.coordinator = coordinator }
    @MainActor
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        coordinator?.receive(message.body)
    }
}

/// `WKWebView` without the browser-ish context menu items: this is a document,
/// not a web page.
final class PreviewWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        let drop: Set<String> = [
            "WKMenuItemIdentifierReload", "WKMenuItemIdentifierOpenLinkInNewWindow", "WKMenuItemIdentifierDownloadLinkedFile",
            "WKMenuItemIdentifierOpenImageInNewWindow", "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierInspectElement",
            "WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward", "WKMenuItemIdentifierStop", "WKMenuItemIdentifierOpenFrameInNewWindow",
            "WKMenuItemIdentifierShowHideMediaControls", "WKMenuItemIdentifierToggleEnhancedFullScreen", "WKMenuItemIdentifierToggleFullScreen",
        ]
        for item in menu.items where item.identifier.map({ drop.contains($0.rawValue) }) == true { menu.removeItem(item) }
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem {
                if previousWasSeparator { menu.removeItem(item) }
                previousWasSeparator = true
            } else { previousWasSeparator = false }
        }
        if let last = menu.items.last, last.isSeparatorItem { menu.removeItem(last) }
        super.willOpenMenu(menu, with: event)
    }
}
