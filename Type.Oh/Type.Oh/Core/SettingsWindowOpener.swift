import AppKit
import Foundation

/// Opens the SwiftUI `Settings` scene. Replaces `@Environment(\.openSettings)`
/// (macOS 14+) with the AppKit responder action that the Settings scene
/// registers on macOS 13.
@MainActor
enum SettingsWindowOpener {
    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Open Settings on a specific tab. The pending tab is written to
    /// UserDefaults for a freshly mounted `SettingsWindow` (consumed in
    /// `.onAppear`), and also posted for one that is already alive.
    static func open(at tab: SettingsTab) {
        SettingsTabRoute.setPendingTab(tab)
        open()
        NotificationCenter.default.post(
            name: SettingsTabRoute.notificationName,
            object: tab.rawValue
        )
    }
}
