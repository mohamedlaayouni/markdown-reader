import AppKit
import Observation
import SwiftUI

/// Files handed to the app from outside: Finder double-click, "Open With", or a
/// drag onto the Dock icon. The delegate drops them here and the window picks
/// them up, which keeps the delegate free of any model wiring.
@MainActor
@Observable
final class OpenInbox {
    static let shared = OpenInbox()
    var pending: [URL] = []
    private init() {}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var confirmTermination: (() -> Bool)?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.confirmTermination?() == false ? .terminateCancel : .terminateNow
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            OpenInbox.shared.pending.append(contentsOf: urls)
        }
    }

    /// Takes the open-documents Apple event before SwiftUI does. Left to itself,
    /// SwiftUI's own handler looks for a scene to hand the file to and, finding
    /// none for a single `Window`, closes that window - and with it the app,
    /// since the last window closing quits. Opening a file while the app was
    /// already running therefore looked like a crash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments))
    }

    @objc private func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let direct = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
        let items = direct.numberOfItems > 0 ? (1...direct.numberOfItems).compactMap { direct.atIndex($0) } : [direct]
        let urls = items.compactMap(\.fileURLValue)
        guard !urls.isEmpty else { return }
        MainActor.assumeIsolated {
            OpenInbox.shared.pending.append(contentsOf: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            WindowCapture.runIfRequested()
        }
    }
}
