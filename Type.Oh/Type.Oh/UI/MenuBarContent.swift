import SwiftUI

struct MenuBarContent: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Type.OH")
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)

        Divider()

        Button("Settings…") { openSettings() }
            .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Type.OH") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
