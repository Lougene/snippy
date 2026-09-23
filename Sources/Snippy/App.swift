import SwiftUI
import AppKit

@main
struct SnippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: LibraryStore
    @StateObject private var engine: ExpansionEngine
    @StateObject private var clipboard = ClipboardManager()

    init() {
        let store = LibraryStore()
        _store = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: ExpansionEngine(store: store))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(clipboard)
        } label: {
            Image(systemName: engine.isRunning ? "text.cursor" : "pause.circle")
        }
        .menuBarExtraStyle(.menu)

        Window("Snippy by Lever — Library", id: "library") {
            MainWindow()
                .environmentObject(store)
                .environmentObject(engine)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(clipboard)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Prompt for Accessibility on first launch (no-op if already granted).
        Permissions.promptForAccessibility()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuContent: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var engine: ExpansionEngine
    @EnvironmentObject var clipboard: ClipboardManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if engine.isRunning {
                Button("Pause Listening") { engine.stop() }
            } else {
                Button("Start Listening") { engine.start() }
            }

            Divider()

            Text(summary).foregroundStyle(.secondary)

            Divider()

            if clipboard.historyEnabled {
                Menu("Clipboard History") {
                    if clipboard.items.isEmpty {
                        Text("Nothing copied yet")
                    } else {
                        ForEach(clipboard.items.prefix(15)) { item in
                            Button(item.preview(maxLength: 50)) { clipboard.paste(item) }
                        }
                        Divider()
                        Button("Clear History") { clipboard.clearHistory() }
                    }
                }
                Button(clipboard.hotKey == .off
                       ? "Search Clipboard History…"
                       : "Search Clipboard History…  \(clipboard.hotKey.label)") {
                    clipboard.showPicker()
                }
            }
            Toggle("Clean Tracking from Copied Links", isOn: $clipboard.cleanLinks)

            Divider()

            Button("Open Library…") {
                openWindow(id: "library")
            }
            .keyboardShortcut("L")

            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")

            Divider()

            Button("Quit Snippy by Lever") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private var summary: String {
        let groups = store.library.groups.count
        let snippets = store.library.groups.reduce(0) { $0 + $1.snippets.count }
        return "\(snippets) snippets in \(groups) group\(groups == 1 ? "" : "s")"
    }
}
