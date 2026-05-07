import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Shared state — injected into every SwiftUI scene via .environment()
    let settingsStore = SettingsStore()

    private let focusCapture    = FocusCapture()
    private lazy var pasteService     = PasteService(focusCapture: focusCapture)
    private lazy var selectionReader  = SelectionReader()
    private      let audioRecorder    = AudioRecorder()
    private      let whisperService   = WhisperService()
    private      let scratchpadStore  = ScratchpadStore()

    private var recordingPanel:  NSPanel?
    private var editorPanel:     NSPanel?
    private var onboardingPanel: NSPanel?
    private var scratchpadPanelController: ScratchpadPanelController?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settingsStore.showInDock ? .regular : .accessory)
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            NSApp.applicationIconImage = appIcon
        }

        HotkeyManager.shared.onVoiceHotkey  = { [weak self] in Task { @MainActor in await self?.handleVoiceKey()  } }
        HotkeyManager.shared.onEditorHotkey = { [weak self] in Task { @MainActor in await self?.handleEditorKey() } }
        HotkeyManager.shared.onScratchpadHotkey = { [weak self] in Task { @MainActor in self?.openScratchpad() } }
        applyHotkeys()

        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.showAbout"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showAboutPanel() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.voiceHotkey"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleVoiceKey() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.editorHotkey.sticky"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showEditorPanel(with: "", sticky: true) }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.showOnboarding"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showOnboarding() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.openScratchpad"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openScratchpad() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.hotkeysChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyHotkeys() }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.openSettings"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                // showSettingsWindow: is the SwiftUI Settings scene's private action selector (macOS 13+)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        NotificationCenter.default.addObserver(forName: .whisperModelDownloaded, object: nil, queue: .main) { [weak self] note in
            guard let self, let modelID = note.object as? String,
                  self.settingsStore.whisperModel == modelID,
                  let folder = ModelManager.shared.modelFolderURL(for: modelID) else { return }
            Task { @MainActor in
                try? await self.whisperService.loadModel(name: modelID, at: folder)
            }
        }

        // Pre-load the last-used Whisper model only if it's already downloaded
        if let folder = ModelManager.shared.modelFolderURL(for: settingsStore.whisperModel),
           ModelManager.shared.isDownloaded(settingsStore.whisperModel) {
            let name = settingsStore.whisperModel
            Task { try? await whisperService.loadModel(name: name, at: folder) }
        }

        // First-launch onboarding handles permission prompts itself.
        // For returning users with missing AX, fall back to the system trust prompt.
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        } else if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openScratchpad()
        return true
    }

    // MARK: - Voice flow

    private func handleVoiceKey() async {
        if audioRecorder.isRecording {
            guard let samples = audioRecorder.stop() else { return }
            hideRecordingPanel()
            do {
                let text = try await whisperService.transcribe(audio: samples)
                await pasteService.paste(text)
            } catch {
                showBannerError(error.localizedDescription)
            }
        } else {
            let modelName = settingsStore.whisperModel
            guard let folder = ModelManager.shared.modelFolderURL(for: modelName) else {
                showBannerError("No Whisper model downloaded. Open Settings → Models to download one.")
                return
            }
            do {
                try await whisperService.ensureLoaded(name: modelName, at: folder)
            } catch {
                showBannerError("Failed to load Whisper model: \(error.localizedDescription)")
                return
            }
            focusCapture.capture()
            do {
                try await audioRecorder.start()
                showRecordingPanel()
            } catch {
                showBannerError("Microphone access denied. Enable it in System Settings → Privacy.")
            }
        }
    }

    private func showRecordingPanel() {
        let hc = NSHostingController(rootView: RecordingOverlay())
        hc.sizingOptions = .preferredContentSize
        let panel = makePanel(titled: false)
        panel.contentViewController = hc

        if let screen = NSScreen.main {
            let size = hc.view.fittingSize
            panel.setContentSize(size)
            panel.setFrameOrigin(CGPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.minY + 60
            ))
        }
        bringPanelFront(panel)
        recordingPanel = panel
    }

    private func hideRecordingPanel() {
        recordingPanel?.close()
        recordingPanel = nil
    }

    // MARK: - Editor flow

    private func handleEditorKey() async {
        focusCapture.capture()
        let capturedApp = focusCapture.capturedApp
        NSLog("[Type.OH] Editor hotkey — AX trusted: %d, source: %@",
              AXIsProcessTrusted() ? 1 : 0,
              capturedApp?.localizedName ?? "(none)")
        let text = await selectionReader.readSelectedText(from: capturedApp)
        NSLog("[Type.OH] Selection captured: %d chars", text?.count ?? -1)
        showEditorPanel(with: text ?? "")
    }

    func showEditorPanel(with text: String, sticky: Bool = false) {
        editorPanel?.close()

        let content = AIEditorPanel(
            originalText: text,
            isSticky: sticky,
            onApply: { [weak self] result in
                guard let self else { return }
                if !sticky {
                    editorPanel?.close()
                    editorPanel = nil
                }
                Task { await self.pasteService.paste(result) }
            },
            onCancel: { [weak self] in
                self?.editorPanel?.close()
                self?.editorPanel = nil
            }
        )
        .environment(settingsStore)

        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = .preferredContentSize
        let panel = makePanel(titled: true)
        panel.title = sticky ? "ReTypeOH" : "AI Editor"
        panel.contentViewController = hc
        panel.minSize = CGSize(width: 460, height: 220)
        panel.center()
        bringPanelFront(panel)
        editorPanel = panel
    }

    // MARK: - About panel

    private func showAboutPanel() {
        AboutPanelController.shared.show()
    }

    // MARK: - Onboarding

    func showOnboarding() {
        onboardingPanel?.close()
        settingsStore.hasCompletedOnboarding = false

        let content = OnboardingWizard(onFinish: { [weak self] in
            self?.onboardingPanel?.close()
            self?.onboardingPanel = nil
            self?.openScratchpad()
        })
        .environment(settingsStore)

        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = .preferredContentSize
        let panel = makePanel(titled: true)
        panel.title = "Welcome to Type.OH"
        panel.contentViewController = hc
        panel.center()
        bringPanelFront(panel)
        onboardingPanel = panel
    }

    func openScratchpad() {
        focusCapture.capture()

        if scratchpadPanelController == nil {
            scratchpadPanelController = ScratchpadPanelController(
                settingsStore: settingsStore,
                pasteService: pasteService,
                store: scratchpadStore
            )
        }

        scratchpadPanelController?.show(using: settingsStore)
    }

    // MARK: - Helpers

    private func makePanel(titled: Bool) -> NSPanel {
        // NSHostingController as contentViewController avoids the infinite updateConstraints
        // loop that crashes when NSHostingView is used as contentView in a non-resizable panel.
        // Titled panels get .resizable so the window can grow/shrink as SwiftUI content changes.
        let style: NSWindow.StyleMask = titled
            ? [.titled, .closable, .resizable, .nonactivatingPanel]
            : [.nonactivatingPanel, .borderless]

        let panel = NSPanel(
            contentRect: .zero,
            styleMask:   style,
            backing:     .buffered,
            defer:       false
        )
        panel.isFloatingPanel = true
        panel.level           = .floating
        panel.backgroundColor = titled ? .windowBackgroundColor : .clear
        panel.isOpaque        = titled
        panel.hasShadow       = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func bringPanelFront(_ panel: NSPanel) {
        // Briefly promote to regular policy so NSApp.activate() raises the window
        // above foreground apps, then revert to the user's preferred policy.
        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        NSApp.setActivationPolicy(settingsStore.showInDock ? .regular : .accessory)
    }

    private func showBannerError(_ message: String) {
        NSLog("[Type.OH] Error: %@", message)
        ToastOverlay.shared.show(message)
    }

    private func applyHotkeys() {
        HotkeyManager.shared.register(
            voice: settingsStore.voiceHotkey,
            editor: settingsStore.editorHotkey,
            scratchpad: settingsStore.scratchpadHotkey
        )
    }
}
