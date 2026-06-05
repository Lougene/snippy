import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: ExpansionEngine

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
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 480)
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
