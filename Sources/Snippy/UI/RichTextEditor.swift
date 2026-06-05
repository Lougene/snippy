import SwiftUI
import AppKit

/// SwiftUI wrapper around NSTextView for rich text editing.
/// Two-way binds an NSAttributedString. Supports paste of images (via NSTextView default behavior).
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var minHeight: CGFloat = 200

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder

        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsImageEditing = true
        textView.importsGraphics = true
        textView.usesFontPanel = true
        textView.usesInspectorBar = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textStorage?.setAttributedString(text)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Avoid feedback loops: only re-set if the value really changed.
        if textView.attributedString() != text {
            let selected = textView.selectedRange()
            textView.textStorage?.setAttributedString(text)
            // Clamp selection
            let len = textView.textStorage?.length ?? 0
            let loc = min(selected.location, len)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let storage = tv.textStorage else { return }
            parent.text = NSAttributedString(attributedString: storage)
        }
    }
}
