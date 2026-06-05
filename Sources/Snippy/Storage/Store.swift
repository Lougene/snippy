import Foundation
import Combine
import AppKit

/// Persists the snippet library to a user-chosen folder as `snippy-library.json`.
/// Writes are debounced; reads happen at launch and when the storage URL changes.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var library: Library = .empty {
        didSet { scheduleSave() }
    }

    @Published var storageURL: URL {
        didSet {
            UserDefaults.standard.set(storageURL.path, forKey: Self.storageKey)
            load()
        }
    }

    private static let storageKey = "snippy.storageFolder"
    private static let fileName = "snippy-library.json"
    private static let legacyBundleID = "com.snippy.app"

    private var saveWorkItem: DispatchWorkItem?

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.storageKey),
           FileManager.default.fileExists(atPath: saved) {
            self.storageURL = URL(fileURLWithPath: saved)
        } else if let migrated = Self.legacyStoragePath() {
            // First launch under the new bundle ID: adopt the folder the user
            // picked under the previous bundle so their library carries over.
            self.storageURL = URL(fileURLWithPath: migrated)
            UserDefaults.standard.set(migrated, forKey: Self.storageKey)
        } else {
            // Default to ~/Library/Application Support/Snippy/. Application
            // Support is the conventional home for app data and, unlike
            // ~/Documents, doesn't trigger a TCC permission prompt on first run.
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Snippy", isDirectory: true)
            self.storageURL = base
        }
        load()
        if library.groups.isEmpty {
            seedDemo()
        }
    }

    /// Reads the storage path that was saved under the previous bundle ID
    /// (`com.snippy.app`). Used once on first launch under the new bundle so
    /// existing users don't lose their library.
    private static func legacyStoragePath() -> String? {
        let value = CFPreferencesCopyAppValue(storageKey as CFString,
                                              legacyBundleID as CFString)
        guard let path = value as? String,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    var libraryFileURL: URL {
        storageURL.appendingPathComponent(Self.fileName)
    }

    func load() {
        let url = libraryFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            library = .empty
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // Suspend save scheduling for this assignment.
            saveWorkItem?.cancel()
            library = try decoder.decode(Library.self, from: data)
        } catch {
            NSLog("Snippy: failed to load library: \(error)")
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: storageURL,
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(library)
            try data.write(to: libraryFileURL, options: .atomic)
        } catch {
            NSLog("Snippy: failed to save library: \(error)")
        }
    }

    // MARK: - Mutations

    func addGroup(name: String = "New Group") {
        library.groups.append(SnippetGroup(name: name))
    }

    func deleteGroup(_ id: UUID) {
        library.groups.removeAll { $0.id == id }
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let idx = library.groups.firstIndex(where: { $0.id == id }) else { return }
        library.groups[idx].name = name
    }

    func toggleGroup(_ id: UUID) {
        guard let idx = library.groups.firstIndex(where: { $0.id == id }) else { return }
        library.groups[idx].enabled.toggle()
    }

    func addSnippet(to groupID: UUID) -> Snippet? {
        guard let idx = library.groups.firstIndex(where: { $0.id == groupID }) else { return nil }
        let snippet = Snippet.make()
        library.groups[idx].snippets.append(snippet)
        return snippet
    }

    func updateSnippet(_ snippet: Snippet, in groupID: UUID) {
        guard let gIdx = library.groups.firstIndex(where: { $0.id == groupID }),
              let sIdx = library.groups[gIdx].snippets.firstIndex(where: { $0.id == snippet.id })
        else { return }
        var updated = snippet
        updated.updatedAt = Date()
        library.groups[gIdx].snippets[sIdx] = updated
    }

    func deleteSnippet(_ snippetID: UUID, in groupID: UUID) {
        guard let gIdx = library.groups.firstIndex(where: { $0.id == groupID }) else { return }
        library.groups[gIdx].snippets.removeAll { $0.id == snippetID }
    }

    func toggleSnippet(_ snippetID: UUID, in groupID: UUID) {
        guard let gIdx = library.groups.firstIndex(where: { $0.id == groupID }),
              let sIdx = library.groups[gIdx].snippets.firstIndex(where: { $0.id == snippetID })
        else { return }
        library.groups[gIdx].snippets[sIdx].enabled.toggle()
    }

    private func seedDemo() {
        var demo = SnippetGroup(name: "Examples")
        demo.snippets = [
            Snippet.make(name: "Signature",
                         abbreviation: ";sig",
                         content: NSAttributedString(string: "Cheers,\nYour Name")),
            Snippet.make(name: "Email",
                         abbreviation: ";em",
                         content: NSAttributedString(string: "you@example.com")),
            Snippet.make(name: "Date",
                         abbreviation: ";date",
                         content: NSAttributedString(string: DateFormatter.localizedString(
                            from: Date(), dateStyle: .medium, timeStyle: .none)))
        ]
        library.groups = [demo]
    }
}
