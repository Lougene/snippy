import Foundation

/// A snippet pre-compiled with its effective trigger behavior.
struct CompiledTrigger {
    let snippet: Snippet
    let groupID: UUID
    let abbreviation: String          // raw abbreviation (no terminator)
    let mode: TerminatorMode          // .auto or .terminator (resolved)
}

/// Maintains a sliding buffer of typed characters and reports matches.
final class Matcher {
    private(set) var buffer: String = ""
    private let maxBufferLength = 64
    private var triggers: [CompiledTrigger] = []

    /// Result returned to the caller when a match fires.
    struct Match {
        let trigger: CompiledTrigger
        /// Total characters to delete from the document (abbreviation + optional terminator).
        let deleteCount: Int
        /// If terminator mode fired and reemit is on, the terminator character to append.
        let trailingTerminator: Character?
    }

    func setTriggers(_ triggers: [CompiledTrigger]) {
        self.triggers = triggers.sorted { $0.abbreviation.count > $1.abbreviation.count }
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// Process one typed key. Returns a match if one fires.
    func consume(_ key: TypedKey, reemitTerminator: Bool) -> Match? {
        if key.isWordReset {
            reset()
            return nil
        }
        if key.isBackspace {
            if !buffer.isEmpty { buffer.removeLast() }
            return nil
        }
        guard let ch = key.character else { return nil }

        buffer.append(ch)
        if buffer.count > maxBufferLength {
            buffer.removeFirst(buffer.count - maxBufferLength)
        }

        // Auto mode: any trigger whose abbreviation matches the tail of the buffer fires.
        // Terminator mode: requires the buffer to end with abbreviation + terminator.
        for t in triggers {
            switch t.mode {
            case .auto:
                if buffer.hasSuffix(t.abbreviation) {
                    let match = Match(trigger: t,
                                      deleteCount: t.abbreviation.count,
                                      trailingTerminator: nil)
                    reset()
                    return match
                }
            case .terminator:
                if key.isTerminator && buffer.dropLast().hasSuffix(t.abbreviation) {
                    let match = Match(trigger: t,
                                      deleteCount: t.abbreviation.count + 1,
                                      trailingTerminator: reemitTerminator ? ch : nil)
                    reset()
                    return match
                }
            case .inherit:
                continue
            }
        }
        return nil
    }
}
