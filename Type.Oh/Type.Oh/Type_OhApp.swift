import SwiftUI

@main
struct TypeOhApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.settingsStore)
        } label: {
            Image(nsImage: menuBarIcon)
                .help("Type.OH")
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
