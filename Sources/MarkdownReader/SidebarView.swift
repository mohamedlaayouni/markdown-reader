import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Bindable var library: Library
    let onOpen: (LibraryItem) -> Void
    let onAdd: () -> Void
    var onRemove: (LibraryItem) -> Void = { _ in }
    var onLocate: (LibraryItem, URL) -> Void = { _, _ in }
    var revealed = true
    @State private var filter = ""
    @FocusState private var filterFocused: Bool

    private var visibleItems: [LibraryItem] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.items.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
    }

    var body: some View {
        List(selection: Binding(get: { library.selection }, set: { id in
            if let item = library.items.first(where: { $0.id == id }) { onOpen(item) }
        })) {
            ForEach(visibleItems) { item in
                HStack(spacing: 10) {
                    Image(systemName: library.isMissing(item) ? "doc.badge.ellipsis" : "doc.text")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.displayName).lineLimit(1).truncationMode(.middle)
                        Text(library.isMissing(item) ? "Moved or deleted" : item.displayPath)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                    }
                    Spacer(minLength: 0)
                    if library.isMissing(item) {
                        Button("Locate…") { locate(item) }.buttonStyle(.link)
                    }
                }
                .padding(.vertical, 5)
                .tag(item.id)
                .help(item.token)
                .contextMenu {
                    Button("Show in Finder") {
                        if let url = library.url(for: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }.disabled(library.isMissing(item))
                    Button("Locate…") { locate(item) }
                    Divider()
                    Button("Remove from Library") { onRemove(item) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 8) {
            VStack(spacing: 10) {
                HStack {
                    Text("Library").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Files…", systemImage: "plus", action: onAdd)
                        .labelStyle(.iconOnly).buttonStyle(LibraryAddButtonStyle())
                        .help("Add Markdown files (⌘O)")
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Filter files", text: $filter, prompt: Text("Filter files").foregroundStyle(filterFocused ? Color.black.opacity(0.5) : Color.secondary)).textFieldStyle(.plain)
                        .accessibilityLabel("Filter library files")
                        .focused($filterFocused)
                        .foregroundStyle(filterFocused ? Color.black.opacity(0.85) : Color.primary)
                    if !filter.isEmpty {
                        Button("Clear filter", systemImage: "xmark.circle.fill") { filter = "" }
                            .labelStyle(.iconOnly).buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(filterFocused ? Color(red: 1, green: 0.985, blue: 0.95) : Color(nsColor: .quaternaryLabelColor))
                }
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(filterFocused ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1) }
                .foregroundStyle(filterFocused ? Color.black.opacity(0.6) : Color.secondary)
            }.padding(.horizontal, 14).padding(.top, 8)
        }
        .overlay {
            if visibleItems.isEmpty {
                VStack(spacing: 8) {
                    Text(filter.isEmpty ? "Your library is empty" : "No matching files").font(.headline)
                    if filter.isEmpty { Button("Add Files…", action: onAdd) }
                    else { Button("Clear Filter") { filter = "" } }
                }.padding().multilineTextAlignment(.center)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Drop Markdown files here to add them")
                .font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls)
            if let item = library.items.first(where: { $0.token == urls.first?.path }) { onOpen(item) }
            return urls.contains { ["md", "markdown", "mdown"].contains($0.pathExtension.lowercased()) }
        }
    }

    private func locate(_ item: LibraryItem) {
        let panel = NSOpenPanel()
        panel.message = "Find \(item.displayName)"
        panel.allowedContentTypes = ["md", "markdown", "mdown"].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onLocate(item, url)
    }
}

/// Fixed hit target with visible hover and press feedback, including reduced motion.
private struct LibraryAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Feedback(configuration: configuration)
    }
    private struct Feedback: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .frame(width: 30, height: 30)
                .background(.primary.opacity(configuration.isPressed ? 0.18 : hovered ? 0.09 : 0), in: Circle())
                .contentShape(Circle())
                .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.92 : hovered ? 1.1 : 1)
                .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
                .animation(reduceMotion ? nil : Motion.hover, value: hovered)
                .onHover { hovered = $0 }
        }
    }
}
