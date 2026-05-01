import SwiftUI

@main
struct TypeOhApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.settingsStore)
        } label: {
            Image(systemName: "waveform")
                .help("Type.OH")
        }

        Settings {
            SettingsWindow()
                .environment(appDelegate.settingsStore)
        }
    }
}
