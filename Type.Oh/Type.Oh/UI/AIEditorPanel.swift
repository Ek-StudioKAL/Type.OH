import AppKit
import ApplicationServices
import SwiftUI

struct AIEditorPanel: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    let originalText: String
    let isSticky: Bool
    let onApply:  (String) -> Void
    let onCancel: () -> Void

    // editableInput starts as originalText but can be overridden via the Paste button
    @State private var editableInput: String
    @State private var mode: EditorMode = .fix
    @State private var selectedStyle: StylePreset? = StylePresets.all.first
    @State private var result       = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    @State private var sourceLanguage: Locale.Language? = nil
    @State private var targetLanguage  = Locale.Language(identifier: "en")
    @State private var hasLoadedTranslationSettings = false

    init(originalText: String, isSticky: Bool = false, onApply: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.originalText = originalText
        self.isSticky = isSticky
        self.onApply  = onApply
        self.onCancel = onCancel
        self._editableInput = State(initialValue: originalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Mode tabs
            ModeTabs(mode: $mode)
                .onChange(of: mode) {
                    result = ""
                    errorMessage = nil
                }

            // Mode-specific controls
            if mode == .style {
                StyleChipRow(selected: $selectedStyle)
            } else if mode == .translate {
                LanguagePicker(
                    sourceLanguage: $sourceLanguage,
                    targetLanguage: $targetLanguage,
                    compact: true,
                    availability: settings.translationProvider == .nativeOS ? .nativeOSOffline : .allLocaleLanguages
                )
                    .onChange(of: sourceLanguage) { persistTranslationSettings() }
                    .onChange(of: targetLanguage) { persistTranslationSettings() }
            }

            // Input area with Paste fallback
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Input")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                            editableInput = clip
                            result = ""
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Replace input with clipboard contents")
                }

                ScrollView {
                    if editableInput.isEmpty {
                        EmptyInputNotice()
                    } else {
                        Text(editableInput)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 60, maxHeight: 160)
            }

            // Result area
            if !result.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(result, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy result to clipboard")
                    }

                    ScrollView {
                        Text(result)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 60, maxHeight: 160)
                }
            }

            // Error
            if let msg = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(msg).font(.caption).foregroundStyle(.red)
                    if msg.contains("API key") || msg.contains("Settings → Providers") {
                        HStack(spacing: 12) {
                            Button("Open Settings → Providers") {
                                openSettingsAt(.providers)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Button("Re-run Setup Wizard") {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("typeoh.showOnboarding"), object: nil)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
            }

            // Emojify toggle
            Toggle("Emojify ✨", isOn: Binding(
                get: { settings.emojify },
                set: { settings.emojify = $0; settings.save() }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)

            // Action bar
            HStack {
                Button(isSticky ? "Done" : "Cancel") { onCancel() }
                    .keyboardShortcut(.escape)

                Spacer()

                if isProcessing {
                    ProgressView().scaleEffect(0.7)
                }

                Button(actionLabel) { Task { await runAction() } }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing || editableInput.isEmpty)

                if !result.isEmpty {
                    Button("Apply") { onApply(result) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, maxWidth: 900)
        .background(NativeTranslationDriverView())
        .onAppear { loadTranslationSettingsIfNeeded() }
    }

    // MARK: - Helpers

    private var actionLabel: String {
        switch mode {
        case .translate: "Translate"
        case .style:     "Apply Style"
        case .fix:       "Fix"
        }
    }

    private func runAction() async {
        errorMessage = nil
        result       = ""
        isProcessing = true

        let provider = ProviderRegistry.provider(for: settings.activeProvider)

        if mode == .translate {
            if let src = sourceLanguage, src.languageCode == targetLanguage.languageCode {
                errorMessage = "Source and target language are the same — pick a different target."
                isProcessing = false
                return
            }
            do {
                result = try await TranslationDispatcher.translate(
                    text: editableInput,
                    source: sourceLanguage,
                    target: targetLanguage,
                    using: settings
                )
            } catch TranslationDispatcher.Failure.engineUnselected {
                errorMessage = "Pick a translation engine — opening Settings."
                openSettingsAt(.translation)
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
            return
        } else {
            do {
            switch mode {
            case .style:
                guard let preset = selectedStyle else {
                    errorMessage = "Select a style preset first."
                    isProcessing = false
                    return
                }
                result = try await provider.applyStyle(preset, to: editableInput, emojify: settings.emojify)
            case .fix:
                result = try await provider.fix(text: editableInput, emojify: settings.emojify)
            case .translate:
                break
            }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        isProcessing = false
    }

    private func loadTranslationSettingsIfNeeded() {
        guard !hasLoadedTranslationSettings else { return }
        sourceLanguage = settings.sourceLanguage.map(Locale.Language.init(identifier:))
        targetLanguage = Locale.Language(identifier: settings.targetLanguage)
        hasLoadedTranslationSettings = true
    }

    private func persistTranslationSettings() {
        settings.sourceLanguage = sourceLanguage?.minimalIdentifier
        settings.targetLanguage = targetLanguage.minimalIdentifier
        settings.save()
    }

    private func displayName(_ lang: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: lang.minimalIdentifier) ?? lang.minimalIdentifier
    }

    /// See `ScratchpadView.openSettingsAt` — same trick to make the
    /// SwiftUI Settings scene reliably surface on the requested tab whether
    /// it's already alive or being mounted for the first time.
    private func openSettingsAt(_ tab: SettingsTab) {
        SettingsTabRoute.setPendingTab(tab)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        NotificationCenter.default.post(
            name: SettingsTabRoute.notificationName,
            object: tab.rawValue
        )
    }
}

private struct EmptyInputNotice: View {
    private var axTrusted: Bool { AXIsProcessTrusted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if axTrusted {
                Text("No text was captured from the source app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Select text before pressing the hotkey, or use Paste above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Still not working? Re-run Setup Wizard") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("typeoh.showOnboarding"), object: nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Accessibility permission missing")
                        .font(.body.weight(.medium))
                }
                Text("Type.OH needs Accessibility access to read selected text from other apps. Grant it in System Settings, then re-launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Re-run Setup Wizard") {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("typeoh.showOnboarding"), object: nil)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
