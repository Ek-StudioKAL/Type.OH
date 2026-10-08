import AppKit
import SwiftUI

/// About Type.OH: the launch splash's card (`LaunchSplash`) with the version,
/// hotkeys and a Settings button in place of the progress bar. Closes with
/// Esc, the Close button, or a click outside.
final class AboutPanelController: NSObject, NSWindowDelegate {
    static let shared = AboutPanelController()
    private var panel: NSPanel?

    @MainActor
    func show(settings: SettingsStore) {
        if let existing = panel {
            bringToFront(existing)
            return
        }

        let content = AboutPanelContent(
            settings: settings,
            onOpenSettings: { [weak self] in
                self?.close()
                NotificationCenter.default.post(name: NSNotification.Name("typeoh.openSettings"), object: nil)
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hc = NSHostingController(rootView: content.typeOhAccent())
        hc.sizingOptions = .preferredContentSize
        let p = AboutWindow(
            contentRect: CGRect(origin: .zero, size: hc.view.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentViewController = hc
        p.setContentSize(hc.view.fittingSize)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.isFloatingPanel = true
        p.level = .floating
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.delegate = self
        p.center()

        bringToFront(p)
        panel = p
    }

    @MainActor
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
        let p = panel
        panel = nil
        p?.close()
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Borderless panels can't become key by default; this one needs to, for Esc.
private final class AboutWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor private struct AboutPanelContent: View {
    @ObservedObject var settings: SettingsStore
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 22) {
            logo

            VStack(spacing: 4) {
                Text("Type.OH")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("Voice + AI for everywhere you type")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(version)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            HStack(spacing: 14) {
                hotkey(settings.voiceHotkey.displayString, label: "Dictate")
                hotkey(settings.editorHotkey.displayString, label: "ReType")
                hotkey(settings.scratchpadHotkey?.displayString ?? "—", label: "LazyPad")
            }

            HStack(spacing: 10) {
                Button("Settings…") { onOpenSettings() }
                Button("Close") { onClose() }
                    .keyboardShortcut(.escape)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(36)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .typeOhFocusEffectDisabled()
    }

    private var logo: some View {
        Group {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(appIcon: .voiceModel, size: 96)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 96, height: 96)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    private func hotkey(_ keys: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(keys)
                .font(.system(.callout, design: .rounded).weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
