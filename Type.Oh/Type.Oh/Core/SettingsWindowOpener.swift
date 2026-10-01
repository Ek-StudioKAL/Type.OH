import AppKit
import Foundation

/// Opens the SwiftUI `Settings` scene from anywhere, including AppKit code.
///
/// macOS 14+ ignores the `showSettingsWindow:` responder action ("Please use
/// SettingsLink for opening the Settings scene"), so there the app uses
/// SwiftUI's `openSettings` action, registered by `MenuBarIconLabel` (which is
/// alive for the app's whole lifetime). macOS 13 has no `openSettings`; the
/// responder action is the way to open Settings there.
@MainActor
enum SettingsWindowOpener {
    /// `openSettings` from the SwiftUI environment (macOS 14+).
    static var openSettingsAction: (() -> Void)?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
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
