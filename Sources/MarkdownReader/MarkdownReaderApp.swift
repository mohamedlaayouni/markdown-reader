import SwiftUI
import UniformTypeIdentifiers

/// Actions the menu bar needs to reach into the focused window.
struct AppActions {
    var openFiles: () -> Void = {}
    var save: () -> Void = {}
    var toggleMode: () -> Void = {}
    var toggleSidebar: () -> Void = {}
    var canSave = false
    var hasDocument = false
}

private struct AppActionsKey: FocusedValueKey {
    typealias Value = AppActions
}

extension FocusedValues {
    var appActions: AppActions? {
        get { self[AppActionsKey.self] }
        set { self[AppActionsKey.self] = newValue }
    }
}

struct MarkdownReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @State private var settings = AppSettings()
    @State private var library = Library()
    @State private var document = DocumentModel()

    @FocusedValue(\.appActions) private var actions

    var body: some Scene {
        Window("Markdown Reader", id: "main") {
            RootView(settings: settings, library: library, document: document)
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open\u{2026}") { actions?.openFiles() }
                    .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") { actions?.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!(actions?.canSave ?? false))
            }

            // Items go INTO the standard View menu. Declaring
            // CommandMenu("View") creates a second one, which is the duplicate.
            CommandGroup(after: .sidebar) {
                Divider()

                // One command, both directions, bound in both modes. The
                // asymmetric version of this is the bug worth not shipping.
                Button("Toggle Preview / Editor") { actions?.toggleMode() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(!(actions?.hasDocument ?? false))

                Button("Toggle Sidebar") { actions?.toggleSidebar() }
                    .keyboardShortcut("\\", modifiers: .command)

                Divider()

                Button("Wider Text") {
                    settings.measure = min(settings.measure + 40, Double(Theme.measureRange.upperBound))
                }
                .keyboardShortcut("]", modifiers: [.command, .option])

                Button("Narrower Text") {
                    settings.measure = max(settings.measure - 40, Double(Theme.measureRange.lowerBound))
                }
                .keyboardShortcut("[", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(settings: settings)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}

/// Entry point. Intercepts the development render flag before SwiftUI starts,
/// so the app has one binary and no separate tooling target.
@main
struct Entry {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if let index = arguments.firstIndex(of: "--render-proof") {
            arguments.removeSubrange(...index)
            exit(MainActor.assumeIsolated { RenderProof.run(arguments: arguments) })
        }
        if arguments.first == "--render-icon", arguments.count > 1 {
            exit(MainActor.assumeIsolated { IconProof.run(outputPath: arguments[1]) })
        }
        if arguments.first == "--test-cursor" {
            exit(MainActor.assumeIsolated { CursorProof.run() })
        }
        MainActor.assumeIsolated {
            WindowCapture.request = WindowCapture.parse(arguments)
            if let file = WindowCapture.request?.file {
                OpenInbox.shared.pending = [file]
            }
        }
        MarkdownReaderApp.main()
    }
}
