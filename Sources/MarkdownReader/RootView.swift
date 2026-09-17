import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var settings: AppSettings
    @Bindable var library: Library
    @Bindable var document: DocumentModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var navigation = ReaderNavigation()
    @State private var quickOpen = false
    @State private var message: String?
    @State private var imageRetry = 0
    @State private var previewFindVisible = false
    @State private var previewFindQuery = ""
    @State private var previewFindFailed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(library: library, onOpen: open, onAdd: openPanel, onRemove: remove, onLocate: relocate, revealed: settings.sidebarVisible)
                .navigationSplitViewColumnWidth(min: 210, ideal: settings.sidebarWidth, max: 340)
                .modifier(SettledWidthObserver { width in
                    if width >= 210, abs(settings.sidebarWidth - Double(width)) > 0.5 {
                        settings.sidebarWidth = Double(width)
                    }
                })
        } detail: {
            VStack(spacing: 0) {
                if document.externalChange || document.fileUnavailable {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                        Text(document.fileUnavailable ? "This file is unavailable. Your edits are still here." : "This file changed elsewhere. Your edits are still here.")
                        Spacer()
                        Button("Reload…") { reload() }.disabled(document.fileUnavailable)
                        Button("Save As…") { saveAs() }
                    }.font(.callout).padding(10).background(.bar)
                }
                if document.url == nil {
                    WelcomeView(onAdd: openPanel)
                } else {
                    Group {
                        if settings.mode == .preview {
                            PreviewWebPane(html: { HTMLRenderer.render(document.text, baseURL: document.url) },
                                contentToken: token, documentKey: document.url?.path ?? "",
                                measure: CGFloat(settings.measure), textScale: settings.textSize / Double(Theme.bodySize), face: settings.face,
                                imageRevision: imageRetry, navigation: navigation, findQuery: previewFindVisible ? previewFindQuery : "",
                                onToggleTask: toggleTask, onLink: openLink, onFeedback: { document.status = $0 },
                                onFindResult: { previewFindFailed = !$0 })
                                .overlay(alignment: .topTrailing) { if previewFindVisible { previewFindBar } }
                        } else {
                            MarkdownTextPane(mode: .editor, content: { content },
                                measure: CGFloat(settings.measure), contentToken: token,
                                onEdit: document.bufferDidChange,
                                contentStyleToken: styleToken, documentKey: document.url?.path ?? "", source: document.text,
                                navigation: navigation, textScale: settings.textSize / Double(Theme.bodySize),
                                onFeedback: { document.status = $0 }, history: document.undoManager)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .navigationTitle(document.url == nil ? "Markdown Reader" : document.displayName)
        .navigationSubtitle(document.isDirty ? "Edited" : document.status)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { document.saveInteractively() } label: {
                    SaveDiskIcon()
                        .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                        .accessibilityLabel("Save")
                }
                .help("Save changes (⌘S)").disabled(!document.isDirty)
            }
            ToolbarItem(placement: .principal) {
                ModeToggle(mode: $settings.mode).disabled(document.url == nil)
            }
        }
        .background(WindowConfiguration(document: document, isDirty: document.isDirty, url: document.url).frame(width: 0, height: 0))
        .focusedSceneValue(\.appActions, actions)
        .sheet(isPresented: $quickOpen) { QuickOpenView(items: library.items, open: open) }
        .alert("Could not complete the action", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
        .onChange(of: settings.sidebarVisible) { _, visible in
            let target: NavigationSplitViewVisibility = visible ? .all : .detailOnly
            // The native toolbar already animates its own toggle. Do not echo it
            // back into another transaction when we persist the resulting state.
            guard columnVisibility != target else { return }
            withAnimation(reduceMotion ? nil : Motion.sidebar) { columnVisibility = target }
        }
        .onChange(of: columnVisibility) { _, visibility in
            let visible = visibility != .detailOnly
            if settings.sidebarVisible != visible { settings.sidebarVisible = visible }
        }
        .onChange(of: OpenInbox.shared.pending) { _, urls in
            guard !urls.isEmpty else { return }
            OpenInbox.shared.pending = []
            accept(urls)
        }
        .onAppear {
            columnVisibility = settings.sidebarVisible ? .all : .detailOnly
            AppDelegate.confirmTermination = { document.confirmLeaving() }
            if let item = library.items.first(where: { $0.id == library.selection }) { open(item) }
            if !OpenInbox.shared.pending.isEmpty {
                let urls = OpenInbox.shared.pending; OpenInbox.shared.pending = []; accept(urls)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                document.checkExternalChanges(); library.refreshMissing()
            }
        }
        .task(id: document.status) {
            guard !document.status.isEmpty else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { document.status = "" }
        }
    }

    private var styleToken: String { "\(settings.textSize)" }
    /// Preview style (face, measure, size) is applied live by the web pane and
    /// does not re-render; the editor's highlighted source does not depend on it.
    private var token: String {
        settings.mode == .preview
            ? "\(document.url?.path ?? "")|preview|\(document.revision)"
            : "\(document.url?.path ?? "")|editor|\(document.revision)|\(styleToken)"
    }
    private var content: NSAttributedString {
        SourceHighlighter.highlight(document.text).scaledFonts(by: settings.textSize / Double(Theme.bodySize))
    }
    /// Find in preview. The editor has AppKit's find bar; WebKit has none of its
    /// own, so this small bar drives `WKWebView.find`.
    private var previewFindBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find", text: $previewFindQuery)
                .textFieldStyle(.plain).frame(width: 180)
                .onSubmit { navigation.find(.nextMatch) }
                .onExitCommand { previewFindVisible = false }
            if previewFindFailed && !previewFindQuery.isEmpty { Text("Not found").font(.caption).foregroundStyle(.secondary) }
            Button("Previous", systemImage: "chevron.up") { navigation.find(.previousMatch) }.labelStyle(.iconOnly)
            Button("Next", systemImage: "chevron.down") { navigation.find(.nextMatch) }.labelStyle(.iconOnly)
            Button("Done") { previewFindVisible = false }
        }
        .buttonStyle(.borderless).controlSize(.small)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .padding(12)
    }
    private func find(_ action: NSTextFinder.Action) {
        guard settings.mode == .preview else { navigation.find(action); return }
        switch action {
        case .showFindInterface: previewFindVisible = true
        case .hideFindInterface: previewFindVisible = false
        default: if previewFindVisible { navigation.find(action) } else { previewFindVisible = true }
        }
    }
    private var actions: AppActions {
        AppActions(openFiles: openPanel, save: { document.saveInteractively() }, toggleMode: settings.toggleMode,
            toggleSidebar: { settings.sidebarVisible.toggle() }, canSave: document.isDirty, hasDocument: document.url != nil,
            quickOpen: { quickOpen = true },
            find: find,
            reveal: reveal, saveAs: saveAs, reloadImages: { imageRetry += 1 })
    }
    private func open(_ item: LibraryItem) {
        guard let url = library.url(for: item) else { library.refreshMissing(); return }
        if document.url == url { library.selection = item.id; return }
        guard document.confirmLeaving() else { return }
        do {
            try document.open(url); library.selection = item.id
            if settings.alwaysOpenInPreview { settings.mode = .preview }
        } catch { message = error.localizedDescription }
    }
    private func accept(_ urls: [URL]) {
        library.add(urls)
        if let first = urls.first, let item = library.items.first(where: { $0.token == first.path }) { open(item) }
    }
    private func openPanel() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["md", "markdown", "mdown"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK { accept(panel.urls) }
    }
    private func remove(_ item: LibraryItem) {
        if library.selection == item.id {
            guard document.confirmLeaving() else { return }
            document.close()
            library.remove(item.id)
            if let next = library.items.first(where: { $0.id == library.selection }) { open(next) }
        } else { library.remove(item.id) }
    }
    private func reload() {
        let alert = NSAlert(); alert.messageText = "Reload from disk?"
        alert.informativeText = "This replaces your current edits with the file on disk."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Reload")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try document.revert() } catch { message = error.localizedDescription }
    }
    private func saveAs() {
        guard document.url != nil else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = document.displayName
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        switch document.saveAs(to: url) {
        case .saved:
            library.add([url])
            library.selection = library.items.first(where: { $0.token == url.path })?.id
        case .failed(let error): message = error.localizedDescription
        default: break
        }
    }
    private func relocate(_ item: LibraryItem, to url: URL) {
        if library.selection == item.id {
            guard document.confirmLeaving() else { return }
            do { try document.open(url) } catch { message = error.localizedDescription; return }
        }
        library.relocate(item.id, to: url)
    }

    private func reveal() { if let url = document.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    private func openLink(_ url: URL) {
        if url.isFileURL {
            let fragment = url.fragment?.removingPercentEncoding
            var components = URLComponents(url: url, resolvingAgainstBaseURL: true); components?.fragment = nil
            guard let file = components?.url else { return }
            if ["md", "markdown", "mdown"].contains(file.pathExtension.lowercased()) {
                accept([file])
                if document.url == file, let fragment, let heading = DocumentStructure.headings(document.text).first(where: { DocumentStructure.slug($0.title) == fragment }) { navigation.jump(to: heading.line) }
                return
            }
        }
        if !NSWorkspace.shared.open(url) { message = "Could not open this link: \(url.absoluteString)" }
    }
    private func toggleTask(onLine line: Int) {
        var lines = document.text.components(separatedBy: "\n")
        guard lines.indices.contains(line - 1), let range = lines[line - 1].range(of: "[ ]") ?? lines[line - 1].range(of: "[x]") ?? lines[line - 1].range(of: "[X]") else { return }
        let checked = lines[line - 1][range] != "[ ]"
        lines[line - 1].replaceSubrange(range, with: checked ? "[ ]" : "[x]")
        document.bufferDidChange(to: lines.joined(separator: "\n"))
        document.undoManager.setActionName("Toggle Task")
    }
}

