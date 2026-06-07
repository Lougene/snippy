# Snippy

A native macOS text expander. Lives in your menu bar, watches your keystrokes,
and replaces abbreviations with snippets you've defined — plain text, rich text,
or images.

<!-- TODO: replace with a real screenshot before v1.0.0 release -->
<!-- ![Snippy library window](docs/screenshot.png) -->

## Download

Latest release: **[github.com/Lougene/snippy/releases/latest](https://github.com/Lougene/snippy/releases/latest)**

Download `Snippy-x.y.z.dmg`, open it, and drag **Snippy** to **Applications**.

Requires **macOS 14 (Sonoma) or later**.

## First launch

1. Open **Snippy** from `/Applications` or Launchpad. It lives in the menu bar
   (look for the cursor icon near your clock — Snippy has no Dock icon).
2. On first launch Snippy asks for **Accessibility** permission, which it needs
   to watch your keystrokes. Click the prompt's link to open
   *System Settings → Privacy & Security → Accessibility* and toggle Snippy on.
3. Open the library from the menu bar → *Open Library…* and start adding snippets.

That's it.

## What it does

- **Snippets** — give each one a name, an abbreviation (e.g. `;sig`, `;addr`),
  and a content body. Rich text and inline images are supported.
- **Groups** — organize snippets into groups; toggle whole groups on or off.
- **Trigger styles** — *Auto-expand* (fires the instant you finish typing the
  abbreviation) or *Require Tab/Space* (waits for you to confirm with a
  terminator). Set globally, per group, or per snippet.
- **Override formatting** *(per snippet, default off)* — when off, snippets
  paste in the **destination's** font and size, so pasting into Mail keeps
  Mail's text style. Bullet points and numbered lists survive as text markers.
  Turn this on for snippets where you want Snippy's exact formatting (signatures
  with logos, fancy boilerplate, etc.).
- **Plays nicely with macOS Text Replacements** — when an abbreviation collides
  with one of your built-in System Settings replacements, Snippy takes
  precedence cleanly (no more racing the system). The editor warns you about
  collisions so you can rename if you'd rather macOS handle it.
- **Your clipboard is preserved** — Snippy temporarily uses the clipboard to
  paste, then restores whatever you had on it.

## Using Snippy

Once installed and Accessibility-granted, the loop is three steps:

1. **Open the library.** Menu bar → *Open Library*. Groups on the left, snippets in the middle, editor on the right.
2. **Create a snippet.** Click *+* at the bottom of the snippet list. Give it a memorable abbreviation (e.g. `;sig`) and the content to paste. It saves automatically.
3. **Type it anywhere.** Switch to any text field and type the abbreviation — Snippy detects it and pastes your content.

### Tips that pay off

- **Prefix abbreviations with a sigil** like `;` or `\`. `;sig` never collides with real words; `sig` could fire inside "design".
- **Pick a trigger style** per snippet. *Auto-expand* fires the instant the abbreviation is typed — best with sigils. *Require Tab/Space* waits for a space or tab — best for word-like abbreviations.
- **Override formatting** is off by default, so snippets paste in the destination's font and size (bullets and lists survive as text markers). Turn it on per-snippet for rich signatures or content you want pixel-perfect.
- **Group snippets** by context — work, personal, a specific client. Toggle whole groups off when they don't apply.
- **Watch for collision warnings.** When your abbreviation matches a macOS Text Replacement, the editor surfaces a warning — Snippy takes precedence cleanly.

## Privacy

Snippy is built for privacy:

- **No network.** Snippy never makes a network request. Your snippets,
  keystrokes, and clipboard never leave your Mac.
- **No telemetry.** No analytics, no usage tracking, no crash reporting.
- **Local-only storage.** Your library is a plain JSON file you can read,
  copy, or version-control yourself. Default location:
  `~/Library/Application Support/Snippy/snippy-library.json`.
- **Accessibility permission** is required to observe keystrokes, like every
  other macOS text expander. The code that uses it is in
  [`Sources/Snippy/Engine/KeystrokeMonitor.swift`](Sources/Snippy/Engine/KeystrokeMonitor.swift)
  — it's a few dozen lines, easy to audit.

The full source is in this repo. The build is reproducible from
`./build.sh release` on any Mac with the Swift toolchain.

## Sync between Macs

Snippy's library is a single file (`snippy-library.json`). To sync between
machines:

1. *Settings → Storage → Choose Folder…*
2. Pick a folder inside **iCloud Drive**, **Dropbox**, or any other sync tool.
3. Do the same on each Mac and point at the same folder.

The library auto-saves on every change and is re-read when Snippy launches.

## Build from source

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/Lougene/snippy.git
cd snippy
./build.sh release
open build/Snippy.app
```

For day-to-day iteration:

```sh
swift build -c debug
```

## Releasing (maintainer notes)

The production release pipeline (Developer ID signing, notarization, DMG) lives
in `release.sh` and reads signing credentials from a gitignored `.env.local`.
See `.env.local.example` for the variables it expects and the one-time
`xcrun notarytool store-credentials` setup.

## License

MIT — see [LICENSE](LICENSE).

## Credits

Built by **Lougene** ([getlever.com.au](https://www.getlever.com.au)).

If Snippy is useful, [let me know](https://www.getlever.com.au).
