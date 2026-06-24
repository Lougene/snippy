import SwiftUI
import AppKit

struct SnippetEditor: View {
    @Binding var snippet: Snippet
    let groupID: UUID
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: ExpansionEngine

    @State private var attributed: NSAttributedString = NSAttributedString(string: "")
    @StateObject private var richTextCoordinator = RichTextCoordinator()

    private var conflictsWithMacOS: Bool {
        !snippet.abbreviation.isEmpty
            && engine.macOSConflicts.contains(snippet.abbreviation)
    }

    private var namePlaceholder: String {
        let derived = Snippet.derivedName(from: attributed.string)
        return derived == "Untitled" ? "Name (auto from content)" : derived
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField(namePlaceholder, text: $snippet.name)
                    .textFieldStyle(.roundedBorder)
                Toggle("Enabled", isOn: $snippet.enabled)
                    .toggleStyle(.switch)
            }

            HStack {
                Text("Abbreviation")
                    .frame(width: 110, alignment: .leading)
                TextField("e.g. ;sig", text: $snippet.abbreviation)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            if conflictsWithMacOS {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Also defined in macOS Text Replacements. Snippy will fire first; the system substitution is suppressed for this abbreviation.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .foregroundStyle(.orange)
                .padding(.leading, 110)
            }

            HStack {
                Text("Trigger")
                    .frame(width: 110, alignment: .leading)
                Picker("", selection: $snippet.terminatorMode) {
                    ForEach(TerminatorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Formatting")
                    .frame(width: 110, alignment: .leading)
                Toggle("Override formatting", isOn: $snippet.overrideFormatting)
                    .toggleStyle(.switch)
                    .help("When off, paste uses the destination's font and size. When on, paste preserves this snippet's font, size, and colors.")
                Spacer()
            }

            Divider()

            HStack {
                Text("Content")
                    .font(.headline)
                Spacer()
                Button {
                    insertImage()
                } label: {
                    Label("Insert Image", systemImage: "photo")
                }
                .help("Insert an image into the snippet content")
            }

            RichTextToolbar(coordinator: richTextCoordinator)
            RichTextEditor(text: $attributed, coordinator: richTextCoordinator)
                .frame(minHeight: 240)

            Spacer()
        }
        .padding(16)
        .onAppear {
            attributed = snippet.attributedContent
        }
        .onChange(of: snippet.id) { _, _ in
            attributed = snippet.attributedContent
        }
        .onChange(of: attributed) { _, newValue in
            snippet.contentRTFD = newValue.toRTFD()
        }
    }

    private func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else { return }

        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: image)
        attachment.attachmentCell = cell
        let attachStr = NSAttributedString(attachment: attachment)

        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.append(attachStr)
        attributed = mutable
    }
}
