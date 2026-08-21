# Markdown Reader

A minimalist, native Swift markdown reader for macOS. It reads first, edits
second: documents open in Preview, and Editor is one click away when you need
it.

## Why

Most markdown apps on the Mac are Electron wrapped around a web view, or a
full-blown editor with reading bolted on as an afterthought. This is the
opposite: one native `NSTextView` (TextKit 2) that serves both a rendered
preview and a syntax-highlighted source view, so switching between them is
instant and never touches disk on its own.

## Features

- **Preview and Editor share one text engine.** No separate view swap, no lost
  scroll position, one implementation of Find/selection/Writing Tools.
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
- Fullscreen behaves like a native Mac app: the toolbar auto-hides and
  returns at the top edge.

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

Requires macOS 26 (Tahoe) or later.

## Architecture

- **Parsing**: [swift-markdown](https://github.com/swiftlang/swift-markdown)
  (Apple's official package, wrapping their cmark-gfm fork) - spec-correct
  GitHub-flavored markdown.
- **Rendering**: a `MarkupVisitor` walks the parsed AST directly into an
  `NSAttributedString`, rather than through a SwiftUI view tree. Block
  decorations that attributed strings can't express on their own (code block
  backgrounds, horizontal rules) are painted directly by the text view.
- **Editing**: the same attributed string, re-highlighted incrementally
  (line-oriented, not a full document re-parse) as you type.
- **Persistence**: the library stores plain file paths. The app is
  intentionally unsandboxed - see [`Library.swift`](Sources/MarkdownReader/Library.swift)
  for the `FileRefStore` protocol this sits behind, which is the seam you'd
  use to switch to security-scoped bookmarks if you ever wanted App Sandbox
  or Mac App Store distribution.

## License

[PolyForm Noncommercial 1.0.0](LICENSE). Free to use, modify, and share -
commercial use is not permitted. See the LICENSE file for the exact terms.
