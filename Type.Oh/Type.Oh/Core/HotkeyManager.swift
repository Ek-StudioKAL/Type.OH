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
        if let r = voiceRef  { UnregisterEventHotKey(r) }
        if let r = editorRef { UnregisterEventHotKey(r) }
        if let r = scratchpadRef { UnregisterEventHotKey(r) }

        let sig: OSType = "TYPE".utf8.prefix(4).reduce(OSType(0)) { ($0 << 8) | OSType($1) }
        RegisterEventHotKey(voice.keyCode,  voice.modifiers,
            EventHotKeyID(signature: sig, id: 1), GetApplicationEventTarget(), 0, &voiceRef)
        RegisterEventHotKey(editor.keyCode, editor.modifiers,
            EventHotKeyID(signature: sig, id: 2), GetApplicationEventTarget(), 0, &editorRef)
        if let scratchpad {
            RegisterEventHotKey(scratchpad.keyCode, scratchpad.modifiers,
                EventHotKeyID(signature: sig, id: 3), GetApplicationEventTarget(), 0, &scratchpadRef)
        } else {
            scratchpadRef = nil
        }
    }
}
