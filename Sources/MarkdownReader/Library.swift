import Foundation
import Observation

/// How a file reference is turned into a usable URL.
///
/// The app is unsandboxed, so a plain path round-trips fine. This sits behind a
/// protocol anyway: enabling the App Sandbox later means writing one more
/// conformance that stores `bookmarkData(options: [.withSecurityScope])` and
/// balances `startAccessingSecurityScopedResource()`, with nothing above this
/// line needing to change.
protocol FileRefStore: Sendable {
    /// Opaque token persisted in the library file.
    func token(for url: URL) throws -> String
    /// Resolve a token back to a URL, or nil if it no longer points anywhere.
    func resolve(_ token: String) -> URL?
    /// Called when the app is done reading/writing. A no-op for plain paths.
    func relinquish(_ url: URL)
}

struct PathStore: FileRefStore {
    func token(for url: URL) throws -> String { url.path(percentEncoded: false) }

    func resolve(_ token: String) -> URL? {
        let url = URL(filePath: token)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func relinquish(_ url: URL) {}
}

/// One entry in the sidebar.
struct LibraryItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Store token, opaque by design - see `FileRefStore`.
    var token: String
    /// Cached for display so a missing file still shows a name and location.
    var displayName: String
    var displayPath: String

    init(id: UUID = UUID(), token: String, displayName: String, displayPath: String) {
        self.id = id
        self.token = token
        self.displayName = displayName
        self.displayPath = displayPath
    }
}

@MainActor
@Observable
final class Library {
    private(set) var items: [LibraryItem] = []
    /// Ids whose token no longer resolves. Rows stay visible and offer Locate;
    /// dropping them silently would lose the reference the user added.
    private(set) var missing: Set<UUID> = []
    var selection: UUID? {
        didSet { UserDefaults.standard.set(selection?.uuidString, forKey: "selectedDocument") }
    }

    private let store: FileRefStore
    private let fileURL: URL

    init(store: FileRefStore = PathStore()) {
        self.store = store
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MarkdownReader", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        self.fileURL = support.appending(path: "library.json")
        load()
    }

    // MARK: Mutation

    func add(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "md"
            || url.pathExtension.lowercased() == "markdown"
            || url.pathExtension.lowercased() == "mdown" {
            guard let token = try? store.token(for: url) else { continue }
            guard !items.contains(where: { $0.token == token }) else { continue }
            items.append(
                LibraryItem(
                    token: token,
                    displayName: url.lastPathComponent,
                    displayPath: Self.abbreviate(url.deletingLastPathComponent())
                )
            )
        }
        refreshMissing()
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        missing.remove(id)
        if selection == id { selection = items.first?.id }
        save()
    }

    /// Re-point an entry whose file moved, keeping its position in the list.
    func relocate(_ id: UUID, to url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let token = try? store.token(for: url) else { return }
        items[index].token = token
        items[index].displayName = url.lastPathComponent
        items[index].displayPath = Self.abbreviate(url.deletingLastPathComponent())
        missing.remove(id)
        save()
    }

    // MARK: Resolution

    func url(for item: LibraryItem) -> URL? { store.resolve(item.token) }

    func relinquish(_ url: URL) { store.relinquish(url) }

    /// Cheap existence sweep. Called on launch and after the app reactivates,
    /// not on every render.
    func refreshMissing() {
        var gone: Set<UUID> = []
        for item in items where store.resolve(item.token) == nil {
            gone.insert(item.id)
        }
        missing = gone
    }

    func isMissing(_ item: LibraryItem) -> Bool { missing.contains(item.id) }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([LibraryItem].self, from: data)
        else { return }
        items = decoded
        refreshMissing()
        let remembered = UserDefaults.standard.string(forKey: "selectedDocument").flatMap(UUID.init(uuidString:))
        selection = items.first(where: { $0.id == remembered && !missing.contains($0.id) })?.id ?? items.first(where: { !missing.contains($0.id) })?.id
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func abbreviate(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if path == home { return "~" }
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
