import AppKit
import Observation

enum ViewMode: String {
    case preview, editor
}

/// The open file: its in-memory buffer, its dirty state, and the only code path
/// in the app that writes to disk.
///
/// Two invariants hold the design together:
///   1. Rendering never writes. Save and Save As are only ever called from
///      an explicit user action.
///   2. Preview renders `text` (the buffer), never a re-read of the file, so
///      unsaved edits appear rendered and switching modes is a view change.
@MainActor
@Observable
final class DocumentModel {

    /// The buffer. Source of truth for both modes.
    private(set) var text: String = ""
    private(set) var url: URL?
    private(set) var isDirty = false

    /// Modification date observed at the last read or write, used to notice a
    /// change made by another program before we overwrite it.
    private var lastKnownModification: Date?
    private var savedText = ""
    let undoManager = UndoManager()
    var externalChange = false
    var fileUnavailable = false
    var status = ""
    private(set) var revision = 0

    func confirmLeaving() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(displayName)?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveInteractively()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    @discardableResult
    func saveInteractively() -> Bool {
        switch save() {
        case .saved, .nothingToSave: return true
        case .failed(let error):
            let alert = NSAlert(error: error); alert.runModal(); return false
        case .conflict:
            let alert = NSAlert()
            alert.messageText = "This file changed on disk"
            alert.informativeText = "Overwrite the other version with your changes?"
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Overwrite")
            guard alert.runModal() == .alertSecondButtonReturn else { return false }
            switch forceSave() {
            case .saved: return true
            case .failed(let error): NSAlert(error: error).runModal(); return false
            default: return false
            }
        }
    }

    func checkExternalChanges() {
        guard let url else { return }
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else {
            fileUnavailable = true; return
        }
        fileUnavailable = false
        guard disk != savedText else { externalChange = false; return }
        if isDirty { externalChange = true; return }
        text = disk; savedText = disk; revision += 1
        undoManager.removeAllActions()
        lastKnownModification = Self.modificationDate(of: url)
        status = "Updated from disk"
    }

    var displayName: String { url?.lastPathComponent ?? "No file" }

    /// What the titlebar shows. Mirrors the AppKit convention.
    var windowSubtitle: String {
        guard url != nil else { return "" }
        return isDirty ? "\(displayName) — Edited" : displayName
    }

    // MARK: Reading

    func open(_ url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        undoManager.removeAllActions()
        savedText = contents
        revision += 1
        externalChange = false
        fileUnavailable = false
        status = ""
        self.text = contents
        self.url = url
        self.isDirty = false
        self.lastKnownModification = Self.modificationDate(of: url)
    }

    /// Discard the buffer and re-read from disk.
    func revert() throws {
        guard let url else { return }
        try open(url)
    }

    func close() {
        undoManager.removeAllActions()
        savedText = ""
        revision += 1
        externalChange = false
        fileUnavailable = false
        status = ""
        text = ""
        url = nil
        isDirty = false
        lastKnownModification = nil
    }

    // MARK: Editing

    /// Called by the text view as the user types. Does not touch the disk.
    func bufferDidChange(to newText: String) {
        guard newText != text else { return }
        let previous = text
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.bufferDidChange(to: previous) }
        }
        undoManager.setActionName("Edit Markdown")
        text = newText
        revision += 1
        isDirty = text != savedText
        status = ""
    }

    // MARK: Writing

    enum SaveOutcome {
        case saved
        case nothingToSave
        /// The file changed underneath us. The caller must ask the user before
        /// calling `forceSave()`.
        case conflict(onDisk: Date)
        case failed(Error)
    }

    /// Save As is authorized by the native save panel, including replacement
    /// confirmation. Keep source history so Undo remains useful after saving.
    func saveAs(to destination: URL) -> SaveOutcome {
        let outcome = write(to: destination)
        if case .saved = outcome { url = destination; revision += 1 }
        return outcome
    }

    /// Checks for an outside modification before saving the current file.
    func save() -> SaveOutcome {
        guard let url else { return .nothingToSave }
        guard isDirty else { return .nothingToSave }

        guard let disk = try? String(contentsOf: url, encoding: .utf8), disk == savedText else {
            return .conflict(onDisk: Self.modificationDate(of: url) ?? Date())
        }
        return write(to: url)
    }

    /// Save even though the file changed on disk. Only call after the user says so.
    func forceSave() -> SaveOutcome {
        guard let url else { return .nothingToSave }
        return write(to: url)
    }

    private func write(to url: URL) -> SaveOutcome {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            savedText = text
            externalChange = false
            fileUnavailable = false
            status = "Saved"
            lastKnownModification = Self.modificationDate(of: url)
            return .saved
        } catch {
            return .failed(error)
        }
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
