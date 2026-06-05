# Changelog

All notable changes to Snippy are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
