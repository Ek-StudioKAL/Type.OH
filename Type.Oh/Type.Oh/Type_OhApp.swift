import SwiftUI

@main
struct TypeOhApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appDelegate.settingsStore)
                .typeOhAccent()
        } label: {
            MenuBarIconLabel()
        }

        Settings {
            SettingsWindow()
                .environmentObject(appDelegate.settingsStore)
                .typeOhAccent()
                .typeOhFocusEffectDisabled()
        }
    }
}

@MainActor private struct MenuBarIconLabel: View {

    var body: some View {
        Image(nsImage: menuBarImage)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: 18, height: 18)
            .help("Type.OH")
            .background {
                if #available(macOS 14.0, *) {
                    OpenSettingsActionBridge()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("typeoh.openSettings"))) { _ in
                openSettingsWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: SettingsTabRoute.notificationName)) { note in
                if let requestedTab = (note.object as? String).flatMap(SettingsTab.init(rawValue:)) {
                    SettingsTabRoute.setPendingTab(requestedTab)
                }
                openSettingsWindow()
            }
    }

    private var menuBarImage: NSImage {
        let image = NSImage(named: "Menubar")
            ?? NSImage(named: "menuBarIcon")
            ?? NSImage(named: "Type.OH-logo")
            ?? NSImage(named: NSImage.applicationIconName)
            ?? NSApp.applicationIconImage
            ?? NSImage()
        image.isTemplate = false
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func openSettingsWindow() {
        SettingsWindowOpener.open()
    }
}

/// Hands SwiftUI's `openSettings` action to `SettingsWindowOpener`, so AppKit
/// code (URL scheme, panels, notifications) can open Settings on macOS 14+.
@available(macOS 14.0, *)
@MainActor private struct OpenSettingsActionBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .onAppear {
                let action = openSettings
                SettingsWindowOpener.openSettingsAction = { action() }
            }
    }
}
