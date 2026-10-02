import AppKit
import Carbon
import SwiftUI

extension HotkeyConfig {
    var displayString: String {
        modifierSymbols(for: modifiers) + keySymbol(for: keyCode)
    }

    var hasModifiers: Bool {
        modifiers != 0
    }

    /// Function keys (F1–F20) may be used without modifiers. F13–F19 are the
    /// safest — almost no app or system shortcut claims them; a bare F1–F12
    /// hotkey takes that key away from every other app.
    var isFunctionKey: Bool {
        functionKeyCodes.contains(keyCode)
    }
}

func validateHotkeys(voice: HotkeyConfig?, editor: HotkeyConfig?, scratchpad: HotkeyConfig?) -> String? {
    guard let voice else { return "Voice recording needs a hotkey." }
    guard let editor else { return "AI Editor needs a hotkey." }

    func needsModifierError(_ name: String, _ hk: HotkeyConfig) -> String? {
        guard !hk.hasModifiers && !hk.isFunctionKey else { return nil }
        return "\(name) needs at least one modifier key (or a function key)."
    }
    if let err = needsModifierError("Voice recording", voice) { return err }
    if let err = needsModifierError("AI Editor", editor)     { return err }
    if let scratchpad, let err = needsModifierError("LazyPad", scratchpad) { return err }

    let assignments = [
        ("Voice recording", voice),
        ("AI Editor", editor),
        ("LazyPad", scratchpad)
    ].compactMap { assignment -> (String, HotkeyConfig)? in
        guard let hotkey = assignment.1 else { return nil }
        return (assignment.0, hotkey)
    }

    for (index, lhs) in assignments.enumerated() {
        for rhs in assignments.dropFirst(index + 1) where lhs.1 == rhs.1 {
            return "\(lhs.0) and \(rhs.0) cannot use the same hotkey."
        }
    }

    return nil
}

@MainActor struct HotkeyConfigurationEditor: View {
    @Binding var voiceHotkey: HotkeyConfig
    @Binding var editorHotkey: HotkeyConfig
    @Binding var scratchpadHotkey: HotkeyConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hotkeyRow(
                title: "Voice recording",
                detail: "Hold to dictate text into the last focused app.",
                hotkey: Binding(
                    get: { voiceHotkey },
                    set: { if let hotkey = $0 { voiceHotkey = hotkey } }
                ),
                onClear: { voiceHotkey = .defaultVoice }
            )

            hotkeyRow(
                title: "AI Editor",
                detail: "Open the selected-text editor from anywhere.",
                hotkey: Binding(
                    get: { editorHotkey },
                    set: { if let hotkey = $0 { editorHotkey = hotkey } }
                ),
                onClear: { editorHotkey = .defaultEditor }
            )

            hotkeyRow(
                title: "LazyPad",
                detail: "Open the LazyPad workspace.",
                hotkey: $scratchpadHotkey,
                onClear: { scratchpadHotkey = .defaultScratchpad }
            )

            Text("Defaults are \(HotkeyConfig.defaultVoice.displayString) for Voice, \(HotkeyConfig.defaultEditor.displayString) for AI Editor, and \(HotkeyConfig.defaultScratchpad.displayString) for LazyPad. Shortcuts need ⌘ / ⌃ / ⌥ / ⇧, except function keys (F1–F20), which work alone. On a MacBook keyboard, hold fn while pressing F1–F12.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func hotkeyRow(
        title: String,
        detail: String,
        hotkey: Binding<HotkeyConfig?>,
        onClear: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HotkeyRecorderField(hotkey: hotkey)
                .frame(width: 150)

            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear / reset this hotkey")
        }
    }
}

@MainActor struct HotkeyRecorderField: NSViewRepresentable {
    @Binding var hotkey: HotkeyConfig?

    func makeCoordinator() -> Coordinator {
        Coordinator(hotkey: $hotkey)
    }

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton()
        button.onCapture = { hotkey in
            context.coordinator.hotkey = hotkey
        }
        return button
    }

    func updateNSView(_ button: HotkeyRecorderButton, context: Context) {
        button.displayedHotkey = hotkey
    }

    final class Coordinator {
        @Binding var hotkey: HotkeyConfig?

        init(hotkey: Binding<HotkeyConfig?>) {
            _hotkey = hotkey
        }
    }
}

final class HotkeyRecorderButton: NSButton {
    var onCapture: ((HotkeyConfig?) -> Void)?
    private var isRecording = false

    /// Local event monitor active during recording. We use a monitor instead of
    /// overriding keyDown/performKeyEquivalent because NSButton's own routing
    /// drops many non-Cmd events — the system either handles
    /// them as key equivalents on the window before they reach this view, or
    /// NSButton swallows them. The monitor sees every key event at the app
    /// level and lets us return nil to consume it.
    private var eventMonitor: Any?

