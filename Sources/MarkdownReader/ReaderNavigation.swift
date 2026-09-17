import AppKit
import Markdown
import SwiftUI

struct DocumentHeading: Identifiable {
    let line: Int
    let level: Int
    let title: String
    var id: Int { line }
}

enum DocumentStructure {
    static func headings(_ source: String) -> [DocumentHeading] {
        var result: [DocumentHeading] = []
        func walk(_ node: Markup) {
            if let heading = node as? Heading {
                result.append(DocumentHeading(line: heading.range?.lowerBound.line ?? 1, level: heading.level, title: heading.plainText))
            }
            for child in node.children { walk(child) }
        }
        walk(Document(parsing: source))
        return result
    }
    static func slug(_ title: String) -> String {
        title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }.replacingOccurrences(of: " ", with: "-")
    }
}

@MainActor @Observable
final class ReaderNavigation {
    var jumpLine: Int?
    var jumpID = UUID()
    var findAction: Int?
    var findID = UUID()
    func jump(to line: Int) { jumpLine = line; jumpID = UUID() }
    func find(_ action: NSTextFinder.Action) { findAction = action.rawValue; findID = UUID() }
}

struct QuickOpenView: View {
    let items: [LibraryItem]
    let open: (LibraryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: UUID?
    @FocusState private var focused: Bool
    private var matches: [LibraryItem] {
        items.filter { query.isEmpty || $0.displayName.localizedStandardContains(query) || $0.displayPath.localizedStandardContains(query) }
    }
    private func choose() {
        if let item = matches.first(where: { $0.id == selection }) ?? matches.first { dismiss(); open(item) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Open").font(.title2.bold())
            TextField("Search files by name or location", text: $query)
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(choose)
                .onMoveCommand { direction in
                    let index = matches.firstIndex(where: { $0.id == selection }) ?? 0
                    if !matches.isEmpty {
                        selection = matches[min(max(index + (direction == .up ? -1 : 1), 0), matches.count - 1)].id
                    }
                }
            List(matches, selection: $selection) { item in
                VStack(alignment: .leading) {
                    Text(item.displayName)
                    Text(item.displayPath).font(.caption).foregroundStyle(.secondary)
                }.tag(item.id).contentShape(Rectangle()).onTapGesture(count: 2) { selection = item.id; choose() }
            }
            .overlay { if matches.isEmpty { Text("No matching files").foregroundStyle(.secondary) } }
            HStack {
                Text("↑ ↓ to choose · Return to open").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open", action: choose).keyboardShortcut(.defaultAction).disabled(matches.isEmpty)
            }
        }.padding(20).frame(width: 500, height: 360)
            .onAppear { focused = true; selection = matches.first?.id }
            .onChange(of: query) { selection = matches.first?.id }
    }
}
