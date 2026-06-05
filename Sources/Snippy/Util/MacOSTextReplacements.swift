import Foundation

/// Reads macOS's user-configured Text Replacements from
/// NSGlobalDomain → `NSUserDictionaryReplacementItems`. Used to detect when a
/// Snippy abbreviation collides with a system-wide replacement, so Snippy can
/// take precedence cleanly instead of racing the system substitution.
enum MacOSTextReplacements {
    /// Returns the set of currently enabled abbreviations from System Settings →
    /// Keyboard → Text Replacements.
    static func enabledAbbreviations() -> Set<String> {
        // NSGlobalDomain caches in CFPreferences; nudge it so changes made in
        // System Settings while Snippy was running show up on the next read.
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)

        guard let items = UserDefaults.standard.array(forKey: "NSUserDictionaryReplacementItems")
                as? [[String: Any]] else { return [] }

        var result: Set<String> = []
        for item in items {
            if let on = item["on"] as? Bool, !on { continue }
            if let on = item["on"] as? NSNumber, on.boolValue == false { continue }
            if let replace = item["replace"] as? String, !replace.isEmpty {
                result.insert(replace)
            }
        }
        return result
    }
}
