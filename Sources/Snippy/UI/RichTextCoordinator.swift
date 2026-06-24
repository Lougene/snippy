import SwiftUI
import AppKit

/// Bridge between the `RichTextEditor` (NSTextView) and the SwiftUI
/// `RichTextToolbar`. The coordinator observes the editor's selection and
/// publishes the formatting state at the caret (bold, italic, alignment, etc.)
/// so the toolbar can highlight active buttons. It also exposes apply-action
/// methods the toolbar buttons call.
@MainActor
final class RichTextCoordinator: ObservableObject {
    /// Weak so the coordinator can outlive a re-creation of the NSTextView
    /// without retaining it.
    weak var textView: NSTextView?

    @Published var isBold: Bool = false
    @Published var isItalic: Bool = false
    @Published var isUnderline: Bool = false
    @Published var isStrikethrough: Bool = false
    @Published var fontSize: CGFloat = 14
    @Published var textColor: Color = Color(NSColor.labelColor)
    @Published var alignment: NSTextAlignment = .natural
    @Published var listKind: ListKind = .none

    enum ListKind: Hashable {
        case none, bullet, numbered
    }

    /// Available sizes shown in the toolbar size picker.
    static let fontSizes: [CGFloat] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 36, 48, 64]

    // MARK: - State read-back

    /// Refresh published state from the current selection. Called by the
    /// editor whenever the selection or text changes.
    func selectionDidChange() {
        guard let tv = textView else { return }
        let storage = tv.textStorage
        let length = storage?.length ?? 0
        guard length > 0 else {
            resetToDefaults()
            return
        }

        // Read attributes at the location just before the caret when the
        // selection is empty (so the toolbar reflects what the next typed
        // character will look like). For ranges, use the start of the range.
        let sel = tv.selectedRange()
        let probe = max(0, sel.length == 0 ? sel.location - 1 : sel.location)
        let clamped = min(probe, length - 1)
        guard clamped >= 0, let attrs = storage?.attributes(at: clamped, effectiveRange: nil) else {
            resetToDefaults()
            return
        }

        let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
        let traits = NSFontManager.shared.traits(of: font)
        isBold = traits.contains(.boldFontMask)
        isItalic = traits.contains(.italicFontMask)
        fontSize = font.pointSize

        if let u = attrs[.underlineStyle] as? Int {
            isUnderline = u != 0
        } else {
            isUnderline = false
        }
        if let s = attrs[.strikethroughStyle] as? Int {
            isStrikethrough = s != 0
        } else {
            isStrikethrough = false
        }

        if let color = attrs[.foregroundColor] as? NSColor {
            textColor = Color(color)
        } else {
            textColor = Color(NSColor.labelColor)
        }

        if let pStyle = attrs[.paragraphStyle] as? NSParagraphStyle {
            alignment = pStyle.alignment
            if let list = pStyle.textLists.last {
                let fmt = list.markerFormat.rawValue
                listKind = fmt.contains("decimal") ? .numbered : .bullet
            } else {
                listKind = .none
            }
        } else {
            alignment = .natural
            listKind = .none
        }
    }

    private func resetToDefaults() {
        isBold = false
        isItalic = false
        isUnderline = false
        isStrikethrough = false
        fontSize = 14
        textColor = Color(NSColor.labelColor)
        alignment = .natural
        listKind = .none
    }

    // MARK: - Apply actions

    func toggleBold() { toggleTrait(.boldFontMask, unset: .unboldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask, unset: .unitalicFontMask) }

    private func toggleTrait(_ on: NSFontTraitMask, unset: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = effectiveRange(tv)
        guard range.length > 0 else {
            // Empty selection at caret: only update the typing attributes so
            // the next character typed gets the trait.
            adjustTypingAttributesFont(on: on, unset: unset)
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
            let traits = NSFontManager.shared.traits(of: font)
            let nowOn = traits.contains(on)
            let target: NSFontTraitMask = nowOn ? unset : on
            if let next = NSFontManager.shared.convert(font, toHaveTrait: target) as NSFont? {
                storage.addAttribute(.font, value: next, range: sub)
            }
        }
        storage.endEditing()
        tv.didChangeText()
        selectionDidChange()
    }

    private func adjustTypingAttributesFont(on: NSFontTraitMask, unset: NSFontTraitMask) {
        guard let tv = textView else { return }
        var attrs = tv.typingAttributes
        let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: fontSize)
        let traits = NSFontManager.shared.traits(of: font)
        let target: NSFontTraitMask = traits.contains(on) ? unset : on
        if let next = NSFontManager.shared.convert(font, toHaveTrait: target) as NSFont? {
            attrs[.font] = next
            tv.typingAttributes = attrs
        }
        selectionDidChange()
    }

    func toggleUnderline() { toggleIntAttribute(.underlineStyle) }
    func toggleStrikethrough() { toggleIntAttribute(.strikethroughStyle) }

    private func toggleIntAttribute(_ key: NSAttributedString.Key) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = effectiveRange(tv)
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let current = attrs[key] as? Int ?? 0
            attrs[key] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            tv.typingAttributes = attrs
            selectionDidChange()
            return
        }
        storage.beginEditing()
        // Look at the value at the start of the range to decide on/off; apply
        // uniformly across the range.
        let current = storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0
        let target = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        storage.addAttribute(key, value: target, range: range)
        storage.endEditing()
        tv.didChangeText()
        selectionDidChange()
    }

    func setFontSize(_ size: CGFloat) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = effectiveRange(tv)
        if range.length == 0 {
            var attrs = tv.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? NSFont.systemFont(ofSize: size)
            attrs[.font] = NSFontManager.shared.convert(font, toSize: size)
            tv.typingAttributes = attrs
            fontSize = size
            return
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: size)
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: size), range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
        selectionDidChange()
    }

    func setTextColor(_ color: Color) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let nsColor = NSColor(color)
        let range = effectiveRange(tv)
        if range.length == 0 {
            var attrs = tv.typingAttributes
            attrs[.foregroundColor] = nsColor
            tv.typingAttributes = attrs
            textColor = color
            return
        }
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: nsColor, range: range)
        storage.endEditing()
        tv.didChangeText()
        selectionDidChange()
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = paragraphRange(tv)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, sub, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            style.alignment = alignment
            storage.addAttribute(.paragraphStyle, value: style, range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
        selectionDidChange()
    }

    func toggleList(_ kind: ListKind) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = paragraphRange(tv)
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, sub, _ in
            let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            if listKind == kind {
                style.textLists = []
                style.headIndent = 0
                style.firstLineHeadIndent = 0
            } else {
                let format: NSTextList.MarkerFormat = (kind == .bullet) ? .disc : .decimal
                let list = NSTextList(markerFormat: format, options: 0)
                style.textLists = [list]
                style.headIndent = 24
                style.firstLineHeadIndent = 0
            }
            storage.addAttribute(.paragraphStyle, value: style, range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
        selectionDidChange()
    }

    // MARK: - Range helpers

    /// The selection if non-empty, otherwise the whole document — most
    /// formatting buttons act on something rather than nothing.
    private func effectiveRange(_ tv: NSTextView) -> NSRange {
        let sel = tv.selectedRange()
        return sel.length > 0 ? sel : NSRange(location: 0, length: 0)
    }

    /// The paragraph(s) that contain the selection — used for alignment + list
    /// changes, which are paragraph-level.
    private func paragraphRange(_ tv: NSTextView) -> NSRange {
        guard let storage = tv.textStorage, storage.length > 0 else {
            return NSRange(location: 0, length: 0)
        }
        let sel = tv.selectedRange()
        let clamped = NSRange(location: min(sel.location, storage.length - 1),
                              length: min(sel.length, max(0, storage.length - sel.location)))
        return (storage.string as NSString).paragraphRange(for: clamped)
    }
}
