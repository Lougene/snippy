import SwiftUI
import AppKit

/// Inline formatting toolbar that sits above `RichTextEditor`. Reads its state
/// from a `RichTextCoordinator` so buttons highlight when the selection has the
/// matching attribute, and dispatches changes through the coordinator.
struct RichTextToolbar: View {
    @ObservedObject var coordinator: RichTextCoordinator

    var body: some View {
        HStack(spacing: 2) {
            // Bold / Italic / Underline / Strikethrough
            toggleButton(systemName: "bold", isOn: coordinator.isBold, help: "Bold (⌘B)") {
                coordinator.toggleBold()
            }
            toggleButton(systemName: "italic", isOn: coordinator.isItalic, help: "Italic (⌘I)") {
                coordinator.toggleItalic()
            }
            toggleButton(systemName: "underline", isOn: coordinator.isUnderline, help: "Underline (⌘U)") {
                coordinator.toggleUnderline()
            }
            toggleButton(systemName: "strikethrough", isOn: coordinator.isStrikethrough, help: "Strikethrough") {
                coordinator.toggleStrikethrough()
            }

            divider

            // Font size
            Menu {
                ForEach(RichTextCoordinator.fontSizes, id: \.self) { size in
                    Button("\(Int(size))") { coordinator.setFontSize(size) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(Int(coordinator.fontSize))")
                        .font(.system(size: 12, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .frame(minWidth: 38)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Font size")

            // Text color
            ColorPicker("", selection: Binding(
                get: { coordinator.textColor },
                set: { coordinator.setTextColor($0) }
            ))
            .labelsHidden()
            .frame(width: 28)
            .help("Text color")

            divider

            // Alignment
            toggleButton(systemName: "text.alignleft",
                         isOn: coordinator.alignment == .left || coordinator.alignment == .natural,
                         help: "Align left") {
                coordinator.setAlignment(.left)
            }
            toggleButton(systemName: "text.aligncenter",
                         isOn: coordinator.alignment == .center,
                         help: "Align center") {
                coordinator.setAlignment(.center)
            }
            toggleButton(systemName: "text.alignright",
                         isOn: coordinator.alignment == .right,
                         help: "Align right") {
                coordinator.setAlignment(.right)
            }
            toggleButton(systemName: "text.justify",
                         isOn: coordinator.alignment == .justified,
                         help: "Justify") {
                coordinator.setAlignment(.justified)
            }

            divider

            // Lists
            toggleButton(systemName: "list.bullet",
                         isOn: coordinator.listKind == .bullet,
                         help: "Bullet list") {
                coordinator.toggleList(.bullet)
            }
            toggleButton(systemName: "list.number",
                         isOn: coordinator.listKind == .numbered,
                         help: "Numbered list") {
                coordinator.toggleList(.numbered)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func toggleButton(systemName: String,
                              isOn: Bool,
                              help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 22)
                .background(isOn ? Color.accentColor.opacity(0.25) : Color.clear)
                .foregroundColor(isOn ? Color.accentColor : Color.primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
