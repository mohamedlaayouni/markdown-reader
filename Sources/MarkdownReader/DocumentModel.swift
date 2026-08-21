import Foundation
import Observation

enum ViewMode: String {
    case preview, editor
}

/// The open file: its in-memory buffer, its dirty state, and the only code path
/// in the app that writes to disk.
///
/// Two invariants hold the design together:
///   1. Rendering never writes. `save()` is the sole writer and is only ever
///      called from an explicit user action.
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

    var displayName: String { url?.lastPathComponent ?? "No file" }

    /// What the titlebar shows. Mirrors the AppKit convention.
    var windowSubtitle: String {
        guard url != nil else { return "" }
        return isDirty ? "\(displayName) — Edited" : displayName
    }

    // MARK: Reading

    func open(_ url: URL) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
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
        text = ""
        url = nil
        isDirty = false
        lastKnownModification = nil
    }

    // MARK: Editing

    /// Called by the text view as the user types. Does not touch the disk.
    func bufferDidChange(to newText: String) {
        guard newText != text else { return }
        text = newText
        isDirty = true
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

    /// The only writer. Checks for an outside modification first.
    func save() -> SaveOutcome {
        guard let url else { return .nothingToSave }
        guard isDirty else { return .nothingToSave }

        let current = Self.modificationDate(of: url)
        if let current, let known = lastKnownModification, current > known {
            return .conflict(onDisk: current)
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
