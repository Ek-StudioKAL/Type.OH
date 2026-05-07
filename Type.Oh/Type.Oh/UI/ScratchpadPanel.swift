import AppKit
import SwiftUI

final class ScratchpadPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScratchpadPanelController {
    private let panel: ScratchpadPanel

    init(settingsStore: SettingsStore, pasteService: PasteService, store: ScratchpadStore) {
        let content = ScratchpadView(pasteService: pasteService, store: store)
            .environment(settingsStore)

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = []

        panel = ScratchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "LazyPad"
        panel.contentViewController = hostingController
        panel.setContentSize(CGSize(width: 1180, height: 720))
        panel.minSize = CGSize(width: 960, height: 520)
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.tabbingMode = .disallowed
        panel.center()
    }

    func show(using settingsStore: SettingsStore) {
        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(settingsStore.showInDock ? .regular : .accessory)
    }
}
