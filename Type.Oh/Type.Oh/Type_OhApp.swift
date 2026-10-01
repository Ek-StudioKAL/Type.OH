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
