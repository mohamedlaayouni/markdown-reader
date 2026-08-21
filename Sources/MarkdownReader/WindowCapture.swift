import AppKit
import SwiftUI

/// Development tool: has the app photograph its own window and quit.
///
/// This exists because screen-recording permission is per-app and may simply not
/// be available to whatever shell is driving a build. A process is always allowed
/// to draw its *own* view hierarchy into a bitmap, so this needs no TCC grant at
/// all - and unlike an offscreen render of just the text, it captures the real
/// titlebar, toolbar and sidebar as the window manager laid them out.
///
///     Markdown\ Reader --capture-window <out.png> [--file <md>] [--fullscreen] [--dirty]
@MainActor
enum WindowCapture {
    struct Request {
        var outputPath: String
        var file: URL?
        var fullscreen = false
        /// Force out of fullscreen first - macOS restores the last state, which
        /// may not be the one being investigated.
        var windowed = false
        /// Print the titlebar/toolbar view tree with frames, to find chrome that
        /// is present but shouldn't be.
        var dumpChrome = false
        /// Mark the buffer edited, so state that only appears when there are
        /// unsaved changes (the enabled Save button, the titlebar's "Edited")
        /// is visible in the capture.
        var dirty = false
    }

    static var request: Request?

    /// Parses the capture flags, returning nil when the app should launch normally.
    static func parse(_ arguments: [String]) -> Request? {
        guard let index = arguments.firstIndex(of: "--capture-window"),
              index + 1 < arguments.count
        else { return nil }

        var request = Request(outputPath: arguments[index + 1])
        if let fileIndex = arguments.firstIndex(of: "--file"), fileIndex + 1 < arguments.count {
            request.file = URL(filePath: arguments[fileIndex + 1])
        }
        request.fullscreen = arguments.contains("--fullscreen")
        request.windowed = arguments.contains("--windowed")
        request.dirty = arguments.contains("--dirty")
        request.dumpChrome = arguments.contains("--dump-chrome")
        return request
    }

    /// Called once the scene exists. Waits for layout (and the fullscreen
    /// animation, when asked) before capturing.
    static func runIfRequested() {
        guard let request else { return }

        let settle: TimeInterval = (request.fullscreen || request.windowed) ? 3.0 : 1.4

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && $0.contentView != nil }) else {
                finish(1, "no visible window to capture")
                return
            }
            if request.fullscreen, !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            if request.windowed, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                if request.dumpChrome { dump(window: window) }
                capture(window: window, to: request.outputPath)
            }
        }
    }

    /// Walks the window's whole view tree, flagging anything that occupies a
    /// horizontal strip at the top - which is what a stray bar looks like.
    private static func dump(window: NSWindow) {
        print("--- window ---")
        print("styleMask.fullScreen: \(window.styleMask.contains(.fullScreen))")
        print("titleVisibility: \(window.titleVisibility.rawValue), transparent: \(window.titlebarAppearsTransparent)")
        print("toolbar: \(window.toolbar.map { "\($0.identifier) visible=\($0.isVisible)" } ?? "none")")
        print("toolbarStyle: \(window.toolbarStyle.rawValue)")
        let opts = NSApp.presentationOptions
        print("presentationOptions raw: \(opts.rawValue)")
        print("  .fullScreen: \(opts.contains(.fullScreen))")
        print("  .autoHideToolbar: \(opts.contains(.autoHideToolbar))")
        print("  .autoHideMenuBar: \(opts.contains(.autoHideMenuBar))")
        print("frame: \(window.frame)")
        if let content = window.contentView {
            print("contentView frame: \(content.frame)")
            walk(content.superview ?? content, depth: 0, windowHeight: window.frame.height)
        }
        print("--- end ---")
    }

    private static func walk(_ view: NSView, depth: Int, windowHeight: CGFloat) {
        let indent = String(repeating: "  ", count: depth)
        let f = view.frame
        // A "bar" = wide, short, and parked at the top of the window.
        let isTopStrip = f.height > 0 && f.height < 120 && f.width > windowHeight * 0.4
            && (f.maxY > windowHeight - 140)
        let marker = isTopStrip ? "   <== TOP STRIP" : ""
        print("\(indent)\(type(of: view)) frame=\(f) hidden=\(view.isHidden) alpha=\(view.alphaValue)\(marker)")
        for sub in view.subviews where depth < 4 {
            walk(sub, depth: depth + 1, windowHeight: windowHeight)
        }
    }

    private static func capture(window: NSWindow, to path: String) {
        // The titlebar and toolbar live in the frame view, NOT in contentView -
        // capturing contentView alone would miss exactly the chrome we want to
        // inspect. contentView.superview is that frame view.
        guard let content = window.contentView else {
            finish(1, "window has no content view")
            return
        }
        let target = content.superview ?? content

        target.layoutSubtreeIfNeeded()
        target.display()

        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
            finish(1, "cannot allocate bitmap")
            return
        }
        target.cacheDisplay(in: target.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            finish(1, "cannot encode png")
            return
        }
        do {
            try data.write(to: URL(filePath: path))
        } catch {
            finish(1, "cannot write \(path): \(error)")
            return
        }

        let fullscreen = window.styleMask.contains(.fullScreen)
        print("captured \(Int(target.bounds.width))x\(Int(target.bounds.height))"
            + (fullscreen ? " [fullscreen]" : " [windowed]")
            + " -> \(path)")
        finish(0, nil)
    }

    private static func finish(_ code: Int32, _ message: String?) {
        if let message {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        NSApplication.shared.terminate(nil)
        exit(code)
    }
}
