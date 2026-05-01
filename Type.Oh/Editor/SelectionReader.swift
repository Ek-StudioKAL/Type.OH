import AppKit
import ApplicationServices

@MainActor
final class SelectionReader {

    func readSelectedText(from app: NSRunningApplication?) async -> String? {
        if let text = readViaAX(from: app) { return text }
        return await readViaCopy()
    }

    // MARK: - AX path

    private func readViaAX(from app: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted(), let app else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }

        // Safe: the AX attribute always returns AXUIElement for kAXFocusedUIElementAttribute
        let focused = focusedRef as! AXUIElement // swiftlint:disable:this force_cast

        var selectedRef: CFTypeRef?
        AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef)
        return selectedRef as? String
    }

    // MARK: - Clipboard fallback (⌘C)

    private func readViaCopy() async -> String? {
        let previous = NSPasteboard.general.string(forType: .string)
        NSPasteboard.general.clearContents()

        simulateCopy()
        try? await Task.sleep(for: .milliseconds(100))

        let result = NSPasteboard.general.string(forType: .string)

        NSPasteboard.general.clearContents()
        if let previous { NSPasteboard.general.setString(previous, forType: .string) }

        return result
    }

    private func simulateCopy() {
        let src   = CGEventSource(stateID: .hidSystemState)
        let down  = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let up    = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
