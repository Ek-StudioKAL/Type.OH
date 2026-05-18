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

    @State private var editableInput: String
    @State private var mode: EditorMode = .fix
    @State private var selectedStyle: StylePreset? = StylePresets.all.first
    @State private var result       = ""
    @State private var isProcessing = false
    @State private var statusMessage = "Ready"
    @State private var statusIsError = false
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
        VStack(spacing: 10) {
            toolbar

            if mode == .style {
                StyleChipRow(selected: $selectedStyle)
            }

            if mode == .translate {
                translateRow
            }

            inputCard

            if !result.isEmpty {
                resultCard
            }

            if let msg = errorMessage {
                errorBanner(msg)
            }

            actionBar
        }
        .padding(14)
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 900)
        .background(NativeTranslationDriverView())
        .focusEffectDisabled()
        .onAppear { loadTranslationSettingsIfNeeded() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            toolbarButton(title: "Fix", systemImage: "square.and.pencil", isActive: mode == .fix) {
                setMode(.fix)
            }
            toolbarButton(title: "Improve", systemImage: "wand.and.stars", isActive: mode == .improve) {
                setMode(.improve)
            }
            toolbarButton(title: "Style", systemImage: "paintbrush", isActive: mode == .style) {
                setMode(.style)
            }
            toolbarButton(title: "Translate", systemImage: "translate", isActive: mode == .translate) {
                setMode(.translate)
            }
            .contextMenu {
                Text(currentLanguagePairLabel)
                Divider()
                if sourceLanguage != nil {
                    Button("Swap source ⇄ target") {
                        if let src = sourceLanguage {
                            sourceLanguage = targetLanguage
                            targetLanguage = src
                            persistTranslationSettings()
                        }
                    }
                    Button("Reset source to auto-detect") {
                        sourceLanguage = nil
                        persistTranslationSettings()
                    }
                }
                Button("Open Translation Settings…") {
                    openSettingsAt(.translation)
                }
            }

            Spacer(minLength: 12)

            toolbarButton(title: "Paste", systemImage: "doc.on.clipboard") {
                if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                    editableInput = clip
                    result = ""
                    setStatus("Loaded \(clip.count) characters from clipboard.")
                }
            }

            toolbarButton(title: "Copy", systemImage: "doc.on.doc") {
                let textToCopy = result.isEmpty ? editableInput : result
                guard !textToCopy.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(textToCopy, forType: .string)
                setStatus(result.isEmpty ? "Copied input to clipboard." : "Copied result to clipboard.")
            }
            .disabled(editableInput.isEmpty && result.isEmpty)
        }
        .padding(.horizontal, 2)
    }

    /// Inline language selectors shown under the toolbar when mode is `.translate`.
    /// Mirrors the Style chip row so the two modes feel like one design.
    /// Edits write through to `settings.sourceLanguage` / `targetLanguage`
    /// (also the "defaults" used everywhere else).
    private var translateRow: some View {
        HStack(spacing: 10) {
            LanguagePicker(
                sourceLanguage: $sourceLanguage,
                targetLanguage: $targetLanguage,
                compact: true,
                availability: settings.translationProvider == .nativeOS ? .nativeOSOffline : .allLocaleLanguages
            )
            .onChange(of: sourceLanguage) { persistTranslationSettings() }
            .onChange(of: targetLanguage) { persistTranslationSettings() }

            Spacer(minLength: 8)

            Button {
                openSettingsAt(.translation)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Translation Settings")
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Cards

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            cardHeader(title: "Input", trailing: AnyView(EmptyView()))

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
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .frame(minHeight: 60, maxHeight: 160)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            cardHeader(
                title: "Result",
                trailing: AnyView(
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        setStatus("Copied result to clipboard.")
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy result to clipboard")
                )
            )

            ScrollView {
                Text(result)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .frame(minHeight: 60, maxHeight: 200)
        }
    }

    @ViewBuilder
    private func cardHeader(title: String, trailing: AnyView) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            trailing
        }
    }

    @ViewBuilder
    private func errorBanner(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(isSticky ? "Done" : "Cancel") { onCancel() }
                .keyboardShortcut(.escape)

            Toggle("Emojify ✨", isOn: Binding(
                get: { settings.emojify },
                set: { settings.emojify = $0; settings.save() }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)

            Spacer()

            if isProcessing {
                ProgressView().scaleEffect(0.7)
            }

            Button(actionLabel) { Task { await runAction() } }
                .buttonStyle(.bordered)
                .disabled(isProcessing || editableInput.isEmpty)

            if !result.isEmpty {
                Button("Insert") { onApply(result) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .help("Replace the original selection with the result")
            }
        }
    }

    // MARK: - Toolbar primitives (mirrors LazyPad)

    @ViewBuilder
    private func toolbarButton(title: String, systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AccentToolbarLabel(title: title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var actionLabel: String {
        switch mode {
        case .translate: "Translate"
        case .style:     "Stylize"
        case .improve:   "Improve"
        case .fix:       "Fix"
        }
    }

    private var modeStatusLabel: String {
        switch mode {
        case .translate: "Translate"
        case .style:     "Style: \(selectedStyle?.label ?? "—")"
        case .improve:   "Improve"
        case .fix:       "Fix"
        }
    }

    private func setMode(_ newMode: EditorMode) {
        guard mode != newMode else { return }
        mode = newMode
        result = ""
        errorMessage = nil
    }

    private func setStatus(_ message: String) {
        statusMessage = message
        statusIsError = false
    }

    private func setErrorStatus(_ message: String) {
        statusMessage = message
        statusIsError = true
        errorMessage = message
    }

    private func runAction() async {
        errorMessage = nil
        result       = ""
        isProcessing = true
        setStatus("\(actionLabel)…")

        let provider = ProviderRegistry.provider(for: settings.activeProvider)

        if mode == .translate {
            if let src = sourceLanguage, src.languageCode == targetLanguage.languageCode {
                setErrorStatus("Source and target language are the same — pick a different target.")
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
                setStatus("Translate complete.")
            } catch TranslationDispatcher.Failure.engineUnselected {
                setErrorStatus("Pick a translation engine — opening Settings.")
                openSettingsAt(.translation)
            } catch {
                setErrorStatus(error.localizedDescription)
            }
            isProcessing = false
            return
        }

        do {
            switch mode {
            case .improve:
                let preset = StylePreset(
                    id: "retype-improve",
                    label: "Improve",
                    emoji: "✨",
                    promptFragment: "Rewrite the following text to improve clarity, flow, tone, and readability while preserving its meaning. Keep it natural and polished."
                )
                result = try await provider.applyStyle(preset, to: editableInput, emojify: settings.emojify)
                setStatus("Improve complete.")
            case .style:
                guard let preset = selectedStyle else {
                    setErrorStatus("Select a style preset first.")
                    isProcessing = false
                    return
                }
                result = try await provider.applyStyle(preset, to: editableInput, emojify: settings.emojify)
                setStatus("Style applied.")
            case .fix:
                result = try await provider.fix(text: editableInput, emojify: settings.emojify)
                setStatus("Fix complete.")
            case .translate:
                break
            }
        } catch {
            setErrorStatus(error.localizedDescription)
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

    private var currentLanguagePairLabel: String {
        let src = sourceLanguage.map(displayName) ?? "Auto"
        let dst = displayName(targetLanguage)
        return "\(src) → \(dst)"
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

/// A sidebar row with full-width hit area, hover tint, and selection state.
/// Used in LazyPad for style presets, custom presets, and provider switching.
struct SidebarHoverRow<Content: View>: View {
    var isSelected: Bool = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    private var fillColor: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovering { return Color.accentColor.opacity(0.08) }
        return Color.clear
    }

    private var foreground: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.accentColor }
        return Color.primary
    }

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fillColor)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

/// A toolbar label used by both ReType (AI Editor) and LazyPad.
///
/// Visual language:
/// - Symbol tinted with the accent color when `isActive` or hovered
///   (no filled background "highlight" rectangle).
/// - Thin 0.5 pt accent underline appears under the active tab.
/// - Subtle scale / opacity transition on hover to feel alive.
struct AccentToolbarLabel: View {
    let title: String
    let systemImage: String
    var isActive: Bool = false
    var literalGlyph: String? = nil

    @State private var isHovering = false

    private var tinted: Bool { isActive || isHovering }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let literalGlyph {
                    Text(literalGlyph)
                        .font(.system(size: 17, weight: tinted ? .semibold : .regular))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: tinted ? .semibold : .regular))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .foregroundStyle(tinted ? Color.accentColor : .primary)
            .frame(width: 28, height: 22)
            .scaleEffect(isHovering && !isActive ? 1.06 : 1.0)

            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(tinted ? Color.accentColor : .primary)

            // Thin accent underline beneath the active tab — replaces the
            // filled "highlighted area" used before.
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 0.5)
                .frame(maxWidth: isActive ? 38 : 0)
                .opacity(isActive ? 1.0 : 0.0)
        }
        .frame(width: 62)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .animation(.easeOut(duration: 0.14), value: isActive)
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
