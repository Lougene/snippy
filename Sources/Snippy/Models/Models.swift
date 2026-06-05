import Foundation
import AppKit

enum TerminatorMode: String, Codable, CaseIterable, Identifiable {
    case inherit
    case auto       // expand as soon as the abbreviation is typed
    case terminator // expand only after Tab/Space follows the abbreviation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inherit:    return "Inherit"
        case .auto:       return "Auto-expand"
        case .terminator: return "Require Tab/Space"
        }
    }
}

struct Snippet: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var abbreviation: String
    /// NSAttributedString serialized as RTFD (rich text + inline images), base64-encoded for JSON.
    var contentRTFD: Data
    var enabled: Bool = true
    var terminatorMode: TerminatorMode = .inherit
    /// When true, paste preserves the snippet's font, size, color, and other
    /// character styling. When false (the default), paste publishes plain text
    /// so the destination's own text style wins; list/bullet structure is
    /// converted to text markers so it survives the transition.
    var overrideFormatting: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var attributedContent: NSAttributedString {
        guard !contentRTFD.isEmpty,
              let attr = try? NSAttributedString(
                data: contentRTFD,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
              )
        else { return NSAttributedString(string: "") }
        return attr
    }

    static func make(name: String = "",
                     abbreviation: String = "",
                     content: NSAttributedString = NSAttributedString(string: "")) -> Snippet {
        Snippet(name: name,
                abbreviation: abbreviation,
                contentRTFD: content.toRTFD())
    }

    /// User-entered name if present; otherwise derived from the first line of content.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return Self.derivedName(from: attributedContent.string)
    }

    static func derivedName(from content: String, maxLength: Int = 40) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "Untitled" }
        if firstLine.count <= maxLength { return firstLine }
        let cut = firstLine.index(firstLine.startIndex, offsetBy: maxLength)
        return firstLine[..<cut] + "…"
    }
}

struct SnippetGroup: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var enabled: Bool = true
    var terminatorMode: TerminatorMode = .inherit
    var snippets: [Snippet] = []
}

struct Library: Codable {
    var groups: [SnippetGroup] = []
    var globalTerminatorMode: TerminatorMode = .auto

    /// Re-emit the terminator after expansion when terminator mode fires.
    var reemitTerminator: Bool = true

    static let empty = Library()

    /// Resolve the effective terminator mode for a snippet by walking the inherit chain.
    func effectiveMode(for snippet: Snippet, in group: SnippetGroup) -> TerminatorMode {
        if snippet.terminatorMode != .inherit { return snippet.terminatorMode }
        if group.terminatorMode != .inherit { return group.terminatorMode }
        return globalTerminatorMode == .inherit ? .auto : globalTerminatorMode
    }
}

extension Snippet {
    enum CodingKeys: String, CodingKey {
        case id, name, abbreviation, contentRTFD, enabled, terminatorMode
        case overrideFormatting, createdAt, updatedAt
    }

    /// Custom decoder so libraries persisted before a field was added still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.abbreviation = try c.decodeIfPresent(String.self, forKey: .abbreviation) ?? ""
        self.contentRTFD = try c.decodeIfPresent(Data.self, forKey: .contentRTFD) ?? Data()
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.terminatorMode = try c.decodeIfPresent(TerminatorMode.self, forKey: .terminatorMode) ?? .inherit
        self.overrideFormatting = try c.decodeIfPresent(Bool.self, forKey: .overrideFormatting) ?? false
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

extension NSAttributedString {
    func toRTFD() -> Data {
        let range = NSRange(location: 0, length: length)
        if let data = try? data(from: range,
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
            return data
        }
        return Data()
    }

    var plainString: String { string }
}
