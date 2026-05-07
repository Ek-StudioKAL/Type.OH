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
}

func validateHotkeys(voice: HotkeyConfig?, editor: HotkeyConfig?, scratchpad: HotkeyConfig?) -> String? {
    guard let voice else { return "Voice recording needs a hotkey." }
    guard let editor else { return "AI Editor needs a hotkey." }
    guard voice.hasModifiers, editor.hasModifiers else { return "Global hotkeys must include at least one modifier key." }
    if let scratchpad, !scratchpad.hasModifiers {
        return "LazyPad hotkeys must include at least one modifier key."
    }

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

struct HotkeyConfigurationEditor: View {
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
                )
            )

            hotkeyRow(
                title: "AI Editor",
                detail: "Open the selected-text editor from anywhere.",
                hotkey: Binding(
                    get: { editorHotkey },
                    set: { if let hotkey = $0 { editorHotkey = hotkey } }
                )
            )

            hotkeyRow(
                title: "LazyPad",
                detail: "Optional. Leave empty if you do not want a global shortcut.",
                hotkey: $scratchpadHotkey,
                allowsClearing: true
            )

            Text("Record a shortcut with at least one modifier key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func hotkeyRow(title: String, detail: String, hotkey: Binding<HotkeyConfig?>, allowsClearing: Bool = false) -> some View {
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

            if allowsClearing {
                Button("Clear") {
                    hotkey.wrappedValue = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct HotkeyRecorderField: NSViewRepresentable {
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
        action = #selector(beginRecording)
        target = self
        updateDisplay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc
    private func beginRecording() {
        guard !isRecording else {
            stopRecording()
            return
        }

        isRecording = true
        window?.makeFirstResponder(self)
        updateDisplay()
    }

    private func stopRecording() {
        isRecording = false
        updateDisplay()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        updateDisplay()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
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

        if event.keyCode == 53 {
            stopRecording()
            return
        }

        if modifierOnlyKeyCodes.contains(event.keyCode) {
            return
        }

        guard let hotkey = makeHotkey(from: event) else {
            NSSound.beep()
            return
        }

        onCapture?(hotkey)
        stopRecording()
    }

    private func updateDisplay() {
        if isRecording {
            let symbols = modifierSymbols(
                for: carbonModifiers(
                    from: NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
                )
            )
            title = symbols.isEmpty ? "Type shortcut" : "\(symbols)…"
        } else {
            title = displayedHotkey?.displayString ?? "Not set"
        }
        needsDisplay = true
    }
}

private let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

private func makeHotkey(from event: NSEvent) -> HotkeyConfig? {
    let relevantFlags = event.modifierFlags
        .intersection(.deviceIndependentFlagsMask)
        .intersection([.command, .option, .control, .shift])
    let modifiers = carbonModifiers(from: relevantFlags)
    guard modifiers != 0 else { return nil }
    return HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: modifiers)
}

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
    case 71: "⌧"
    case 76: "↩"
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
