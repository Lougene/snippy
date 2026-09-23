import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: ExpansionEngine
    @EnvironmentObject var clipboard: ClipboardManager

    @State private var accessibilityGranted: Bool = Permissions.accessibilityGranted

    var body: some View {
        Form {
            Section("Storage") {
                HStack {
                    Text(store.storageURL.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose Folder…") { pickFolder() }
                }
                Text("Your library is saved as `snippy-library.json` in this folder. Pick a folder inside iCloud Drive or Dropbox to sync between machines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Triggering") {
                Picker("Default trigger style", selection: $store.library.globalTerminatorMode) {
                    Text("Auto-expand").tag(TerminatorMode.auto)
                    Text("Require Tab/Space").tag(TerminatorMode.terminator)
                }
                .pickerStyle(.segmented)
                Toggle("Re-emit terminator after expansion", isOn: $store.library.reemitTerminator)
                    .help("When a snippet fires via Tab/Space, append that character after the expansion.")
            }

            Section("Links") {
                Toggle("Clean tracking from copied links", isOn: $clipboard.cleanLinks)
                Text("When you copy a link, Snippy strips tracking tags (utm_…, fbclid, gclid, share IDs) and unwraps Google/Outlook/Facebook redirects. The page, its real parameters, and #anchors are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard History") {
                Toggle("Keep clipboard history", isOn: $clipboard.historyEnabled)
                if clipboard.historyEnabled {
                    Picker("Shortcut", selection: $clipboard.hotKey) {
                        ForEach(ClipboardHotKey.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Remember", selection: $clipboard.historyLimit) {
                        ForEach(ClipboardManager.limitOptions, id: \.self) { Text("\($0) items").tag($0) }
                    }
                    Toggle("Keep history after restart", isOn: $clipboard.rememberAcrossRestarts)
                    HStack {
                        Text("\(clipboard.items.count) item\(clipboard.items.count == 1 ? "" : "s") saved")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear History") { clipboard.clearHistory() }
                            .disabled(clipboard.items.isEmpty)
                    }
                }
                Text("Text only, stored on this Mac (never in your synced library folder). Password-manager copies are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Text(accessibilityGranted
                         ? "Accessibility permission granted."
                         : "Accessibility permission required to detect keystrokes.")
                    Spacer()
                    Button("Open System Settings") {
                        Permissions.openAccessibilitySettings()
                    }
                    Button("Re-check") {
                        accessibilityGranted = Permissions.accessibilityGranted
                        if accessibilityGranted && !engine.isRunning { engine.start() }
                    }
                }
            }

            Section {
                if let err = engine.lastError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    if engine.isRunning {
                        Button("Pause Listening") { engine.stop() }
                    } else {
                        Button("Start Listening") { engine.start() }
                    }
                }
            }

            Section("About") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Snippy by Lever")
                        .font(.headline)
                    Text("A free productivity tool from Lever Automation Consulting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("Made by")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link("getlever.com.au", destination: URL(string: "https://www.getlever.com.au")!)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 720)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.storageURL
        if panel.runModal() == .OK, let url = panel.url {
            store.storageURL = url
        }
    }
}
