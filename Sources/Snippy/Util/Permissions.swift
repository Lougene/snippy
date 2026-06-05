import Foundation
import AppKit

enum Permissions {
    /// Returns true if Accessibility is currently granted.
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system's "grant Accessibility?" prompt for this app.
    @discardableResult
    static func promptForAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
