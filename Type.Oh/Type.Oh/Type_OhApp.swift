import SwiftUI

@main
struct TypeOhApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.settingsStore)
        } label: {
            MenuBarIconLabel(image: menuBarIcon)
        }

        Settings {
            SettingsWindow()
                .environment(appDelegate.settingsStore)
        }
    }

    private var menuBarIcon: NSImage {
        let icon = NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage
        let sized = NSImage(size: NSSize(width: 16, height: 16))
        sized.lockFocus()
        if let icon {
            icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
        }
        sized.unlockFocus()
        return sized
    }
}

private struct MenuBarIconLabel: View {
    @Environment(\.openSettings) private var openSettings

    let image: NSImage

    var body: some View {
        Image(nsImage: image)
            .help("Type.OH")
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

    private func openSettingsWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
