import SwiftUI
import AppKit

/// SwiftUI wrapper around NSTextView for rich text editing.
/// Two-way binds an NSAttributedString. Supports paste of images (via NSTextView default behavior).
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: NSAttributedString
    var coordinator: RichTextCoordinator?
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
        // Inspector bar is window-level in NSTextView and leaks above the
        // SwiftUI split-pane layout (sits above the snippet list, not the
        // editor). We replace it with our own inline SwiftUI toolbar.
        textView.usesInspectorBar = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textStorage?.setAttributedString(text)

        // Hand the NSTextView reference up to the SwiftUI-side coordinator so
        // the toolbar can read/write its attributes.
        coordinator?.textView = textView
        coordinator?.selectionDidChange()

        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Re-hand-off the textView reference each update — if SwiftUI tears
        // down + rebuilds the SnippetEditor (e.g. when switching snippets),
        // makeNSView may not be re-called but the binding to `coordinator`
        // can change identity.
        if coordinator?.textView !== textView {
            coordinator?.textView = textView
            coordinator?.selectionDidChange()
        }
        // Avoid feedback loops: only re-set if the value really changed.
        if textView.attributedString() != text {
            let selected = textView.selectedRange()
            textView.textStorage?.setAttributedString(text)
            // Clamp selection
            let len = textView.textStorage?.length ?? 0
            let loc = min(selected.location, len)
            textView.setSelectedRange(NSRange(location: loc, length: 0))
            coordinator?.selectionDidChange()
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
            DispatchQueue.main.async { [weak self] in
                self?.parent.coordinator?.selectionDidChange()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.coordinator?.selectionDidChange()
            }
        }
    }
}
