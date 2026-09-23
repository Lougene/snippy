import SwiftUI
import AppKit

/// Floating, non-activating panel listing clipboard history. It takes keyboard
/// focus without activating Snippy, so the app you were typing in stays
/// frontmost and receives the paste.
@MainActor
final class ClipboardPickerController: NSObject, NSWindowDelegate {
    private unowned let manager: ClipboardManager
    private let state = PickerState()
    private var panel: PickerPanel?

    init(manager: ClipboardManager) {
        self.manager = manager
    }

    /// Opens the picker; pressing the shortcut again while open moves down the
    /// list (Flycut-style cycling).
    func toggle() {
        if let panel, panel.isVisible {
            state.moveSelection(by: 1, count: state.filtered(manager.items).count)
            return
        }
        show()
    }

    private func show() {
        state.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func pick(_ item: ClipItem) {
        close()
        manager.paste(item)
    }

    private func makePanel() -> PickerPanel {
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                                backing: .buffered,
                                defer: true)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ClipboardPickerView(
            manager: manager,
            state: state,
            onPick: { [weak self] in self?.pick($0) },
            onClose: { [weak self] in self?.close() }
        ))
        return panel
    }

    /// Centre horizontally, upper third, on the screen with the mouse pointer.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                     y: visible.maxY - size.height - visible.height * 0.15))
    }

    // Clicking anywhere else dismisses the picker.
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated { close() }
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PickerState: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    /// Bumped each time the picker opens so the view re-focuses the search field.
    @Published private(set) var shownAt = Date()

    func reset() {
        query = ""
        selection = 0
        shownAt = Date()
    }

    func filtered(_ items: [ClipItem]) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { selection = 0; return }
        selection = (selection + delta + count) % count
    }
}

struct ClipboardPickerView: View {
    @ObservedObject var manager: ClipboardManager
    @ObservedObject var state: PickerState
    let onPick: (ClipItem) -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool

    private var results: [ClipItem] { state.filtered(manager.items) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(pickSelected)
                    .onChange(of: state.query) { state.selection = 0 }
                    // Handled on the field itself so its editor doesn't swallow them.
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.escape) { onClose(); return .handled }
                    .onExitCommand(perform: onClose)
                    .onKeyPress(characters: .decimalDigits) { press in
                        guard press.modifiers.contains(.command),
                              let digit = Int(press.characters), digit >= 1,
                              results.indices.contains(digit - 1)
                        else { return .ignored }
                        onPick(results[digit - 1])
                        return .handled
                    }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if results.isEmpty {
                Spacer()
                Text(manager.items.isEmpty
                     ? "Nothing copied yet. Copy some text and it will show up here."
                     : "No matches.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, index: index)
                                    .id(item.id)
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: state.selection) {
                        guard results.indices.contains(state.selection) else { return }
                        proxy.scrollTo(results[state.selection].id)
                    }
                }
            }

            Divider()
            Text("↑↓ select · ⏎ paste · ⌘1–9 quick paste · esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .frame(width: 560, height: 440)
        .onAppear { searchFocused = true }
        .onChange(of: state.shownAt) { searchFocused = true }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        let selected = index == state.selection
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(index < 9 ? "⌘\(index + 1)" : "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview(maxLength: 140))
                    .lineLimit(2)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Text(caption(for: item))
                    .font(.caption)
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { onPick(item) }
        .contextMenu {
            Button("Paste") { onPick(item) }
            Button("Delete from History") { manager.delete(item) }
        }
    }

    private func caption(for item: ClipItem) -> String {
        let when = item.copiedAt.formatted(.relative(presentation: .named))
        if let app = item.sourceApp { return "\(when) · \(app)" }
        return when
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        state.moveSelection(by: delta, count: results.count)
        return .handled
    }

    private func pickSelected() {
        guard results.indices.contains(state.selection) else { return }
        onPick(results[state.selection])
    }
}
