import SwiftUI

struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Type.OH") {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.showAbout"), object: nil)
        }

        Button("Dictate") {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.voiceHotkey"), object: nil)
        }

        Button("ReTypeOH") {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.editorHotkey.sticky"), object: nil)
        }

        Button("Settings…") { openSettings() }

        Divider()

        Button("Quit Type.OH") { NSApp.terminate(nil) }
    }
}
