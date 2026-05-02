import AppKit
import ApplicationServices

@MainActor
final class SelectionReader {

    func readSelectedText(from app: NSRunningApplication?) async -> String? {
        if let text = readViaAX(from: app) { return text }
        return await readViaCopy(from: app)
    }

    // MARK: - AX path

    private func readViaAX(from app: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted(), let app else { return nil }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusError == .success, let focusedRef else {
            NSLog("[Type.OH] AX focusedElement error: %d", focusError.rawValue)
            return nil
        }

        let focused = focusedRef as! AXUIElement // swiftlint:disable:this force_cast

        var selectedRef: CFTypeRef?
        let selError = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef)
        if selError != .success {
            NSLog("[Type.OH] AX selectedText error: %d", selError.rawValue)
        }
        return selectedRef as? String
    }

    // MARK: - Clipboard fallback (⌘C)

    private func readViaCopy(from app: NSRunningApplication?) async -> String? {
        let previous = NSPasteboard.general.string(forType: .string)

        // Two attempts: Electron / browser apps can be slow to handle ⌘C
        for attempt in 1...2 {
            NSPasteboard.general.clearContents()

            // Re-activate the source app so ⌘C lands there, not on our process.
            // 150 ms gives the window server time to actually hand focus back.
            if let app {
                app.activate()
                try? await Task.sleep(for: .milliseconds(150))
            }

            simulateCopy()
            // 350 ms covers Electron, heavy web views, and other slow clipboard writers
            try? await Task.sleep(for: .milliseconds(350))

            if let result = NSPasteboard.general.string(forType: .string), !result.isEmpty {
                NSPasteboard.general.clearContents()
                if let previous { NSPasteboard.general.setString(previous, forType: .string) }
                return result
            }

            NSLog("[Type.OH] readViaCopy attempt %d returned empty — %@",
                  attempt, attempt < 2 ? "retrying" : "giving up")
        }

        NSPasteboard.general.clearContents()
        if let previous { NSPasteboard.general.setString(previous, forType: .string) }
        return nil
    }

    private func simulateCopy() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