    var displayedHotkey: HotkeyConfig? {
        didSet {
            updateDisplay()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        focusRingType = .default
        action = #selector(toggleRecording)
        target = self
        updateDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only take keyboard focus while recording. On macOS 13, a key press that
    /// reaches `NSControl.keyDown` outside recording (e.g. Tab after a capture)
    /// enters AppKit's keyboard-UI traversal (`selectNextKeyView`), and SwiftUI's
    /// focus bridge recurses on it endlessly — the Settings window hangs at
    /// 100% CPU. Staying out of the key-view loop avoids that path entirely.
    override var acceptsFirstResponder: Bool { isRecording }
    override var canBecomeKeyView: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }

    override func keyDown(with event: NSEvent) {
        // The local monitor handles keys while recording; when not recording
        // swallow the event instead of letting NSControl run keyboard UI.
        if isRecording { capture(event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd-shortcuts pressed while recording are ours (the monitor consumes
        // them); otherwise let the window handle them normally.
        isRecording
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Closing the window mid-recording must still resume the global hotkeys.
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    @objc
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        // The app's own global hotkeys would swallow their keys (e.g. F13
        // starting dictation) before the recorder sees them.
        HotkeyManager.shared.suspend()
        window?.makeFirstResponder(self)
        installMonitor()
        updateDisplay()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        HotkeyManager.shared.resume()
        removeMonitor()
        updateDisplay()
        // Give focus back to the window so later key presses don't land here.
        if let window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    private func installMonitor() {
        removeMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.type == .flagsChanged {
                self.updateDisplay()
                // Pass flag changes through so the rest of the UI still sees them.
                return event
            }
            // .keyDown — capture and swallow so no other handler fires.
            self.capture(event)
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitor = nil
    }

    override func flagsChanged(with event: NSEvent) {
        // The local monitor handles updates while recording. Outside of
        // recording we let AppKit do its default thing.
        if !isRecording {
            super.flagsChanged(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecording {
            stopRecording()
        }
        return didResign
    }

    private func capture(_ event: NSEvent) {
        guard isRecording else { return }

        // Escape cancels recording without changing the hotkey.
        if event.keyCode == 53 {
            stopRecording()
            return
        }

        // Ignore raw modifier key-downs — they'd never make a valid shortcut on
        // their own. The user has to press a real key while holding modifiers.
        if modifierOnlyKeyCodes.contains(event.keyCode) {
            return
        }

        guard let hotkey = makeHotkey(from: event) else {
            // No modifier held → invalid. Beep but stay in recording mode so the
            // user can try again without re-clicking the field.
            NSSound.beep()
            return
        }

        onCapture?(hotkey)
        stopRecording()
    }

    private func updateDisplay() {
        let newTitle: String
        if isRecording {
            let symbols = modifierSymbols(
                for: carbonModifiers(
                    from: NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                )
            )
            newTitle = symbols.isEmpty ? "Type shortcut" : "\(symbols)…"
        } else {
            newTitle = displayedHotkey?.displayString ?? "Not set"
        }
        // Only touch `title` when it changes: every assignment invalidates
        // layout, which re-enters SwiftUI's updateNSView.
        if title != newTitle {
            title = newTitle
            needsDisplay = true
        }
    }
}

private let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

private func makeHotkey(from event: NSEvent) -> HotkeyConfig? {
    let relevantFlags = event.modifierFlags
        .intersection(.deviceIndependentFlagsMask)
        .intersection([.command, .option, .control, .shift])
    let modifiers = carbonModifiers(from: relevantFlags)
    let hotkey = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    guard modifiers != 0 || hotkey.isFunctionKey else { return nil }
    return hotkey
}

/// Carbon key codes of F1–F20.
private let functionKeyCodes: Set<UInt32> = [
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1–F12
    105, 107, 113, 106, 64, 79, 80, 90,                     // F13–F20
]

private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var modifiers: UInt32 = 0
    if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
    if flags.contains(.option) { modifiers |= UInt32(optionKey) }
    if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
    return modifiers
}

private func modifierSymbols(for modifiers: UInt32) -> String {
    [
        (UInt32(controlKey), "⌃"),
        (UInt32(optionKey), "⌥"),
        (UInt32(shiftKey), "⇧"),
        (UInt32(cmdKey), "⌘")
    ]
    .filter { modifiers & $0.0 != 0 }
    .map(\.1)
    .joined()
}

private func keySymbol(for keyCode: UInt32) -> String {
    switch keyCode {
    case 0: "A"
    case 1: "S"
    case 2: "D"
    case 3: "F"
    case 4: "H"
    case 5: "G"
    case 6: "Z"
    case 7: "X"
    case 8: "C"
    case 9: "V"
    case 11: "B"
    case 12: "Q"
    case 13: "W"
    case 14: "E"
    case 15: "R"
    case 16: "Y"
    case 17: "T"
    case 18: "1"
    case 19: "2"
    case 20: "3"
    case 21: "4"
    case 22: "6"
    case 23: "5"
    case 24: "="
    case 25: "9"
    case 26: "7"
    case 27: "-"
    case 28: "8"
    case 29: "0"
    case 30: "]"
    case 31: "O"
    case 32: "U"
    case 33: "["
    case 34: "I"
    case 35: "P"
    case 37: "L"
    case 38: "J"
    case 39: "'"
    case 40: "K"
    case 41: ";"
    case 42: "\\"
    case 43: ","
    case 44: "/"
    case 45: "N"
    case 46: "M"
    case 47: "."
    case 50: "`"
    case 36: "↩"
    case 48: "⇥"
    case 49: "Space"
    case 51: "⌫"
    case 53: "⎋"
    case 64: "F17"
    case 71: "⌧"
    case 76: "↩"
    case 79: "F18"
    case 80: "F19"
    case 90: "F20"
    case 96: "F5"
    case 97: "F6"
    case 98: "F7"
    case 99: "F3"
    case 100: "F8"
    case 101: "F9"
    case 103: "F11"
    case 105: "F13"
    case 106: "F16"
    case 107: "F14"
    case 109: "F10"
    case 111: "F12"
    case 113: "F15"
    case 114: "Help"
    case 115: "↖"
    case 116: "⇞"
    case 117: "⌦"
    case 118: "F4"
    case 119: "↘"
    case 120: "F2"
    case 121: "⇟"
    case 122: "F1"
    case 123: "←"
    case 124: "→"
    case 125: "↓"
    case 126: "↑"
    default: "Key \(keyCode)"
    }
}
