import AppKit
import ApplicationServices

@MainActor
final class FocusCapture {
    private(set) var capturedApp: NSRunningApplication?
    private var capturedFocusedElement: AXUIElement?

    func capture() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        capturedApp = frontmostApp
        capturedFocusedElement = focusedElement(in: frontmostApp)
    }

    func restore() {
        capturedApp?.activate()
        restoreFocusedElement()
    }

    func replaceCapturedSelection(with text: String) async -> Bool {
        guard AXIsProcessTrusted(), let element = capturedFocusedElement else { return false }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        let previousSelection = selectedText(in: element)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            return false
        }

        guard let previousSelection, previousSelection != text else { return true }
        try? await Task.sleep(for: .milliseconds(80))
        let currentSelection = selectedText(in: element)
        return currentSelection != previousSelection
    }

    private func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(focusedRef, to: AXUIElement.self)
    }

    private func restoreFocusedElement() {
        guard AXIsProcessTrusted(),
              let app = capturedApp,
              let element = capturedFocusedElement else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXFocusedUIElementAttribute as CFString, element)
    }

    private func selectedText(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? String
    }
}
