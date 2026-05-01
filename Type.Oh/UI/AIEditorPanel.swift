import SwiftUI
import Translation

struct AIEditorPanel: View {
    @Environment(SettingsStore.self) private var settings

    let originalText: String
    let onApply:  (String) -> Void
    let onCancel: () -> Void

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

            // Text panes
            Group {
                if mode == .fix && !result.isEmpty {
                    DiffTextView(original: originalText, result: result)
                        .frame(minHeight: 120)
                } else {
                    ScrollView {
                        Text(result.isEmpty ? originalText : result)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .frame(minHeight: 80)
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
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)

                Spacer()

                if isProcessing {
                    ProgressView().scaleEffect(0.7)
                }

                Button(actionLabel) { Task { await runAction() } }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)

                if !result.isEmpty {
                    Button("Apply") { onApply(result) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                }
            }
        }
        .padding(20)
        .frame(width: 500)
        // Translation is handled via this modifier; triggered by setting/invalidating translationConfig.
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(originalText)
                await MainActor.run {
                    result = response.targetText
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
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
                result = try await provider.applyStyle(preset, to: originalText, emojify: settings.emojify)
            case .fix:
                result = try await provider.fix(text: originalText, emojify: settings.emojify)
            case .translate:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}
