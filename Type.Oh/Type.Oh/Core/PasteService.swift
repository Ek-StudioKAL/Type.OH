import AppKit

@MainActor
final class PasteService {
    private let focusCapture: FocusCapture

    var hasCapturedTarget: Bool {
        focusCapture.capturedApp != nil
    }

    init(focusCapture: FocusCapture) {
        self.focusCapture = focusCapture
    }

    func paste(_ text: String) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        focusCapture.restore()
        // Give the target app time to become key before the keystroke arrives.
        try? await Task.sleep(for: .milliseconds(150))
        simulatePaste()
    }

    private func simulatePaste() {
        let src     = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
