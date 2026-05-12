import AppKit
import ApplicationServices

/// What the reader managed to capture from the foreground app.
struct CapturedSelection {
    /// The selected text, or nil if nothing was selected / accessible.
    let text: String?
    /// True when AX reports the focused element will accept a paste
    /// (i.e. `kAXSelectedTextAttribute` is settable). When false, ReType
    /// should redirect to LazyPad instead of trying to paste back.
    let isEditable: Bool
}

@MainActor
final class SelectionReader {

    func readSelectedText(from app: NSRunningApplication?) async -> CapturedSelection {
        let axResult = readViaAX(from: app)
        if let text = axResult.text {
            return CapturedSelection(text: text, isEditable: axResult.isEditable)
        }

        // AX gave us nothing. Try the clipboard fallback. We can't reliably know
        // editability without AX, so we assume editable=false to be safe (route
        // to LazyPad) unless AX *positively* confirmed editability.
        let copied = await readViaCopy(from: app)
        return CapturedSelection(text: copied, isEditable: axResult.isEditable)
    }

    // MARK: - AX path

    private struct AXReadResult {
        let text: String?
        let isEditable: Bool
    }

    private func readViaAX(from app: NSRunningApplication?) -> AXReadResult {
        guard AXIsProcessTrusted(), let app else {
            return AXReadResult(text: nil, isEditable: false)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        let focusError = AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        guard focusError == .success, let focusedRef else {
            NSLog("[Type.OH] AX focusedElement error: %d", focusError.rawValue)
            return AXReadResult(text: nil, isEditable: false)
        }

        // AXUIElementCreateApplication etc. return AXUIElementRef typed as
        // CFTypeRef. Verify the CoreFoundation type before bridging so unusual
        // Catalyst/PDF surfaces fail closed instead of trapping.
        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            NSLog("[Type.OH] AX focusedElement returned non-element type")
            return AXReadResult(text: nil, isEditable: false)
        }
        let focused = unsafeBitCast(focusedRef, to: AXUIElement.self)

        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute as CFString, &settable)
        let editable = settable.boolValue

        var selectedRef: CFTypeRef?
        let selError = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef)
        if selError != .success {
            NSLog("[Type.OH] AX selectedText error: %d", selError.rawValue)
        }
        let text = selectedRef as? String
        let nonEmpty = (text?.isEmpty == false) ? text : nil
        return AXReadResult(text: nonEmpty, isEditable: editable)
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
