import AppKit
import SwiftUI

private enum ScratchpadAction {
    case improve
    case fix
    case concise
    case translate
    case style(StylePreset)

    var buttonTitle: String {
        switch self {
        case .improve: "Improve"
        case .fix: "Fix"
        case .concise: "Make Concise"
        case .translate: "Translate"
        case .style: "Stylize"
        }
    }

    var progressTitle: String {
        switch self {
        case .improve: "Improving"
        case .fix: "Fixing"
        case .concise: "Making concise"
        case .translate: "Translating"
        case .style(let preset): "Applying \(preset.label)"
        }
    }
}

struct ScratchpadView: View {
    @Environment(SettingsStore.self) private var settings

    let pasteService: PasteService
    let store: ScratchpadStore

    @State private var text: String
    @State private var selectedRange = NSRange(location: NSNotFound, length: 0)
    @State private var textViewController = NativeTextViewController()
    @State private var isProcessing = false
    @State private var statusMessage = "Ready"
    @State private var statusIsError = false
    @State private var sourceLanguage: Locale.Language? = nil
    @State private var targetLanguage = Locale.Language(identifier: "en")
    @State private var isShowingTranslationPopover = false
    @State private var hasLoadedTranslationSettings = false
    @State private var isSidebarVisible = true

    init(pasteService: PasteService, store: ScratchpadStore) {
        self.pasteService = pasteService
        self.store = store
        _text = State(initialValue: store.load())
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar

            HStack(spacing: 0) {
                if isSidebarVisible {
                    sidebar
                    Divider()
                }

                editorArea
            }

            statusBar
        }
        .padding(14)
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
        .onChange(of: text) {
            store.scheduleSave(text)
        }
        .onAppear {
            loadTranslationSettingsIfNeeded()
        }
        .onDisappear {
            store.saveNow(text)
        }
    }

    private var characterCount: Int {
        text.count
    }

    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var providerStatusLabel: String {
        settings.activeProvider.displayName
    }

    private var whisperModelStatusLabel: String {
        settings.whisperModel
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    private func runAction(_ action: ScratchpadAction) {
        Task { await performAction(action) }
    }

    private func performAction(_ action: ScratchpadAction) async {
        let sourceText = text
        let targetRange = selectedTextRange(in: sourceText)
        let input = targetRange.map { substring(in: sourceText, range: $0) } ?? sourceText

        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setErrorStatus("Nothing to process.")
            return
        }

        if case .translate = action {
            await performTranslation(on: input, sourceText: sourceText, selectedRange: targetRange)
            return
        }

        isProcessing = true
        setStatus("\(action.progressTitle)…")
        let provider = ProviderRegistry.provider(for: settings.activeProvider)

        do {
            let output = try await rewrite(input: input, action: action, provider: provider)
            guard text == sourceText else {
                setErrorStatus("Text changed while the AI action was running. Nothing was replaced.")
                isProcessing = false
                return
            }

            if let targetRange {
                textViewController.replaceCharacters(in: targetRange, with: output)
            } else {
                textViewController.replaceAllText(with: output)
            }
            text = textViewController.currentText ?? output
            setStatus("\(action.buttonTitle) complete.")
        } catch {
            setErrorStatus(error.localizedDescription)
        }

        isProcessing = false
    }

    private func rewrite(input: String, action: ScratchpadAction, provider: any TextAIProvider) async throws -> String {
        switch action {
        case .fix:
            return try await provider.fix(text: input, emojify: settings.emojify)
        case .improve:
            let preset = StylePreset(
                id: "scratchpad-improve",
                label: "Improve",
                emoji: "✨",
                promptFragment: "Rewrite the following text to improve clarity, flow, tone, and readability while preserving its meaning. Keep it natural and polished."
            )
            return try await provider.applyStyle(preset, to: input, emojify: settings.emojify)
        case .concise:
            let preset = StylePreset(
                id: "scratchpad-concise",
                label: "Concise",
                emoji: "✂️",
                promptFragment: "Rewrite the following text to be noticeably more concise while preserving the original meaning, key details, and tone."
            )
            return try await provider.applyStyle(preset, to: input, emojify: settings.emojify)
        case .translate:
            return input
        case .style(let preset):
            return try await provider.applyStyle(preset, to: input, emojify: settings.emojify)
        }
    }

    private func performTranslation(on input: String, sourceText: String, selectedRange: NSRange?) async {
        if let sourceLanguage, sourceLanguage.languageCode == targetLanguage.languageCode {
            setErrorStatus("Source and target language are the same.")
            return
        }

        isProcessing = true
        setStatus("Translating…")
        let provider = ProviderRegistry.provider(for: settings.activeProvider)

        do {
            let translatedText = try await provider.translate(
                text: input,
                sourceLanguage: sourceLanguage.map(displayName),
                targetLanguage: displayName(targetLanguage)
            )

            guard text == sourceText else {
                setErrorStatus("Text changed while translation was running. Nothing was replaced.")
                isProcessing = false
                return
            }

            if let selectedRange {
                textViewController.replaceCharacters(in: selectedRange, with: translatedText)
            } else {
                textViewController.replaceAllText(with: translatedText)
            }

            text = textViewController.currentText ?? translatedText
            setStatus("Translate complete.")
        } catch {
            setErrorStatus(error.localizedDescription)
        }

        isProcessing = false
    }

    private func selectedTextRange(in sourceText: String) -> NSRange? {
        guard let range = textViewController.selectedRange(), range.length > 0 else { return nil }
        guard NSMaxRange(range) <= sourceText.utf16.count else { return nil }
        return range
    }

    private func substring(in sourceText: String, range: NSRange) -> String {
        (sourceText as NSString).substring(with: range)
    }

    private func pasteToLastApp() async {
        if pasteService.hasCapturedTarget {
            await pasteService.paste(text)
            setStatus("Pasted to the last app.")
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            setStatus("No previous app was captured. Copied to clipboard instead.")
        }
    }

    private func setStatus(_ message: String) {
        statusMessage = message
        statusIsError = false
    }

    private func setErrorStatus(_ message: String) {
        statusMessage = message
        statusIsError = true
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sidebarSection(title: "Styles") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(StylePresets.all) { preset in
                                sidebarButton(
                                    title: preset.label,
                                    systemImage: styleSymbol(for: preset),
                                    isSelected: false
                                ) {
                                    runAction(.style(preset))
                                }
                                .disabled(isProcessing || text.isEmpty)
                            }
                        }
                    }

                    sidebarSection(title: "Providers") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(ProviderID.allCases, id: \.self) { provider in
                                sidebarProviderButton(provider)
                            }
                        }
                    }

                    sidebarSection(title: "Text Tools") {
                        VStack(alignment: .leading, spacing: 2) {
                            sidebarToggle(
                                title: "Spelling",
                                detail: "Spell checking and automatic spelling correction.",
                                isOn: Binding(
                                    get: { settings.spellingAssistanceEnabled },
                                    set: { value in
                                        settings.spellingAssistanceEnabled = value
                                        settings.save()
                                    }
                                )
                            )
                            sidebarToggle(
                                title: "Grammar",
                                detail: "Grammar checking, smart quotes, and smart dashes.",
                                isOn: Binding(
                                    get: { settings.grammarAssistanceEnabled },
                                    set: { value in
                                        settings.grammarAssistanceEnabled = value
                                        settings.save()
                                    }
                                )
                            )
                            sidebarToggle(
                                title: "Text Replacement",
                                detail: "Text replacement shortcuts and substitutions.",
                                isOn: Binding(
                                    get: { settings.textReplacementEnabled },
                                    set: { value in
                                        settings.textReplacementEnabled = value
                                        settings.save()
                                    }
                                )
                            )
                        }
                    }
                }
                .padding(10)
            }

            Divider()

            HStack(spacing: 10) {
                bottomIconButton(title: "Settings", systemImage: "gearshape") {
                    NotificationCenter.default.post(name: NSNotification.Name("typeoh.openSettings"), object: nil)
                }
                bottomIconButton(title: "Setup", systemImage: "wand.and.stars.inverse") {
                    NotificationCenter.default.post(name: NSNotification.Name("typeoh.showOnboarding"), object: nil)
                }
            }
            .padding(10)
        }
        .frame(width: 220)
        .background(Color.secondary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var editorArea: some View {
        NativeTextView(
            text: $text,
            selectedRange: $selectedRange,
            spellingAssistanceEnabled: settings.spellingAssistanceEnabled,
            grammarAssistanceEnabled: settings.grammarAssistanceEnabled,
            textReplacementEnabled: settings.textReplacementEnabled,
            controller: textViewController
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            toolbarButton(title: isSidebarVisible ? "Hide" : "Show", systemImage: isSidebarVisible ? "sidebar.left" : "sidebar.right") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            }

            toolbarButton(title: "Dictate", systemImage: "mic") {
                NotificationCenter.default.post(name: NSNotification.Name("typeoh.voiceHotkey"), object: nil)
            }

            toolbarButton(title: "Improve", systemImage: "wand.and.stars") {
                runAction(.improve)
            }
            .disabled(isProcessing || text.isEmpty)

            toolbarButton(title: "Fix", systemImage: "square.and.pencil") {
                runAction(.fix)
            }
            .disabled(isProcessing || text.isEmpty)

            toolbarButton(title: "Concise", systemImage: "minus.square") {
                runAction(.concise)
            }
            .disabled(isProcessing || text.isEmpty)

            toolbarButton(title: "Translate", systemImage: "translate") {
                isShowingTranslationPopover.toggle()
            }
            .disabled(isProcessing || text.isEmpty)
            .popover(isPresented: $isShowingTranslationPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Translate")
                        .font(.headline)
                    LanguagePicker(sourceLanguage: $sourceLanguage, targetLanguage: $targetLanguage)
                        .onChange(of: sourceLanguage) { persistTranslationSettings() }
                        .onChange(of: targetLanguage) { persistTranslationSettings() }
                    Button("Translate") {
                        isShowingTranslationPopover = false
                        runAction(.translate)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isProcessing || text.isEmpty)
                }
                .padding(14)
                .frame(width: 320)
            }

            Spacer(minLength: 12)

            toolbarButton(title: "Paste", systemImage: "arrowshape.turn.up.right") {
                Task { await pasteToLastApp() }
            }
            .disabled(text.isEmpty)

            toolbarButton(title: "Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                setStatus("Copied full text to clipboard.")
            }
            .disabled(text.isEmpty)

            toolbarButton(title: "Clear", systemImage: "trash") {
                text = ""
                selectedRange = NSRange(location: 0, length: 0)
                store.scheduleSave(text)
                setStatus("Scratchpad cleared.")
            }
            .disabled(isProcessing || text.isEmpty)
        }
        .padding(.horizontal, 2)
    }

    private var statusBar: some View {
        HStack {
            HStack(spacing: 6) {
                Text("\(characterCount) characters")
                Text("•")
                Text("\(wordCount) words")
            }

            Spacer()

            HStack(spacing: 6) {
                Text("Whisper: \(whisperModelStatusLabel)")
                Text("•")
                Text("Provider: \(providerStatusLabel)")
            }
            .multilineTextAlignment(.center)

            Spacer()

            Text(statusMessage)
                .foregroundStyle(statusIsError ? .red : .secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func toolbarButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolbarLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func toolbarLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 28, height: 22)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
        }
        .frame(width: 62)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
    }

    private func providerSymbol(for provider: ProviderID) -> String {
        switch provider {
        case .appleOnDevice: "apple.logo"
        case .anthropic: "text.quote"
        case .openAI: "bubble.left.and.bubble.right"
        case .google: "g.circle"
        }
    }

    private var currentProviderToolbarTitle: String {
        switch settings.activeProvider {
        case .appleOnDevice: "Apple"
        case .anthropic: "Claude"
        case .openAI: "ChatGPT"
        case .google: "Google"
        }
    }

    private func providerMenuTitle(for provider: ProviderID) -> String {
        switch provider {
        case .appleOnDevice: "Apple (On-Device)"
        case .anthropic: "Anthropic Claude"
        case .openAI: "OpenAI ChatGPT"
        case .google: "Google Gemini"
        }
    }

    private func styleSymbol(for preset: StylePreset) -> String {
        switch preset.id {
        case "boomer": "newspaper"
        case "genx": "bolt.horizontal"
        case "millennial": "bubble.left.and.bubble.right"
        case "genz": "sparkles"
        case "alpha": "flame"
        default: "paintbrush"
        }
    }

    @ViewBuilder
    private func sidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder
    private func sidebarToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .help(detail)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sidebarButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sidebarProviderButton(_ provider: ProviderID) -> some View {
        Button {
            settings.activeProvider = provider
            settings.save()
        } label: {
            HStack(spacing: 10) {
                providerSidebarIcon(for: provider)
                    .frame(width: 18, height: 18)
                Text(providerMenuTitle(for: provider))
                    .fontWeight(settings.activeProvider == provider ? .semibold : .regular)
                Spacer(minLength: 0)
                if settings.activeProvider == provider {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.activeProvider == provider ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func providerSidebarIcon(for provider: ProviderID) -> some View {
        if let image = providerAssetImage(for: provider) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
        } else {
            Image(systemName: providerSymbol(for: provider))
                .frame(width: 18, height: 18)
        }
    }

    private func providerAssetImage(for provider: ProviderID) -> NSImage? {
        let assetName: String?
        switch provider {
        case .appleOnDevice:
            assetName = nil
        case .anthropic:
            assetName = "Claude Sidebar Icon"
        case .openAI:
            assetName = "ChatGPT Sidebar Icon"
        case .google:
            assetName = "Gemini Sidebar Icon"
        }
        guard let assetName else { return nil }
        return NSImage(named: assetName)
    }

    @ViewBuilder
    private func bottomIconButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .regular))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
