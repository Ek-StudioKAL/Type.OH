import AppKit
import SwiftUI

final class AboutPanelController {
    static let shared = AboutPanelController()
    private var panel: NSPanel?

    func show() {
        if let existing = panel {
            bringToFront(existing)
            return
        }

        let content = AboutPanelContent(
            onOpenSettings: { [weak self] in
                self?.close()
                NotificationCenter.default.post(name: NSNotification.Name("typeoh.openSettings"), object: nil)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hostingView = NSHostingView(rootView: content.typeOhAccent())
        let p = NSPanel(
            contentRect: CGRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "About Type.OH"
        p.contentView = hostingView
        p.isFloatingPanel = true
        p.level = .floating
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.center()

        bringToFront(p)
        panel = p
    }

    private func bringToFront(_ p: NSPanel) {
        // Restore whichever activation policy was in effect before we temporarily go .regular.
        let prior = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if prior != .regular {
            NSApp.setActivationPolicy(prior)
        }
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

@MainActor private struct AboutPanelContent: View {
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Type.OH")
                        .font(.largeTitle.bold())
                    Text("Version \(version)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Hotkeys")
                    .font(.headline)
                hotkeyRow(HotkeyConfig.defaultVoice.displayString, label: "Voice Dictation")
                hotkeyRow(HotkeyConfig.defaultEditor.displayString, label: "AI Editor")
                hotkeyRow(HotkeyConfig.defaultScratchpad.displayString, label: "LazyPad")
            }

            Divider()

            HStack {
                Button("Settings…") { onOpenSettings() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.escape)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    @ViewBuilder
    private func hotkeyRow(_ keys: String, label: String) -> some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }
}
