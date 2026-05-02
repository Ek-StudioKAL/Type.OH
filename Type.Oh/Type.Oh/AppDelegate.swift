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

    private var recordingPanel:  NSPanel?
    private var editorPanel:     NSPanel?
    private var onboardingPanel: NSPanel?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // No Dock icon

        HotkeyManager.shared.onVoiceHotkey  = { [weak self] in Task { @MainActor in await self?.handleVoiceKey()  } }
        HotkeyManager.shared.onEditorHotkey = { [weak self] in Task { @MainActor in await self?.handleEditorKey() } }
        HotkeyManager.shared.register(voice: settingsStore.voiceHotkey, editor: settingsStore.editorHotkey)

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
        let panel = makePanel(size: CGSize(width: 130, height: 44), titled: false)
        let host  = NSHostingView(rootView: RecordingOverlay())
        host.frame = CGRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if let screen = NSScreen.main {
            panel.setFrameOrigin(CGPoint(
                x: screen.visibleFrame.midX - panel.frame.width / 2,
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

    private func showEditorPanel(with text: String) {
        editorPanel?.close()

        let content = AIEditorPanel(
            originalText: text,
            onApply: { [weak self] result in
                guard let self else { return }
                editorPanel?.close()
                editorPanel = nil
                Task { await self.pasteService.paste(result) }
            },
            onCancel: { [weak self] in
                self?.editorPanel?.close()
                self?.editorPanel = nil
            }
        )
        .environment(settingsStore)
        
        // Create hosting view first to get its fitting size
        let hostingView = NSHostingView(rootView: content)
        let fittingSize = hostingView.fittingSize
        
        let panel = makePanel(size: fittingSize, titled: true)
        panel.title = "AI Editor"
        panel.contentView = hostingView
        
        panel.center()
        bringPanelFront(panel)
        editorPanel = panel
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        onboardingPanel?.close()

        let content = OnboardingWizard(onFinish: { [weak self] in
            self?.onboardingPanel?.close()
            self?.onboardingPanel = nil
        })
        .environment(settingsStore)
        
        // Create hosting view first to get its fitting size
        let hostingView = NSHostingView(rootView: content)
        let fittingSize = hostingView.fittingSize
        
        let panel = makePanel(size: fittingSize, titled: true)
        panel.title = "Welcome to Type.OH"
        panel.contentView = hostingView
        
        panel.center()
        bringPanelFront(panel)
        onboardingPanel = panel
    }

    // MARK: - Helpers

    private func makePanel(size: CGSize, titled: Bool) -> NSPanel {
        // .resizable + SwiftUI NSHostingView causes an infinite updateConstraints loop that
        // crashes the app (NSGenericException in _postWindowNeedsUpdateConstraints).
        // Titled panels need .nonactivatingPanel so they render in front under LSUIElement.
        let style: NSWindow.StyleMask = titled
            ? [.titled, .closable, .nonactivatingPanel]
            : [.nonactivatingPanel, .borderless]

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
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
        
        // Prevent the panel from being resizable to avoid constraint update loops
        panel.styleMask.remove(.resizable)
        
        return panel
    }

    private func bringPanelFront(_ panel: NSPanel) {
        // Briefly promote to regular policy so NSApp.activate() raises the window
        // above foreground apps, then revert to accessory (no Dock icon).
        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        NSApp.setActivationPolicy(.accessory)
    }

    private func showBannerError(_ message: String) {
        // TODO: replace with an in-app notification banner
        NSLog("[Type.OH] Error: %@", message)
    }
}
