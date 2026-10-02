import Carbon

// Module-level globals bridge the C callback to Swift without capturing self.
private nonisolated(unsafe) var _voiceCallback:  (() -> Void)?
private nonisolated(unsafe) var _editorCallback: (() -> Void)?
private nonisolated(unsafe) var _scratchpadCallback: (() -> Void)?

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onVoiceHotkey:  (() -> Void)? { didSet { _voiceCallback  = onVoiceHotkey  } }
    var onEditorHotkey: (() -> Void)? { didSet { _editorCallback = onEditorHotkey } }
    var onScratchpadHotkey: (() -> Void)? { didSet { _scratchpadCallback = onScratchpadHotkey } }

    private var eventHandlerRef: EventHandlerRef?
    private var voiceRef:        EventHotKeyRef?
    private var editorRef:       EventHotKeyRef?
    private var scratchpadRef:   EventHotKeyRef?

    /// Last registered hotkeys, re-registered by `resume()`.
    private var current: (voice: HotkeyConfig, editor: HotkeyConfig, scratchpad: HotkeyConfig?)?
    private var suspendCount = 0

    private init() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr else { return OSStatus(eventNotHandledErr) }
                switch hkID.id {
                case 1: DispatchQueue.main.async { _voiceCallback?()  }
                case 2: DispatchQueue.main.async { _editorCallback?() }
                case 3: DispatchQueue.main.async { _scratchpadCallback?() }
                default: return OSStatus(eventNotHandledErr)
                }
                return noErr
            },
            1, &spec, nil, &eventHandlerRef
        )
    }

    func register(voice: HotkeyConfig, editor: HotkeyConfig, scratchpad: HotkeyConfig?) {
        current = (voice, editor, scratchpad)
        // While suspended, resume() registers the new set.
        if suspendCount == 0 { registerCurrent() }
    }

    /// Temporarily release the global hotkeys — while a shortcut is being
    /// recorded, a registered key (e.g. F13) must reach the recorder instead
    /// of firing its action. Balanced by `resume()`.
    func suspend() {
        suspendCount += 1
        if suspendCount == 1 { unregisterAll() }
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0 { registerCurrent() }
    }

    private func registerCurrent() {
        unregisterAll()
        guard let current else { return }

        let sig: OSType = "TYPE".utf8.prefix(4).reduce(OSType(0)) { ($0 << 8) | OSType($1) }
        RegisterEventHotKey(current.voice.keyCode,  current.voice.modifiers,
            EventHotKeyID(signature: sig, id: 1), GetApplicationEventTarget(), 0, &voiceRef)
        RegisterEventHotKey(current.editor.keyCode, current.editor.modifiers,
            EventHotKeyID(signature: sig, id: 2), GetApplicationEventTarget(), 0, &editorRef)
        if let scratchpad = current.scratchpad {
            RegisterEventHotKey(scratchpad.keyCode, scratchpad.modifiers,
                EventHotKeyID(signature: sig, id: 3), GetApplicationEventTarget(), 0, &scratchpadRef)
        }
    }

    private func unregisterAll() {
        if let r = voiceRef      { UnregisterEventHotKey(r) }
        if let r = editorRef     { UnregisterEventHotKey(r) }
        if let r = scratchpadRef { UnregisterEventHotKey(r) }
        voiceRef = nil
        editorRef = nil
        scratchpadRef = nil
    }
}
