import SwiftUI
import AppKit

struct MainWindow: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: ExpansionEngine

    @State private var selectedGroupID: UUID?
    @State private var selectedSnippetID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 200)
        } content: {
            snippetList
                .frame(minWidth: 240)
        } detail: {
            detail
                .frame(minWidth: 420)
        }
        .frame(minWidth: 900, minHeight: 540)
        .navigationTitle("Snippy")
        .toolbar {
            ToolbarItem(placement: .status) {
                statusBadge
            }
        }
        .onAppear {
            if selectedGroupID == nil {
                selectedGroupID = store.library.groups.first?.id
            }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(engine.isRunning ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(engine.isRunning ? "Listening" : "Paused")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    // MARK: - Sidebar (groups)

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selectedGroupID) {
                Section("Groups") {
                    ForEach($store.library.groups, id: \.id) { $group in
                        GroupRow(group: $group)
                            .tag(group.id as UUID?)
                            .contextMenu {
                                Button("Rename…") {
                                    renamePrompt(group: group)
                                }
                                Button(group.enabled ? "Disable" : "Enable") {
                                    store.toggleGroup(group.id)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    store.deleteGroup(group.id)
                                    if selectedGroupID == group.id {
                                        selectedGroupID = store.library.groups.first?.id
                                    }
                                }
                            }
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    store.addGroup()
                    selectedGroupID = store.library.groups.last?.id
                } label: {
                    Label("New Group", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Snippet list

    @ViewBuilder
    private var snippetList: some View {
        if let gIdx = currentGroupIndex {
            VStack(spacing: 0) {
                List(selection: $selectedSnippetID) {
                    ForEach($store.library.groups[gIdx].snippets, id: \.id) { $snippet in
                        SnippetRow(snippet: $snippet)
                            .tag(snippet.id as UUID?)
                            .contextMenu {
                                Button(snippet.enabled ? "Disable" : "Enable") {
                                    store.toggleSnippet(snippet.id, in: store.library.groups[gIdx].id)
                                }
                                Button("Delete", role: .destructive) {
                                    let gid = store.library.groups[gIdx].id
                                    store.deleteSnippet(snippet.id, in: gid)
                                }
                            }
                    }
                }
                Divider()
                HStack {
                    Button {
                        let gid = store.library.groups[gIdx].id
                        if let new = store.addSnippet(to: gid) {
                            selectedSnippetID = new.id
                        }
                    } label: {
                        Label("New Snippet", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .padding(8)
            }
        } else {
            ContentUnavailableView("No Group Selected",
                                   systemImage: "folder",
                                   description: Text("Select or create a group to add snippets."))
        }
    }

    // MARK: - Detail (editor)

    @ViewBuilder
    private var detail: some View {
        if let gIdx = currentGroupIndex,
           let sIdx = currentSnippetIndex(in: gIdx) {
            SnippetEditor(
                snippet: $store.library.groups[gIdx].snippets[sIdx],
                groupID: store.library.groups[gIdx].id
            )
            .environmentObject(store)
            .environmentObject(engine)
            .id(store.library.groups[gIdx].snippets[sIdx].id)
        } else {
            ContentUnavailableView("No Snippet Selected",
                                   systemImage: "text.cursor",
                                   description: Text("Pick a snippet to edit, or create a new one."))
        }
    }

    // MARK: - Helpers

    private var currentGroupIndex: Int? {
        guard let id = selectedGroupID else { return nil }
        return store.library.groups.firstIndex(where: { $0.id == id })
    }

    private func currentSnippetIndex(in groupIdx: Int) -> Int? {
        guard let id = selectedSnippetID else { return nil }
        return store.library.groups[groupIdx].snippets.firstIndex(where: { $0.id == id })
    }

    private func renamePrompt(group: SnippetGroup) {
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        let field = NSTextField(string: group.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.renameGroup(group.id, to: field.stringValue)
        }
    }
}

private struct GroupRow: View {
    @Binding var group: SnippetGroup
    var body: some View {
        HStack {
            Toggle("", isOn: $group.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            Text(group.name)
                .foregroundStyle(group.enabled ? .primary : .secondary)
            Spacer()
            Text("\(group.snippets.count)")
                .foregroundStyle(.secondary)
                .font(.caption.monospacedDigit())
        }
    }
}

private struct SnippetRow: View {
    @Binding var snippet: Snippet
    var body: some View {
        HStack {
            Toggle("", isOn: $snippet.enabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.displayName)
                    .foregroundStyle(snippet.enabled ? .primary : .secondary)
                    .italic(snippet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !snippet.abbreviation.isEmpty {
                    Text(snippet.abbreviation)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
