import Foundation
import AppKit
import Carbon.HIToolbox

/// A character that was typed, plus whether it terminated a word (Tab/Space/Return).
struct TypedKey {
    var character: Character?
    var isBackspace: Bool = false
    var isTerminator: Bool = false  // tab or space
    var isWordReset: Bool = false   // return, escape, etc.
}

/// Wraps a CGEventTap and forwards each keystroke to a handler closure.
/// Requires Accessibility permission. Returns nil if the tap can't be created.
final class KeystrokeMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (TypedKey) -> Void

    init(handler: @escaping (TypedKey) -> Void) {
        self.handler = handler
    }

    deinit { stop() }

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeystrokeMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(event: event, type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func handle(event: CGEvent, type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown else { return }

        let flags = event.flags
        // Cmd/Ctrl held → reset buffer; user is doing a shortcut, not typing a snippet.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            handler(TypedKey(isWordReset: true))
            return
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch keyCode {
        case kVK_Delete, kVK_ForwardDelete:
            handler(TypedKey(isBackspace: true))
            return
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape:
            handler(TypedKey(isWordReset: true))
            return
        case kVK_Tab:
            handler(TypedKey(character: "\t", isTerminator: true))
            return
        case kVK_Space:
            handler(TypedKey(character: " ", isTerminator: true))
            return
        default:
            break
        }

        // Decode unicode characters.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4,
                                       actualStringLength: &length,
                                       unicodeString: &chars)
        guard length > 0 else { return }
        let str = String(utf16CodeUnits: chars, count: length)
        for ch in str {
            handler(TypedKey(character: ch))
        }
    }
}
