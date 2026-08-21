import SwiftUI
import UniformTypeIdentifiers

/// The library. Holds references to markdown files wherever they live; it never
/// copies or moves them.
struct SidebarView: View {
    @Bindable var library: Library
    let onOpen: (LibraryItem) -> Void
    let onAdd: () -> Void

    var body: some View {
        List(selection: Binding(
            get: { library.selection },
            set: { newValue in
                library.selection = newValue
                if let id = newValue, let item = library.items.first(where: { $0.id == id }) {
                    onOpen(item)
                }
            }
        )) {
            Section {
                ForEach(library.items) { item in
                    row(item)
                        .tag(item.id)
                        .contextMenu {
                            Button("Show in Finder") { revealInFinder(item) }
                                .disabled(library.isMissing(item))
                            Button("Locate\u{2026}") { locate(item) }
                            Divider()
                            Button("Remove from Library") { library.remove(item.id) }
                        }
                }
            } header: {
                HStack {
                    Text("Library")
                        .font(.system(size: 16.5, weight: .semibold))
                    Spacer()
                    // `.bordered` + `.circle` is the same construction the
                    // toolbar's Save button renders with, so the two match
                    // instead of one being a rounded square and the other a
                    // circle. `.accessoryBar` was the wrong family - it draws a
                    // squarish hover chrome.
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    // A bordered button draws its border at its own bounds, so
                    // without this it sits visibly tighter to the sidebar's
                    // trailing edge than the file rows below it do. The previous
                    // borderless glyph had slack inside a larger frame and did
                    // not need it.
                    .padding(.trailing, 6)
                    .help("Add markdown files\u{2026}")
                }
                .padding(.bottom, 16)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("Drop .md files here to add them")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls)
            return true
        }
    }

    @ViewBuilder
    private func row(_ item: LibraryItem) -> some View {
        let missing = library.isMissing(item)
        HStack(spacing: 8) {
            Circle()
                .fill(missing ? Color.orange : Color.accentColor)
                .frame(width: 4, height: 4)
                .opacity(missing || library.selection == item.id ? 1 : 0)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12.5, weight: library.selection == item.id ? .medium : .regular))
                    .foregroundStyle(missing ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                // The path is not decoration: loose files in ~/Downloads and
                // ~/Desktop are only distinguishable by where they live.
                Text(missing ? "Moved or deleted" : item.displayPath)
                    .font(.system(size: 10.5))
                    .foregroundStyle(missing ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 0)

            if missing {
                Button("Locate") { locate(item) }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5, weight: .medium))
            }
        }
        .padding(.vertical, 2)
    }

    private func revealInFinder(_ item: LibraryItem) {
        guard let url = library.url(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Re-point a moved file, keeping its place in the list. Silently dropping
    /// the row would lose a reference the user deliberately added.
    private func locate(_ item: LibraryItem) {
        let panel = NSOpenPanel()
        panel.message = "Find \(item.displayName)"
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.relocate(item.id, to: url)
    }
}
