# Reader design and interaction principles

The reader follows Apple's Human Interface Guidelines with reading comfort,
user control, and continuity as the priorities. Liquid Glass belongs to the
navigation and control layer; document text uses a stable, readable surface.
Standard SwiftUI and AppKit controls provide system materials, keyboard behavior,
focus, and accessibility adaptations.

## Acceptance criteria

- Never replace a dirty document without Save / Discard / Cancel. Failed or
  cancelled saves keep the original document active. Closing and quitting use
  the same guard. External changes never overwrite an unsaved buffer.
- Undo and redo operate on Markdown source, including task toggles, independently
  of the active viewing mode. Returning to the saved contents clears Edited.
- Find, Quick Open, and reading size have menu
  commands and keyboard shortcuts.
- Store the visible source line for each file; restore by source location across
  files and viewing modes. Window frame, sidebar width, and reading preferences
  persist.
- Native selection is visible in light and dark appearances. Metadata remains
  readable. Controls have accessible labels, native selection semantics, and
  keyboard interaction. Task toggles expose accessibility custom actions.
- Use brief system transitions. Honor Reduce Motion. Avoid decorative repeated
  movement during reading. Let system controls adapt to Reduce Transparency and
  increased contrast.
- Load images asynchronously with alt-text captions and failure states. Keep
  image dimensions inside the reading column. Retry is available in View.
- Resolve local document links relative to the source document. Provide familiar
  copy-link and copy-code actions and unobtrusive feedback.

## Sources

- [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion)
- [Feedback](https://developer.apple.com/design/human-interface-guidelines/feedback)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Feature choices and reading presets are this app's interpretation of the HIG,
not a list of features mandated by Apple.


## Interaction refinements

Preview/Editor occupies the center of the toolbar. The folder menu and its Copy File Path action have been removed; standard file commands remain in the menu bar. The library Add control has a fixed hit target, hover growth, and a pressed state. Reduced Motion retains color feedback without scaling. The focused library filter uses a cream background and dark text in either appearance.

Preview links keep their underline, show a hand cursor and hover/press highlights. Clicks are intercepted by the app, which resolves relative `.md` links and anchors itself; feedback indicates that the link was handed to its handler, not that a remote page finished loading.

Checkboxes are real controls: a click flips the box in place and posts the source line to the app, which edits the buffer. Same-document content refreshes preserve the scroll offset; a document switch restores the remembered line. Reading-position writes are debounced. Preview typography and width change live through CSS variables without a re-render.


Custom controls share SwiftUI's built-in `Animation.smooth` springs: 0.18 seconds for hover/press feedback and 0.28 seconds for programmatic sidebar transitions. System controls keep their native animations. Reduce Motion suppresses custom movement. Split-view geometry is observed locally and propagated only after settling; native sidebar changes are not echoed into a second visibility transaction. These choices govern motion behavior, not a guaranteed frame rate.
