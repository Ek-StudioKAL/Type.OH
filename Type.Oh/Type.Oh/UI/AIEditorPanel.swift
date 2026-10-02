import AppKit
import ApplicationServices
import SwiftUI

enum EditorMode: String, CaseIterable {
    case translate = "Translate"
    case style     = "Style"
    case improve   = "Improve"
    case fix       = "Fix"
}

@MainActor struct AIEditorPanel: View {
    @EnvironmentObject private var settings: SettingsStore

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

    /// Share of the card area the Input card gets while a Result is shown.
    /// Set by dragging the divider between the cards; remembered across launches.
    @AppStorage("typeoh.retype.inputFraction") private var inputFraction = 0.5

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

            if result.isEmpty {
                inputCard
            } else {
                splitCards
            }

            if let msg = errorMessage {
                errorBanner(msg)
            }

            actionBar
        }
        .padding(14)
        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NativeTranslationDriverView())
        .typeOhFocusEffectDisabled()
        .onAppear { loadTranslationSettingsIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: TypeOhTouchBar.reTypeAction)) { note in
            guard let id = note.object as? String else { return }
            runTouchBarAction(id)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(alignment: .top, spacing: 10) {
            toolbarButton(title: "Fix", icon: .fix, isActive: mode == .fix, shortcut: "1") {
                setMode(.fix)
            }
            .help("Fix spelling and grammar (⌘1)")
            toolbarButton(title: "Improve", icon: .improve, isActive: mode == .improve, shortcut: "2") {
                setMode(.improve)
            }
            .help("Improve clarity and flow (⌘2)")
            toolbarButton(title: "Style", icon: .style, isActive: mode == .style, shortcut: "3") {
                setMode(.style)
            }
            .help("Rewrite in a style preset (⌘3)")
            toolbarButton(title: "Translate", icon: .translate, isActive: mode == .translate, shortcut: "4") {
                setMode(.translate)
            }
            .help("Translate: \(currentLanguagePairLabel) (⌘4)")
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

            toolbarButton(title: "Paste", icon: .paste) {
                if let clip = NSPasteboard.general.string(forType: .string), !clip.isEmpty {
                    editableInput = clip
                    result = ""
                    setStatus("Loaded \(clip.count) characters from clipboard.")
                }
            }
            .help("Replace the input with the clipboard")

            toolbarButton(title: "Copy", icon: .copy) {
                let textToCopy = result.isEmpty ? editableInput : result
                guard !textToCopy.isEmpty else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(textToCopy, forType: .string)
                setStatus(result.isEmpty ? "Copied input to clipboard." : "Copied result to clipboard.")
            }
            .disabled(editableInput.isEmpty && result.isEmpty)
            .help(result.isEmpty ? "Copy the input" : "Copy the result")
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
            .onChange(of: sourceLanguage) { _ in persistTranslationSettings() }
            .onChange(of: targetLanguage) { _ in persistTranslationSettings() }

            Spacer(minLength: 8)

            Button {
                openSettingsAt(.translation)
            } label: {
                Image(appIcon: .settings, size: 16)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Translation Settings")
            .accessibilityLabel("Translation Settings")
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
            .frame(minHeight: 60, maxHeight: .infinity)
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
                        Label {
                            Text("Copy")
                        } icon: {
                            Image(appIcon: .copy, size: 13)
                        }
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
            .frame(minHeight: 60, maxHeight: .infinity)
        }
    }

    /// Input above Result with a draggable divider between them.
    private var splitCards: some View {
        GeometryReader { proxy in
            let available = max(0, proxy.size.height - CardSplitHandle.height)
            // Each card keeps room for its header plus a few lines.
            let minFraction = available > 0 ? min(0.45, 90 / Double(available)) : 0.5
            let range = minFraction...(1 - minFraction)
            let fraction = min(max(inputFraction, range.lowerBound), range.upperBound)

            VStack(spacing: 0) {
                inputCard
                    .frame(height: available * fraction)
                CardSplitHandle(fraction: $inputFraction, availableHeight: available, range: range)
                resultCard
                    .frame(height: available * (1 - fraction))
            }
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
                Image(appIcon: .warning, size: 15)
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

            // Errors show in the banner above; this line carries the rest
            // ("Copied result", "Loaded 120 characters", progress).
            if !statusIsError {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if isProcessing {
                ProgressView().scaleEffect(0.7)
            }

            // Return always triggers the next step: run the action until
            // there's a result, then Insert it. ⌘Return re-runs.
            if result.isEmpty {
                Button(actionLabel) { Task { await runAction() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(isProcessing || editableInput.isEmpty)
                    .help("\(actionLabel) the input (Return)")
            } else {
                Button("\(actionLabel) Again") { Task { await runAction() } }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isProcessing || editableInput.isEmpty)
                    .help("Run \(actionLabel) again (⌘Return)")

                Button("Insert") { onApply(result) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .help("Replace the original selection with the result (Return)")
            }
        }
    }

    /// Touch Bar buttons (`TypeOhTouchBar.reType`): pick the mode and run it
    /// in one tap; Insert applies the result.
    private func runTouchBarAction(_ id: String) {
        if id == "insert" {
            if !result.isEmpty { onApply(result) }
            return
        }
        let newMode: EditorMode
        switch id {
        case "fix": newMode = .fix
        case "improve": newMode = .improve
        case "translate": newMode = .translate
        default: return
        }
        guard !isProcessing, !editableInput.isEmpty else { return }
        setMode(newMode)
        Task { await runAction() }
    }

    // MARK: - Toolbar primitives (mirrors LazyPad)

    @ViewBuilder
    private func toolbarButton(
        title: String,
        icon: AppIcon,
        isActive: Bool = false,
        shortcut: KeyEquivalent? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            AccentToolbarLabel(title: title, icon: icon, isActive: isActive)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0, modifiers: .command) })
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
        SettingsWindowOpener.open(at: tab)
    }
}

