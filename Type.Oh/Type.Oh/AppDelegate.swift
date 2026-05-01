import AppKit
import SwiftUI
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Shared state — injected into every SwiftUI scene via .environment()
    let settingsStore = SettingsStore()

    private let focusCapture    = FocusCapture()
    private lazy var pasteService     = PasteService(focusCapture: focusCapture)
    private lazy var selectionReader  = SelectionReader()
    private      let audioRecorder    = AudioRecorder()
    private      let whisperService   = WhisperService()

    private var recordingPanel: NSPanel?
    private var editorPanel:    NSPanel?

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // No Dock icon

        HotkeyManager.shared.onVoiceHotkey  = { [weak self] in Task { @MainActor in await self?.handleVoiceKey()  } }
        HotkeyManager.shared.onEditorHotkey = { [weak self] in Task { @MainActor in await self?.handleEditorKey() } }
        HotkeyManager.shared.register(voice: settingsStore.voiceHotkey, editor: settingsStore.editorHotkey)

        // Prompt for Accessibility permission on first launch if missing
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        // Pre-load the last-used Whisper model
        Task { try? await whisperService.loadModel(settingsStore.whisperModel) }
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
        panel.orderFront(nil)
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
        let text = await selectionReader.readSelectedText(from: capturedApp)
        showEditorPanel(with: text ?? "")
    }

    private func showEditorPanel(with text: String) {
        editorPanel?.close()

        let panel = makePanel(size: CGSize(width: 540, height: 460), titled: true)
        panel.title = "AI Editor"

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

        panel.contentView = NSHostingView(rootView: content)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        editorPanel = panel
    }

    // MARK: - Helpers

    private func makePanel(size: CGSize, titled: Bool) -> NSPanel {
        var style: NSWindow.StyleMask = [.nonactivatingPanel, .borderless]
        if titled { style = [.titled, .closable, .resizable] }

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
        return panel
    }

    private func showBannerError(_ message: String) {
        // TODO: replace with an in-app notification banner
        NSLog("[Type.OH] Error: %@", message)
    }
}
