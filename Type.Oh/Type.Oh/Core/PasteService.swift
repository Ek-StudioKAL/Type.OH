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

    func paste(_ text: String, preferDirectReplacement: Bool = false) async {
        focusCapture.restore()
        // Give the target app time to become key before replacement or paste arrives.
        try? await Task.sleep(for: .milliseconds(180))

        if preferDirectReplacement,
           await focusCapture.replaceCapturedSelection(with: text) {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
