import AppKit

@MainActor
final class FocusCapture {
    private(set) var capturedApp: NSRunningApplication?

    func capture() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        capturedApp = frontmostApp
    }

    func restore() {
        capturedApp?.activate()
    }
}
