import Foundation
import AppKit
import Carbon.HIToolbox

/// Performs the actual deletion of the trigger and insertion of the snippet content.
/// Strategy: synthesize N backspaces, swap the pasteboard, send Cmd+V, restore pasteboard.
final class Expander {
    /// Delay after writing our snippet to the pasteboard before firing Cmd+V, so the
    /// paste never reads a half-written pasteboard.
    private let settleDelay: TimeInterval = 0.03
    /// Time to wait after Cmd+V before restoring the previous pasteboard. A synthetic
    /// Cmd+V is consumed asynchronously by the destination app; if we restore too soon
    /// the app pastes the *restored* (previous) clipboard instead of our snippet. This
    /// is deliberately generous to cover slow apps (Chrome/Electron/Slack) under load.
    private let restoreDelay: TimeInterval = 0.6
    /// Spacing between successive synthetic backspaces. Slow destinations (Electron
    /// apps like WhatsApp/Slack) process input on a throttled queue and will not
    /// consume a tight burst of backspaces before the paste lands — the paste then
    /// races ahead and the late backspaces chew characters off the *end* of the
    /// inserted snippet. Spreading the backspaces out lets the app keep up.
    private let perBackspaceDelay: TimeInterval = 0.012
    /// Extra pause after the final backspace before we touch the pasteboard and
    /// paste, so every deletion is committed by the destination first.
    private let postBackspaceSettle: TimeInterval = 0.05

    func expand(deleteCount: Int,
                content: NSAttributedString,
                trailingTerminator: Character?,
                overrideFormatting: Bool) {
        // Delete the trigger first, then paste — but only once every backspace has
        // actually been consumed. sendBackspaces schedules the deletions with spacing
        // and invokes the completion after the last one has settled, so the gap before
        // the paste scales with deleteCount instead of being a fixed (too-short) delay.
        sendBackspaces(deleteCount) { [self] in
            paste(content: content,
                  trailingTerminator: trailingTerminator,
                  overrideFormatting: overrideFormatting)
        }
    }

    private func paste(content: NSAttributedString,
                       trailingTerminator: Character?,
                       overrideFormatting: Bool) {
        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard: pasteboard)
        pasteboard.clearContents()

        if overrideFormatting {
            // Publish rich representations so the destination uses the snippet's styling.
            let mutable = NSMutableAttributedString(attributedString: content)
            if let term = trailingTerminator {
                mutable.append(NSAttributedString(string: String(term)))
            }
            if Self.hasRichFormatting(content) {
                if let rtfd = try? mutable.data(from: NSRange(location: 0, length: mutable.length),
                                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
                    pasteboard.setData(rtfd, forType: .rtfd)
                }
                if let rtf = try? mutable.data(from: NSRange(location: 0, length: mutable.length),
                                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                    pasteboard.setData(rtf, forType: .rtf)
                }
            }
            pasteboard.setString(mutable.string, forType: .string)
        } else {
            // Plain-text paste so the destination's own font/size/color win.
            // List paragraphs get textual markers so bullet/number structure survives.
            var text = Self.plainTextWithListMarkers(content)
            if let term = trailingTerminator { text.append(term) }
            pasteboard.setString(text, forType: .string)
        }

        // Let the pasteboard write commit before pasting, then remember the change
        // count so we can tell if anything else (e.g. a real user copy) touched the
        // clipboard during the restore window.
        let ourChangeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            self.sendCmdV()

