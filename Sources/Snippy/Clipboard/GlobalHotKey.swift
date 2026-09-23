import Foundation
import Carbon.HIToolbox

/// A system-wide keyboard shortcut registered through Carbon's hot key API.
/// Unlike the keystroke event tap, the shortcut is consumed: the frontmost app
/// never sees it. Unregisters itself on deinit.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init?(preset: ClipboardHotKey, action: @escaping @MainActor () -> Void) {
        let modifiers: Int
        switch preset {
        case .shiftCmdV:  modifiers = cmdKey | shiftKey
        case .optionCmdV: modifiers = cmdKey | optionKey
        case .ctrlCmdV:   modifiers = cmdKey | controlKey
        case .off:        return nil
        }
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
        guard installed == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x534E_5059), id: 1) // 'SNPY'
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(modifiers), id,
                                             GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            // deinit still runs for a fully-initialized failed init; don't remove twice.
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            NSLog("Snippy: could not register clipboard shortcut \(preset.label) (status \(registered))")
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
