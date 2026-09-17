# Markdown Reader

A minimalist, native Swift markdown reader for macOS. It reads first, edits
second: documents open in Preview, and Editor is one click away when you need
it.

## Why

Most markdown apps on the Mac are Electron wrapped around a web view, or a
full-blown editor with reading bolted on as an afterthought. This is the
opposite: a native app whose preview is a single `WKWebView` driven by
swift-markdown, and whose editor is a TextKit 2 `NSTextView`. The two share
source lines as their coordinate, so switching between them keeps your place
and never touches disk on its own.

## Features

- **Preview and Editor share a coordinate, not a view.** The preview reports
  the source line at the top of the viewport; the editor opens there, and vice
  versa. Reading position is remembered per document.
- **Preview never writes.** Only an explicit Save (⌘S) touches the file on
  disk - switching modes, even repeatedly, can never silently rewrite your
  markdown out from under you.
- **A library, not a file browser.** Add loose `.md` files from anywhere on
  disk; the sidebar remembers them by reference, not by copying them
  anywhere.
- **Clickable task-list checkboxes**, GFM tables, fenced and indented code
  blocks, blockquotes, and nested lists.
- **Appearance, typeface, and reading width** are all user preferences,
  persisted across launches.
- Native Liquid Glass toolbar, accessible sidebar filtering, and system Settings controls.
- Find (⌘F), next/previous matches (⌘G / ⌘⇧G), and Quick Open (⌘K).
- Adjustable text size (⌘+ / ⌘−), and Comfort, Book, and Technical presets.
- Reading position, window frame, sidebar width, and the last document persist.
- Source-based Undo/Redo also works after switching modes and for task checkboxes.
- Save / Discard / Cancel protects edits when opening another file, closing, or quitting.
- External file updates refresh clean documents and display a conflict banner for dirty documents.
- Inline local and remote images, alt-text captions, failure states, and View → Reload Images.
- Relative Markdown links, copy-link context menus, and code-block copy actions.
- Native document location menu, Show in Finder, and Save As (⌘⇧S).
- Full screen keeps navigation accessible; Toggle Sidebar (⌘\\) hides the library.

## Building

No Xcode required - this builds with the Swift toolchain that ships with
Xcode's Command Line Tools.

```bash
git clone https://github.com/mohamedlaayouni/markdown-reader.git
cd markdown-reader
./Packaging/build-app.sh --install
```

That compiles a release build, assembles `Markdown Reader.app` (icon,
`Info.plist`, ad-hoc code signature), and installs it to `/Applications`.
Drop `--install` to just build into `dist/`, or add `--dmg` to also produce a
disk image.

Requires macOS 26 (Tahoe) or later. The build script prefers the installed 26.5
SDK to avoid incomplete SwiftUI macro support in beta SDKs. Set `READER_SDK`
to override it.

## Verification

```bash
./Packaging/test.sh
```

Regression tests cover undo, saved-state tracking, Save As, external changes,
missing files, line mapping, relative and unsafe links, code copying, task
checkboxes, tables, images, headings, and avoiding full rendering passes while
typing.
See [DESIGN.md](DESIGN.md) for the Apple HIG rationale and acceptance criteria.

## Architecture

- **Parsing**: [swift-markdown](https://github.com/swiftlang/swift-markdown)
  (Apple's official package, wrapping their cmark-gfm fork) - spec-correct
  GitHub-flavored markdown.
- **Rendering**: [`HTMLRenderer`](Sources/MarkdownReader/HTMLRenderer.swift),
  a `MarkupVisitor` that walks the parsed AST into HTML with a `data-line` on
  every block. [`PreviewWebPane`](Sources/MarkdownReader/PreviewWebPane.swift)
  loads [`PreviewPage`](Sources/MarkdownReader/PreviewPage.swift) (compiled-in
  CSS and a small script) once, then swaps content in place, so there is no
  flash and scroll state survives. Code grounds, checkboxes, table rules and
  link affordances are plain CSS. Local images are served through a custom
  `mdimg:` scheme; nothing else from the document reaches the page unescaped.
- **Editing**: a syntax-highlighted attributed string, re-highlighted
  incrementally (line-oriented, not a full document re-parse) as you type.
- **Persistence**: the library stores plain file paths. The app is
  intentionally unsandboxed - see [`Library.swift`](Sources/MarkdownReader/Library.swift)
  for the `FileRefStore` protocol this sits behind, which is the seam you'd
  use to switch to security-scoped bookmarks if you ever wanted App Sandbox
  or Mac App Store distribution.

## License

[PolyForm Noncommercial 1.0.0](LICENSE). Free to use, modify, and share -
commercial use is not permitted. See the LICENSE file for the exact terms.
