import AppKit
import ApplicationServices
import SwiftUI
import Translation

struct AIEditorPanel: View {
    @Environment(SettingsStore.self) private var settings

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

    // Translation state
    @State private var sourceLanguage: Locale.Language? = nil
    @State private var targetLanguage  = Locale.Language(identifier: "en")
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var prevSourceLang:  Locale.Language?
    @State private var prevTargetLang   = Locale.Language(identifier: "en")

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
                .onChange(of: mode) { result = ""; errorMessage = nil }

            // Mode-specific controls
            if mode == .style {
                StyleChipRow(selected: $selectedStyle)
            } else if mode == .translate {
                LanguagePicker(sourceLanguage: $sourceLanguage, targetLanguage: $targetLanguage)
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
                Text(msg).font(.caption).foregroundStyle(.red)
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
        // Translation is handled via this modifier; triggered by setting/invalidating translationConfig.
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(editableInput)
                await MainActor.run {
                    result = response.targetText
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    let msg = error.localizedDescription
                    if msg.localizedCaseInsensitiveContains("unsupported") {
                        errorMessage = "Auto-detect isn't supported for this pair — select a source language manually."
                    } else if msg.localizedCaseInsensitiveContains("same") || msg.localizedCaseInsensitiveContains("identical") {
                        errorMessage = "Source and target language are the same."
                    } else {
                        errorMessage = "Translation failed — make sure the language pack is downloaded in System Settings → Language & Region."
                    }
                    isProcessing = false
                }
            }
        }
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

        if mode == .translate {
            // Guard: source and target must differ when source is explicit
            if let src = sourceLanguage,
               src.languageCode == targetLanguage.languageCode {
                errorMessage = "Source and target language are the same — pick a different target."
                isProcessing = false
                return
            }
            let langChanged = sourceLanguage != prevSourceLang || targetLanguage != prevTargetLang
            if translationConfig == nil || langChanged {
                translationConfig = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
                prevSourceLang = sourceLanguage
                prevTargetLang = targetLanguage
            } else {
                translationConfig?.invalidate()
            }
            return // translationTask modifier handles completion
        }

        let provider = ProviderRegistry.provider(for: settings.activeProvider)
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
        isProcessing = false
    }
}

private struct EmptyInputNotice: View {
    private var axTrusted: Bool { AXIsProcessTrusted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if axTrusted {
                Text("No selected text was captured.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Select text in another app before pressing the hotkey, or use Paste above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Accessibility permission missing")
                        .font(.body.weight(.medium))
                }
                Text("Type.OH needs Accessibility access to read selected text from other apps. Grant it once, then re-launch the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
