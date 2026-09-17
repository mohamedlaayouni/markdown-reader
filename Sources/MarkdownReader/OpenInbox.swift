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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            WindowCapture.runIfRequested()
        }
    }
}