/// A sidebar row with full-width hit area, hover tint, and selection state.
/// Used in LazyPad for style presets, custom presets, and provider switching.
/// `actionHint` marks rows that *run* something (styles) rather than select
/// a setting (providers): the hint appears on the trailing edge on hover.
@MainActor struct SidebarHoverRow<Content: View>: View {
    var isSelected: Bool = false
    var actionHint: String? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            HStack(spacing: 6) {
                content()
                if let actionHint, isHovering {
                    Text(actionHint)
                        .font(.caption.weight(.medium))
                        .accessibilityHidden(true)
                }
            }
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
    }
}

/// A toolbar label used by both ReType and LazyPad.
///
/// Visual language:
/// - Symbol tinted with the accent color when `isActive` or hovered
///   (no filled background "highlight" rectangle).
/// - Thin 0.5 pt accent underline appears under the active tab.
/// - Subtle scale / opacity transition on hover to feel alive.
@MainActor struct AccentToolbarLabel: View {
    let title: String
    let icon: AppIcon
    var isActive: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var tinted: Bool { isActive || isHovering }

    var body: some View {
        VStack(spacing: 4) {
            Image(appIcon: icon, size: 22, bold: tinted)
            .foregroundStyle(tinted ? Color.accentColor : .primary)
            .frame(width: 28, height: 22)
            .scaleEffect(isHovering && !isActive && !reduceMotion ? 1.06 : 1.0)

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
        // One element for VoiceOver: the title, plus "selected" on the
        // active mode / tab.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isActive)
    }
}

/// Divider between ReType's Input and Result cards: drag to give one card
/// more room, double-click to split them evenly. VoiceOver users adjust it
/// with the increment / decrement actions.
@MainActor private struct CardSplitHandle: View {
    static let height: CGFloat = 14

    @Binding var fraction: Double
    let availableHeight: CGFloat
    let range: ClosedRange<Double>

    @State private var dragStartFraction: Double?
    @State private var isHovering = false

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(isHovering || dragStartFraction != nil ? 0.6 : 0.3))
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .onHover { inside in
                isHovering = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .onDisappear {
                if isHovering { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard availableHeight > 0 else { return }
                        let start = dragStartFraction ?? clamped(fraction)
                        dragStartFraction = start
                        fraction = clamped(start + value.translation.height / availableHeight)
                    }
                    .onEnded { _ in dragStartFraction = nil }
            )
            .onTapGesture(count: 2) { fraction = clamped(0.5) }
            .help("Drag to resize Input and Result — double-click to split evenly")
            .accessibilityElement()
            .accessibilityLabel("Input and Result divider")
            .accessibilityValue("Input \(Int((clamped(fraction) * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: fraction = clamped(clamped(fraction) + 0.1)
                case .decrement: fraction = clamped(clamped(fraction) - 0.1)
                @unknown default: break
                }
            }
    }
}

@MainActor private struct EmptyInputNotice: View {
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
                    Image(appIcon: .warning, size: 17)
                        .foregroundStyle(.orange)
                    Text("Accessibility permission missing")
                        .font(.body.weight(.medium))
                }
                Text("Type.OH needs Accessibility access to read selected text from other apps. Grant it in System Settings, then press the ReType hotkey again.")
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