struct WelcomeView: View {
    let onAdd: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("No file open", systemImage: "doc.text")
        } description: {
            Text("Add Markdown files to your library. Your files stay where they are.")
        } actions: { Button("Add Files…", action: onAdd).buttonStyle(.glassProminent) }
    }
}
struct ModeToggle: View {
    @Binding var mode: ViewMode
    var body: some View {
        Picker("View", selection: $mode) {
            Text("Preview").tag(ViewMode.preview); Text("Editor").tag(ViewMode.editor)
        }.pickerStyle(.segmented).labelsHidden().frame(width: 148).help("Switch reading and editing (⌘⇧P)")
    }
}
private struct WindowConfiguration: NSViewRepresentable {
    let document: DocumentModel
    let isDirty: Bool
    let url: URL?
    func makeCoordinator() -> Coordinator { Coordinator(document: document) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isDocumentEdited = isDirty
            window.representedURL = url
            window.toolbarStyle = .unified
            if window.frameAutosaveName.isEmpty {
                window.setFrameAutosaveName("MarkdownReaderMainWindow")
                window.setFrameUsingName("MarkdownReaderMainWindow")
            }
            window.delegate = context.coordinator
        }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        let document: DocumentModel
        init(document: DocumentModel) { self.document = document }
        func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { document.undoManager }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard document.confirmLeaving() else { return false }
            document.close()
            return true
        }
    }
}

extension NSAttributedString {
    func scaledFonts(by scale: Double) -> NSAttributedString {
        guard abs(scale - 1) > 0.001 else { return self }
        let out = NSMutableAttributedString(attributedString: self)
        enumerateAttribute(.font, in: NSRange(location: 0, length: length)) { value, range, _ in
            if let font = value as? NSFont { out.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale) ?? font, range: range) }
        }
        return out
    }
}

/// Keep per-frame split-view geometry local. Only the settled width reaches the
/// document renderer and persisted settings, avoiding whole-window updates.
private struct SettledWidthObserver: ViewModifier {
    let onChange: (CGFloat) -> Void
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: width) {
                guard width > 0 else { return }
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return }
                onChange(width)
            }
    }
}
