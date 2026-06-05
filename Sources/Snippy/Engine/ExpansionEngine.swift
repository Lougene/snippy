import Foundation
import AppKit
import Combine

/// Glues the keystroke monitor + matcher + expander into a single ObservableObject the UI can drive.
@MainActor
final class ExpansionEngine: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?

    /// Abbreviations that also appear in macOS Text Replacements. The UI surfaces
    /// these so the user understands why Snippy is taking precedence; the engine
    /// forces these snippets to fire in `.auto` mode so Snippy beats the system
    /// substitution (which only runs at terminator boundaries).
    @Published private(set) var macOSConflicts: Set<String> = []

    private let store: LibraryStore
    private var monitor: KeystrokeMonitor?
    private let matcher = Matcher()
    private let expander = Expander()
    private var cancellables = Set<AnyCancellable>()

    init(store: LibraryStore) {
        self.store = store
        recompileTriggers()
        store.$library
            .sink { [weak self] _ in self?.recompileTriggers() }
            .store(in: &cancellables)
        // Refresh macOS Text Replacement detection whenever Snippy is foregrounded —
        // catches edits the user made in System Settings while we were inactive.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.recompileTriggers() }
            .store(in: &cancellables)
        // Defer start to the next run-loop tick so the event tap binds after launch finishes.
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !isRunning else { return }
        let monitor = KeystrokeMonitor { [weak self] key in
            // Callback runs on the run-loop thread the tap was created on (main).
            guard let self else { return }
            let reemit = self.store.library.reemitTerminator
            if let match = self.matcher.consume(key, reemitTerminator: reemit) {
                let attr = match.trigger.snippet.attributedContent
                self.expander.expand(deleteCount: match.deleteCount,
                                     content: attr,
                                     trailingTerminator: match.trailingTerminator,
                                     overrideFormatting: match.trigger.snippet.overrideFormatting)
            }
        }
        if monitor.start() {
            self.monitor = monitor
            isRunning = true
            lastError = nil
        } else {
            lastError = "Could not create event tap. Grant Accessibility permission in System Settings → Privacy & Security → Accessibility."
        }
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        isRunning = false
    }

    private func recompileTriggers() {
        let macOSAbbrevs = MacOSTextReplacements.enabledAbbreviations()
        var triggers: [CompiledTrigger] = []
        var conflicts: Set<String> = []
        for group in store.library.groups where group.enabled {
            for snippet in group.snippets where snippet.enabled && !snippet.abbreviation.isEmpty {
                var mode = store.library.effectiveMode(for: snippet, in: group)
                if macOSAbbrevs.contains(snippet.abbreviation) {
                    conflicts.insert(snippet.abbreviation)
                    // Force auto so Snippy fires on the abbreviation itself, before the
                    // terminator that would otherwise trigger macOS's substitution.
                    mode = .auto
                }
                triggers.append(CompiledTrigger(snippet: snippet,
                                                groupID: group.id,
                                                abbreviation: snippet.abbreviation,
                                                mode: mode))
            }
        }
        matcher.setTriggers(triggers)
        if conflicts != macOSConflicts {
            macOSConflicts = conflicts
        }
    }
}
