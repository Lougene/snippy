# Changelog

All notable changes to **Snippy by Lever** — a free productivity tool from
[Lever Automation Consulting](https://www.getlever.com.au) — are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] — 2026-07-15

### Fixed
- **Mangled expansions in slow apps (WhatsApp, Slack, other Electron apps).**
  A trigger could paste a garbled result — leftover trigger characters plus a
  truncated snippet (e.g. `;tm` producing `;tThanks for reaching ou`). Electron
  apps process synthetic keystrokes on a throttled input queue, so the paste
  raced ahead of the backspaces that clear the trigger, and the late backspaces
  chewed characters off the end of the inserted text. Snippy now paces the
  deletions and waits for them to be applied before pasting, with the delay
  scaling to the trigger length, so the trigger is always fully cleared first.
- **Clipboard-restore race** that could paste the *previous* clipboard contents
  instead of the snippet. (Fixed on `main` after v1.1.0; first shipped here.)

## [1.1.0] — 2026-06-19

### Added
- **Inline formatting toolbar** above each snippet editor — bold, italic,
  underline, strikethrough, font size, text color, alignment (left/center/right/
  justify), and bullet/numbered lists. Buttons highlight to reflect the
  formatting at the cursor.
- **About section** in Settings, with a link to
  [getlever.com.au](https://www.getlever.com.au).

### Changed
- Rebranded to **Snippy by Lever** — a free productivity tool from
  Lever Automation Consulting. Window titles, menu items, copyright, and
  documentation updated accordingly. Bundle ID, file paths, and library
  format are unchanged; existing installs upgrade in place.

### Fixed
- The macOS NSTextView inspector bar (the old floating font/size/alignment
  toolbar) was leaking to the top of the library window, appearing above the
  snippet list instead of next to its editor. It is now disabled — the new
  inline SwiftUI toolbar takes its place.

## [1.0.0] — 2026-06-05

First public release.

### Features
- Menu-bar text expander for macOS 14+. Watches your keystrokes and replaces
  abbreviations with snippets.
- Rich-text snippets with inline images.
- Groups for organizing snippets, with per-group and per-snippet enable toggles.
- Three trigger modes: *Auto-expand*, *Require Tab/Space*, or *Inherit* — settable
  globally, per group, or per snippet.
- **Override formatting** toggle per snippet (default off). When off, paste uses
  the destination's font, size, and color so snippets blend into emails and other
  styled fields. Bullet and numbered list structure is preserved as text markers.
- **macOS Text Replacement integration**: Snippy detects abbreviations that
  collide with macOS's built-in Text Replacements and takes precedence cleanly
  (no more racing the system). The editor shows a warning when a collision is
  detected.
- Sync-friendly storage: the entire library is a single `snippy-library.json`
  file. Point it at a folder inside iCloud Drive, Dropbox, etc.
- Pasteboard preserved: your clipboard contents are restored after every
  expansion.

### Privacy
- No network requests. Ever.
- The library is stored as plain JSON in a folder you choose.
- Snippy requires Accessibility permission to observe keystrokes — granted in
  System Settings → Privacy & Security → Accessibility.
