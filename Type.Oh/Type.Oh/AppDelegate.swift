import AppKit
import ApplicationServices
import AVFoundation
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
    private var splashPanel:     NSPanel?
    private var scratchpadPanelController: ScratchpadPanelController?
    private var recordingKeyMonitor: Any?
    private var recordingDestination: RecordingDestination = .focusedApp

    private enum RecordingDestination {
        case focusedApp
        case scratchpad
    }

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.install()
        NSApp.setActivationPolicy(settingsStore.showInDock ? .regular : .accessory)
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            NSApp.applicationIconImage = appIcon
        }

        HotkeyManager.shared.onVoiceHotkey = { [weak self] in
            guard let self else { return }
            Task { await self.handleVoiceKey(destination: .focusedApp) }
        }
        HotkeyManager.shared.onEditorHotkey = { [weak self] in
            guard let self else { return }
            Task { await self.handleEditorKey() }
        }
        HotkeyManager.shared.onScratchpadHotkey = { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.openScratchpad()
            }
        }
        applyHotkeys()

        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.showAbout"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.showAboutPanel()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.voiceHotkey"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleVoiceKey(destination: .focusedApp) }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.scratchpad.dictation"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleVoiceKey(destination: .scratchpad) }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.editorHotkey.sticky"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.showEditorPanel(with: "", sticky: true)
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.showOnboarding"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.showOnboarding()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.openScratchpad"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.openScratchpad()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.hotkeysChanged"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.applyHotkeys()
            }
        }
        NotificationCenter.default.addObserver(forName: .whisperModelDownloaded, object: nil, queue: .main) { [weak self] note in
            guard let self, let modelID = note.object as? String else { return }
            Task { @MainActor [weak self, modelID] in
                guard let self,
                      self.settingsStore.whisperModel == modelID,
                      let folder = ModelManager.shared.modelFolderURL(for: modelID) else { return }
                try? await self.whisperService.loadModel(name: modelID, at: folder)
            }
        }

        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.whisper.reload"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let name = self.settingsStore.whisperModel
                guard let folder = ModelManager.shared.modelFolderURL(for: name) else { return }
                await self.whisperService.unload()
                try? await self.whisperService.loadModel(name: name, at: folder)
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.whisper.unload"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.whisperService.unload() }
        }

        // Dictation HUD actions — `Done` button + Return key commit; Esc cancels.
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.voice.commit"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleVoiceKey(destination: .focusedApp) }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("typeoh.voice.cancel"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.cancelVoiceRecording() }
        }

        // First-launch onboarding handles permission prompts and warm-ups
        // itself, so it's skipped on first launch. Returning users see the
        // splash while the bootstrap pre-warms keychain + Whisper.
        if !settingsStore.hasCompletedOnboarding {
            showOnboarding()
        } else {
            if !AXIsProcessTrusted() {
                let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
                AXIsProcessTrustedWithOptions(opts)
            }
            showLaunchSplash()
        }
    }

    /// Show the launch splash and run the bootstrap. Splash hides itself when
    /// bootstrap finishes (or after the 8 s soft budget — whichever is first).
    private func showLaunchSplash() {
        let bootstrap = LaunchBootstrap(settings: settingsStore, whisperService: whisperService)

        let content = LaunchSplash(bootstrap: bootstrap) { [weak self] in
            self?.hideLaunchSplash()
        }

        let hc = NSHostingController(rootView: content)
        hc.sizingOptions = .preferredContentSize
        let panel = makePanel(titled: false)
        panel.contentViewController = hc

        if let screen = NSScreen.main {
            let size = hc.view.fittingSize
            panel.setContentSize(size)
            panel.setFrameOrigin(CGPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            ))
        }
        bringPanelFront(panel)
        splashPanel = panel

        Task { await bootstrap.run() }
    }

    private func hideLaunchSplash() {
        splashPanel?.close()
        splashPanel = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openScratchpad()
        return true
    }

    // MARK: - Voice flow

    private func handleVoiceKey(destination: RecordingDestination = .focusedApp) async {
        if audioRecorder.isRecording {
            guard let samples = audioRecorder.stop() else {
                hideRecordingPanel()
                return
            }
            showRecordingProcessingState()
            do {
                let transcript = try await whisperService.transcribe(
                    audio: samples,
                    inputLanguage: settingsStore.whisperInputLanguage
                )
                let text = try await preparedDictationOutput(from: transcript)
                let destination = recordingDestination
                hideRecordingPanel()
                deliverDictation(text, to: destination)
            } catch {
                hideRecordingPanel()
                showBannerError(error.localizedDescription)
            }
            // Respect the user's "keep model loaded" preference. If they
            // disabled it, free the model now so RAM is returned between
            // dictations (at the cost of warm-up on the next press).
            if !settingsStore.whisperKeepLoaded {
                await whisperService.unload()
            }
        } else {
            let modelName = settingsStore.whisperModel
            guard let folder = ModelManager.shared.modelFolderURL(for: modelName) else {
                showBannerError("No Whisper model downloaded. Open Settings → Whisper to download one.")
                return
            }
            do {
                try await whisperService.ensureLoaded(name: modelName, at: folder)
            } catch {
                showBannerError("Failed to load Whisper model: \(error.localizedDescription)")
                return
            }
            if destination == .focusedApp {
                focusCapture.capture()
            }
            recordingDestination = destination
            do {
                try await audioRecorder.start()
                showRecordingPanel()
            } catch {
                showBannerError("Microphone access denied. Enable it in System Settings → Privacy.")
            }
        }
    }

    private func showRecordingPanel() {
        let state = currentDictationHUDState()
        let hc = NSHostingController(rootView: RecordingOverlay(state: state))
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
        installRecordingKeyMonitor()
    }

    private func showRecordingProcessingState() {
        removeRecordingKeyMonitor()
        let state = currentDictationHUDState()
        let hc = NSHostingController(rootView: RecordingOverlay(state: state, phase: .processing))
        hc.sizingOptions = .preferredContentSize
        recordingPanel?.contentViewController = hc
        if let panel = recordingPanel {
            panel.setContentSize(hc.view.fittingSize)
        }
    }

    private func hideRecordingPanel() {
        recordingPanel?.close()
        recordingPanel = nil
        removeRecordingKeyMonitor()
    }

    private func deliverDictation(_ text: String, to destination: RecordingDestination) {
        switch destination {
        case .focusedApp:
            Task { await pasteService.paste(text) }
        case .scratchpad:
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.scratchpad.dictationResult"), object: text)
        }
        recordingDestination = .focusedApp
    }

    private func preparedDictationOutput(from transcript: String) async throws -> String {
        guard let outputLanguage = settingsStore.whisperOutputLanguage,
              !outputLanguage.isEmpty else { return transcript }

        if settingsStore.whisperInputLanguage == outputLanguage {
            return transcript
        }

        return try await TranslationDispatcher.translate(
            text: transcript,
            source: settingsStore.whisperInputLanguage.map(Locale.Language.init(identifier:)),
            target: Locale.Language(identifier: outputLanguage),
            using: settingsStore
        )
    }

    /// Snapshot the model + permission state used by the dictation HUD when the
    /// panel is shown. Re-computed each invocation (cheap; flag values).
    private func currentDictationHUDState() -> DictationHUDState {
        let selected = settingsStore.whisperModel
        let manager = ModelManager.shared
        let modelDisplay = manager.catalogue.first(where: { $0.id == selected })?.displayName ?? selected

        let modelStatus: DictationHUDState.ModelStatus
        if let loaded = manager.loadedModelID {
            let loadedDisplay = manager.catalogue.first(where: { $0.id == loaded })?.displayName ?? loaded
            modelStatus = .loaded(displayName: loadedDisplay)
        } else if manager.isDownloaded(selected) {
            modelStatus = .ready(displayName: modelDisplay)
        } else {
            modelStatus = .missing
        }

        // Mic auth: .authorized means we can record without prompting. The
        // hotkey path implicitly requests on first use, so .notDetermined
        // surfaces as "missing" here — that's intentional, the badge nudges
        // the user toward System Settings.
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        return DictationHUDState(
            modelStatus: modelStatus,
            axTrusted: AXIsProcessTrusted(),
            micAuthorized: micAuth
        )
    }

    /// Local key monitor that listens for Esc / Return while the HUD is on
    /// screen. The panel is non-activating, so the standard responder chain
    /// doesn't see these key presses — we install a process-local monitor and
    /// translate them into the same notifications the Done button posts.
    private func installRecordingKeyMonitor() {
        removeRecordingKeyMonitor()
        recordingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 53: // Escape
                NotificationCenter.default.post(name: NSNotification.Name("typeoh.voice.cancel"), object: nil)
                return nil
            case 36, 76: // Return / Enter (numpad)
                NotificationCenter.default.post(name: NSNotification.Name("typeoh.voice.commit"), object: nil)
                return nil
            default:
                return event
            }
        }
    }

    private func removeRecordingKeyMonitor() {
        if let monitor = recordingKeyMonitor {
            NSEvent.removeMonitor(monitor)
            recordingKeyMonitor = nil
        }
    }

    /// Cancel-path counterpart to `handleVoiceKey`'s commit path. Stops the
    /// recorder, drops the captured samples, tears down the panel, and honors
    /// the keep-loaded preference.
    private func cancelVoiceRecording() {
        guard audioRecorder.isRecording else { return }
        _ = audioRecorder.stop()
        hideRecordingPanel()
        recordingDestination = .focusedApp
        if !settingsStore.whisperKeepLoaded {
            Task { await whisperService.unload() }
        }
    }

    // MARK: - Editor flow

    private func handleEditorKey() async {
        focusCapture.capture()
        let capturedApp = focusCapture.capturedApp
        NSLog("[Type.OH] Editor hotkey — AX trusted: %d, source: %@",
              AXIsProcessTrusted() ? 1 : 0,
              capturedApp?.localizedName ?? "(none)")
        let captured = await selectionReader.readSelectedText(from: capturedApp)
        NSLog("[Type.OH] Selection captured: %d chars, editable=%d",
              captured.text?.count ?? -1,
              captured.isEditable ? 1 : 0)

        // If the source app can't accept a paste-back (PDF viewer, web-view
        // static text, image OCR, etc.) the ReType compact panel is useless —
        // the user can't apply the rewrite anywhere. Route to LazyPad with the
        // text pre-loaded so they can edit & copy/paste manually.
        if let text = captured.text, !text.isEmpty, !captured.isEditable {
            ToastOverlay.shared.show("Source isn't editable — opened in LazyPad.")
            openScratchpad(insertingText: text)
            return
        }

        showEditorPanel(with: captured.text ?? "")
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
        panel.title = "ReType • AI Editor"
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

    func openScratchpad(insertingText text: String? = nil) {
        focusCapture.capture()

        if scratchpadPanelController == nil {
            scratchpadPanelController = ScratchpadPanelController(
                settingsStore: settingsStore,
                pasteService: pasteService,
                store: scratchpadStore
            )
        }

        scratchpadPanelController?.show(using: settingsStore, insertingText: text)
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
        panel.orderFrontRegardless()
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
