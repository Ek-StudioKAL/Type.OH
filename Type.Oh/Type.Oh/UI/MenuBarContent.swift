import SwiftUI

@MainActor struct MenuBarContent: View {

    var body: some View {
        Button("LazyPad") {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.openScratchpad"), object: nil)
        }

        Button("ReType") {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.editorHotkey.sticky"), object: nil)
        }

        Button("Dictate") {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.voiceHotkey"), object: nil)
        }

        Button("Settings…") {
            SettingsWindowOpener.open()
        }

        Divider()

        Button("Quit Type.OH") { NSApp.terminate(nil) }
    }
}
