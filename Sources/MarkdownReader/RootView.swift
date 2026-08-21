import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var settings: AppSettings
    @Bindable var library: Library
    @Bindable var document: DocumentModel

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var conflictDate: Date?
    @State private var saveError: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(library: library, onOpen: open, onAdd: openPanel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 244, max: 320)
        } detail: {
            detail
        }
        .navigationTitle(document.url == nil ? "Markdown Reader" : document.displayName)
        .navigationSubtitle(document.isDirty ? "Edited" : "")
        .toolbar {
            // One group, not two separate `ToolbarItem`s: a toolbar item whose
            // content toggles between a button and nothing (the `if
            // document.isDirty`) is exactly the case where AppKit has been known
            // to mis-place `.primaryAction` items - which is what was pushing
            // both controls to the leading edge instead of trailing. Grouping
            // them keeps the layout stable across that conditional.
            ToolbarItemGroup(placement: .primaryAction) {
                // Always present, disabled when there is nothing to save, rather
                // than appearing and vanishing: a toolbar item that comes and
                // goes shifts the whole group's layout under it.
                Button(action: attemptSave) {
                    Label {
                        Text("Save")
                    } icon: {
                        SaveDiskIcon()
                            .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                            .frame(width: 15, height: 15)
                    }
                }
                .disabled(!document.isDirty)
                .help("Save changes to the file (\u{2318}S)")

                ModeToggle(mode: $settings.mode)
                    .disabled(document.url == nil)
            }
        }
        // Blend the toolbar into the page so it does not read as a separate bar.
        // Safe now that the window title is visible: it was hiding the *title*
        // that broke trailing placement, not hiding the background.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .windowConfiguration(isDocumentEdited: document.isDirty)
        .onChange(of: settings.sidebarVisible) { _, visible in
            columnVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, value in
            settings.sidebarVisible = (value != .detailOnly)
        }
        .alert(
            "This file changed on disk",
            isPresented: Binding(get: { conflictDate != nil }, set: { if !$0 { conflictDate = nil } })
        ) {
            Button("Overwrite", role: .destructive) {
                conflictDate = nil
                handle(document.forceSave())
            }
            Button("Reload from Disk") {
                conflictDate = nil
                try? document.revert()
            }
            Button("Cancel", role: .cancel) { conflictDate = nil }
        } message: {
            Text("Another program modified \(document.displayName) after you opened it. Overwriting replaces those changes with your version.")
        }
        .alert(
            "Could not save",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onChange(of: OpenInbox.shared.pending) { _, urls in
            guard !urls.isEmpty else { return }
            OpenInbox.shared.pending = []
            library.add(urls)
            if let first = urls.first,
               let item = library.items.first(where: { library.url(for: $0) == first }) {
                library.selection = item.id
                open(item)
            }
            // Debug capture only: show the states that require unsaved changes.
            if WindowCapture.request?.dirty == true {
                document.bufferDidChange(to: document.text + "\n")
            }
        }
        .onAppear {
            columnVisibility = settings.sidebarVisible ? .all : .detailOnly
            if let id = library.selection, let item = library.items.first(where: { $0.id == id }) {
                open(item)
            }
        }
        .focusedSceneValue(\.appActions, AppActions(
            openFiles: openPanel,
            save: attemptSave,
            toggleMode: settings.toggleMode,
            toggleSidebar: { settings.sidebarVisible.toggle() },
            canSave: document.isDirty,
            hasDocument: document.url != nil
        ))
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if document.url == nil {
            WelcomeView(onAdd: openPanel)
        } else {
            MarkdownTextPane(
                mode: settings.mode,
                content: content,
                measure: CGFloat(settings.measure),
                contentToken: token,
                onEdit: document.bufferDidChange,
                onToggleTask: toggleTask
            )
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    /// Preview renders the buffer, never a re-read of the file, so unsaved edits
    /// show up rendered and switching modes stays a view change.
    private var content: NSAttributedString {
        switch settings.mode {
        case .preview:
            return PreviewRenderer.render(document.text, face: settings.face)
        case .editor:
            return SourceHighlighter.highlight(document.text)
        }
    }

    /// Changes whenever the installed content should be replaced.
    private var token: String {
        let path = document.url?.path(percentEncoded: false) ?? "none"
        return "\(path)|\(settings.mode.rawValue)|\(settings.face.rawValue)|\(document.text.count)"
    }

    // MARK: Actions

    private func open(_ item: LibraryItem) {
        guard let url = library.url(for: item) else {
            library.refreshMissing()
            return
        }
        do {
            try document.open(url)
            if settings.alwaysOpenInPreview { settings.mode = .preview }
        } catch {
            saveError = "Could not open \(item.displayName): \(error.localizedDescription)"
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
        ]
        guard panel.runModal() == .OK else { return }
        library.add(panel.urls)
        if let first = panel.urls.first,
           let item = library.items.first(where: { library.url(for: $0) == first }) {
            library.selection = item.id
            open(item)
        }
    }

    /// Flips `[ ]` and `[x]` on one source line.
    ///
    /// This is an edit like any other: it goes through the buffer and marks the
    /// document dirty, so it still needs an explicit save. Preview stays
    /// incapable of writing to disk on its own.
    private func toggleTask(onLine line: Int) {
        var lines = document.text.components(separatedBy: "\n")
        let index = line - 1
        guard lines.indices.contains(index) else { return }

        let original = lines[index]
        guard let range = original.range(of: "[ ]") ?? original.range(of: "[x]")
            ?? original.range(of: "[X]")
        else { return }

        let checked = original[range] != "[ ]"
        lines[index] = original.replacingCharacters(in: range, with: checked ? "[ ]" : "[x]")
        document.bufferDidChange(to: lines.joined(separator: "\n"))
    }

    private func attemptSave() {
        handle(document.save())
    }

    private func handle(_ outcome: DocumentModel.SaveOutcome) {
        switch outcome {
        case .saved, .nothingToSave:
            break
        case .conflict(let onDisk):
            conflictDate = onDisk
        case .failed(let error):
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "doc.text")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No file open")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 22)

            Text("Add the markdown files scattered around your disk. They stay where they are; this only keeps a reference.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 8)

            Button("Add Files\u{2026}", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 24)

            Text("or drag them into the sidebar")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Mode toggle

/// The platform segmented control rather than a hand-drawn pill: it picks up the
/// Tahoe material and the accessibility behaviour for free, and text-only
/// segments are what the HIG supports.
struct ModeToggle: View {
    @Binding var mode: ViewMode

    var body: some View {
        Picker("View", selection: $mode) {
            Text("Preview").tag(ViewMode.preview)
            Text("Editor").tag(ViewMode.editor)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 148)
        .help("Switch between reading and editing (\u{2318}\u{21E7}P)")
    }
}

// MARK: - Window plumbing

/// Reaches the `NSWindow` for the one thing SwiftUI does not expose: the unsaved
/// dot in the close button.
///
/// An earlier version of this also hid the title and the toolbar background to
/// get a chromeless, floating look. That combination is what pushed the
/// Save/Editor controls to the leading edge instead of trailing: with no title
/// to anchor against, the toolbar had nothing to compute trailing space from.
/// A standard titlebar is worth more than the flourish.
private struct WindowConfiguration: NSViewRepresentable {
    let isDocumentEdited: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        FullScreenChrome.shared.startObservingFullScreen()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isDocumentEdited = isDocumentEdited
        }
    }

    /// Makes the toolbar auto-hide in fullscreen.
    ///
    /// macOS keeps a toolbar permanently visible in fullscreen; only a
    /// toolbar-less window auto-hides its titlebar. That permanent strip is the
    /// bar that sits at the top of the screen the whole time. Opting into
    /// `.autoHideToolbar` gets the standard behaviour instead: the chrome slides
    /// away and comes back when you push the pointer to the top edge.
    @MainActor
    final class FullScreenChrome {
        static let shared = FullScreenChrome()
        private var observing = false

        func startObservingFullScreen() {
            guard !observing else { return }
            observing = true

            NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    // `.autoHideToolbar` is only legal alongside `.fullScreen`.
                    NSApp.presentationOptions = [.fullScreen, .autoHideToolbar, .autoHideMenuBar]
                }
            }

            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    NSApp.presentationOptions = []
                }
            }
        }
    }
}

extension View {
    func windowConfiguration(isDocumentEdited: Bool) -> some View {
        background(WindowConfiguration(isDocumentEdited: isDocumentEdited).frame(width: 0, height: 0))
    }
}