            DispatchQueue.main.asyncAfter(deadline: .now() + self.restoreDelay) {
                // If the change count moved past ours, something else wrote to the
                // clipboard after our paste — don't clobber it with the stale snapshot.
                guard pasteboard.changeCount == ourChangeCount else { return }
                self.restore(snapshot: saved, to: pasteboard)
            }
        }
    }

    // MARK: - Synthesizing keystrokes

    /// Post `count` backspaces spaced by `perBackspaceDelay`, then call `completion`
    /// after `postBackspaceSettle` so the caller only pastes once the destination has
    /// had time to apply every deletion. Runs on the main run loop (same thread the
    /// event tap fires on).
    private func sendBackspaces(_ count: Int, completion: @escaping () -> Void) {
        guard count > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + postBackspaceSettle, execute: completion)
            return
        }
        postBackspace()
        func step(_ remaining: Int) {
            guard remaining > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + postBackspaceSettle, execute: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + perBackspaceDelay) {
                self.postBackspace()
                step(remaining - 1)
            }
        }
        step(count - 1)
    }

    private func postBackspace() {
        let source = CGEventSource(stateID: .combinedSessionState)
        CGEvent(keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Delete),
                keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_Delete),
                keyDown: false)?.post(tap: .cghidEventTap)
    }

    private func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source,
                           virtualKey: CGKeyCode(kVK_ANSI_V),
                           keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source,
                         virtualKey: CGKeyCode(kVK_ANSI_V),
                         keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Plain-text rendering with list markers

    /// Flatten an attributed string to plain text. Paragraphs that belong to an
    /// `NSTextList` get a textual marker prefix (`• `, `1. `, etc.) so bullet
    /// and numbered list structure survives a plain-text paste.
    private static func plainTextWithListMarkers(_ attr: NSAttributedString) -> String {
        guard attr.length > 0 else { return "" }
        let ns = attr.string as NSString
        var output = ""
        var counters: [ObjectIdentifier: Int] = [:]
        var pos = 0
        while pos < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: pos, length: 0))
            let body = ns.substring(with: para)
            let style = attr.attribute(.paragraphStyle, at: para.location, effectiveRange: nil) as? NSParagraphStyle
            let lists = style?.textLists ?? []
            if let list = lists.last {
                let key = ObjectIdentifier(list)
                let nextIndex = (counters[key] ?? max(0, list.startingItemNumber - 1)) + 1
                counters[key] = nextIndex
                let indent = String(repeating: "    ", count: max(0, lists.count - 1))
                let marker = list.marker(forItemNumber: nextIndex)
                var line = body
                var trailing = ""
                if line.hasSuffix("\n") { trailing = "\n"; line = String(line.dropLast()) }
                output += "\(indent)\(marker) \(line)\(trailing)"
            } else {
                output += body
            }
            pos = para.location + para.length
        }
        return output
    }

    // MARK: - Rich-text detection

    /// True iff the snippet uses any visible rich-text feature: attachments,
    /// links, bold/italic, underline/strikethrough, non-default colors, or a
    /// font that differs from the editor default. Plain content returns false
    /// so paste falls through to the destination's own styling.
    private static func hasRichFormatting(_ attr: NSAttributedString) -> Bool {
        guard attr.length > 0 else { return false }
        let defaultFont = NSFont.systemFont(ofSize: 14)
        let fullRange = NSRange(location: 0, length: attr.length)
        var rich = false
        attr.enumerateAttributes(in: fullRange, options: []) { attrs, _, stop in
            if attrs[.attachment] != nil { rich = true; stop.pointee = true; return }
            if attrs[.link] != nil { rich = true; stop.pointee = true; return }
            if let u = attrs[.underlineStyle] as? Int, u != 0 { rich = true; stop.pointee = true; return }
            if let s = attrs[.strikethroughStyle] as? Int, s != 0 { rich = true; stop.pointee = true; return }
            if attrs[.backgroundColor] != nil { rich = true; stop.pointee = true; return }
            if let fg = attrs[.foregroundColor] as? NSColor, !isDefaultTextColor(fg) {
                rich = true; stop.pointee = true; return
            }
            if let font = attrs[.font] as? NSFont, !fontMatchesDefault(font, defaultFont) {
                rich = true; stop.pointee = true; return
            }
        }
        return rich
    }

    private static func fontMatchesDefault(_ font: NSFont, _ baseline: NSFont) -> Bool {
        let traits = NSFontManager.shared.traits(of: font)
        if traits.contains(.boldFontMask) || traits.contains(.italicFontMask) { return false }
        guard font.pointSize == baseline.pointSize else { return false }
        return font.familyName == baseline.familyName
    }

    private static func isDefaultTextColor(_ color: NSColor) -> Bool {
        let candidates: [NSColor] = [.labelColor, .textColor, .black]
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        for c in candidates {
            if let cRGB = c.usingColorSpace(.deviceRGB),
               abs(rgb.redComponent   - cRGB.redComponent)   < 0.001,
               abs(rgb.greenComponent - cRGB.greenComponent) < 0.001,
               abs(rgb.blueComponent  - cRGB.blueComponent)  < 0.001,
               abs(rgb.alphaComponent - cRGB.alphaComponent) < 0.001 {
                return true
            }
        }
        return false
    }

    // MARK: - Pasteboard snapshot/restore

    private struct ItemSnapshot {
        let typeData: [(NSPasteboard.PasteboardType, Data)]
    }

    private func snapshot(pasteboard: NSPasteboard) -> [ItemSnapshot] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var entries: [(NSPasteboard.PasteboardType, Data)] = []
            for type in item.types {
                if let data = item.data(forType: type) {
                    entries.append((type, data))
                }
            }
            return ItemSnapshot(typeData: entries)
        }
    }

    private func restore(snapshot: [ItemSnapshot], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { snap in
            let item = NSPasteboardItem()
            for (type, data) in snap.typeData {
                item.setData(data, forType: type)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
