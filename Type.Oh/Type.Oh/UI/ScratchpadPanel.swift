import AppKit
import SwiftUI

final class ScratchpadPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScratchpadPanelController {
    private static let minimumWindowSize = CGSize(width: 780, height: 240)
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
        panel.setContentSize(CGSize(width: 1180, height: 740))
        panel.minSize = Self.minimumWindowSize
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        panel.backgroundColor = .windowBackgroundColor
        panel.isOpaque = true
        panel.hasShadow = true
        panel.tabbingMode = .disallowed
        // Drag the window by any non-interactive area (gaps between toolbar
        // icons, empty sidebar space, status bar). SwiftUI buttons keep their
        // own hit regions; everything else falls through to the window.
        panel.isMovableByWindowBackground = true
        panel.center()
    }

    func show(using settingsStore: SettingsStore, insertingText: String? = nil) {
        NSApp.setActivationPolicy(.regular)
        enforceMinimumWindowSize()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(settingsStore.showInDock ? .regular : .accessory)

        if let insertingText, !insertingText.isEmpty {
            // Defer one tick so ScratchpadView is mounted and its notification
            // observer is registered before we post.
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("typeoh.scratchpad.insertText"),
                    object: insertingText
                )
            }
        }
    }

    private func enforceMinimumWindowSize() {
        let frame = panel.frame
        let width = max(frame.width, Self.minimumWindowSize.width)
        let height = max(frame.height, Self.minimumWindowSize.height)
        guard width != frame.width || height != frame.height else { return }
        panel.setFrame(
            NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height),
            display: true
        )
    }
}
