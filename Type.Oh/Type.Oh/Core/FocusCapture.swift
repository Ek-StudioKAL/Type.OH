import AppKit

@MainActor
final class FocusCapture {
    private(set) var capturedApp: NSRunningApplication?

    func capture() {
        capturedApp = NSWorkspace.shared.frontmostApplication
    }

    func restore() {
        capturedApp?.activate()
    }
}
