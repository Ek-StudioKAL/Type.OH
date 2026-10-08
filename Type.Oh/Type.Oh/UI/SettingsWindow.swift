import AppKit
import SwiftUI
import ServiceManagement

enum SettingsTab: String, Codable, CaseIterable, Sendable {
    case general, providers, presets, translation, models

    var title: String {
        switch self {
        case .general: "General"
        case .providers: "Providers"
        case .presets: "Presets"
        case .translation: "Translation"
        case .models: "Whisper"
        }
    }

    var icon: AppIcon {
        switch self {
        case .general: .generalSettings
        case .providers: .aiProviders
        case .presets: .style
        case .translation: .translate
        case .models: .voiceModel
        }
    }

    /// Window height per tab, so short tabs don't leave half the window
    /// empty. Longer content scrolls inside the tab's form.
    var preferredHeight: CGFloat {
        switch self {
        case .general: ControlStrip.hasTouchBar ? 680 : 570 // + the Touch Bar section
        case .providers: 470
        case .presets: 520
        case .translation: 510
        case .models: 700
        }
    }
}

enum SettingsTabRoute {
    private static let pendingTabKey = "typeoh.pendingSettingsTab"
    static let notificationName = NSNotification.Name("typeoh.openSettings.tab")

    static func open(_ tab: SettingsTab, defaults: UserDefaults = .standard) {
        setPendingTab(tab, defaults: defaults)
        NotificationCenter.default.post(name: notificationName, object: tab.rawValue)
    }

    static func setPendingTab(_ tab: SettingsTab, defaults: UserDefaults = .standard) {
        defaults.set(tab.rawValue, forKey: pendingTabKey)
    }

    static func consumePendingTab(defaults: UserDefaults = .standard) -> SettingsTab? {
        defer { defaults.removeObject(forKey: pendingTabKey) }
        guard let rawValue = defaults.string(forKey: pendingTabKey) else { return nil }
        return SettingsTab(rawValue: rawValue)
    }

    static func clearPendingTab(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingTabKey)
    }
}

@MainActor struct SettingsWindow: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selectedTab: $selectedTab)
                .padding(.top, 18)
                .padding(.bottom, 8)

            selectedTabContent
        }
        .frame(width: 620, height: selectedTab.preferredHeight)
        .background(WindowDragBehaviorConfigurator())
        .typeOhFocusEffectDisabled()
        .onAppear {
            if let pendingTab = SettingsTabRoute.consumePendingTab() {
                selectedTab = pendingTab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsTabRoute.notificationName)) { note in
            if let raw = note.object as? String,
               let tab = SettingsTab(rawValue: raw) {
                SettingsTabRoute.clearPendingTab()
                selectedTab = tab
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            GeneralTab()
        case .providers:
            ProvidersTab()
        case .presets:
            PresetsTab()
        case .translation:
            TranslationTab()
        case .models:
            ModelsTab()
        }
    }
}

@MainActor private struct WindowDragBehaviorConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.isMovableByWindowBackground = true
        }
    }
}

@MainActor private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    AccentToolbarLabel(
                        title: tab.title,
                        icon: tab.icon,
                        isActive: selectedTab == tab
                    )
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }
}

// MARK: - General

@MainActor private struct GeneralTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var voiceHotkeyDraft = HotkeyConfig.defaultVoice
    @State private var editorHotkeyDraft = HotkeyConfig.defaultEditor
    @State private var scratchpadHotkeyDraft: HotkeyConfig? = nil
    @State private var hotkeyError: String?

    var body: some View {
        Form {
            Section("Hotkeys") {
                HotkeyConfigurationEditor(
                    voiceHotkey: $voiceHotkeyDraft,
                    editorHotkey: $editorHotkeyDraft,
                    scratchpadHotkey: $scratchpadHotkeyDraft
                )
                if let hotkeyError {
                    Text(hotkeyError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Reset Defaults") {
                        resetHotkeysToDefaults()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("New shortcuts apply as soon as you record them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { enabled in
                        toggleLoginItem(enabled)
                        settings.save()
                    }
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { show in
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                        settings.save()
                    }
            }
            if ControlStrip.hasTouchBar {
                Section("Touch Bar") {
                    Picker("Control Strip button", selection: $settings.controlStripAction) {
                        ForEach(ControlStripAction.allCases, id: \.self) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    .onChange(of: settings.controlStripAction) { _ in
                        settings.save()
                        NotificationCenter.default.post(name: NSNotification.Name("typeoh.controlStripChanged"), object: nil)
                    }
                    Text("Shows in the small Control Strip, whatever app is in front. For the other actions, use Quick Actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Re-run Setup Wizard…") {
                    NotificationCenter.default.post(name: NSNotification.Name("typeoh.showOnboarding"), object: nil)
                }
                .help("Reopen the onboarding wizard to reconfigure permissions, models, and providers")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { syncHotkeyDraftsFromSettings() }
        .onChange(of: voiceHotkeyDraft) { _ in autosaveHotkeys() }
        .onChange(of: editorHotkeyDraft) { _ in autosaveHotkeys() }
        .onChange(of: scratchpadHotkeyDraft) { _ in autosaveHotkeys() }
    }

    /// Save every valid change right away, like the rest of Settings. An
    /// invalid combination (missing modifier, duplicate) shows the error and
    /// keeps the last saved hotkeys until it's fixed.
    private func autosaveHotkeys() {
        guard voiceHotkeyDraft != settings.voiceHotkey
                || editorHotkeyDraft != settings.editorHotkey
                || scratchpadHotkeyDraft != settings.scratchpadHotkey else {
            hotkeyError = nil
            return
        }
        saveHotkeys()
    }

    private func toggleLoginItem(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }

    private func syncHotkeyDraftsFromSettings() {
        voiceHotkeyDraft = settings.voiceHotkey
        editorHotkeyDraft = settings.editorHotkey
        scratchpadHotkeyDraft = settings.scratchpadHotkey
    }

    private func saveHotkeys() {
        if let error = validateHotkeys(
            voice: voiceHotkeyDraft,
            editor: editorHotkeyDraft,
            scratchpad: scratchpadHotkeyDraft
        ) {
            hotkeyError = error
            return
        }

        hotkeyError = nil
        settings.voiceHotkey = voiceHotkeyDraft
        settings.editorHotkey = editorHotkeyDraft
        settings.scratchpadHotkey = scratchpadHotkeyDraft
        settings.save()
        NotificationCenter.default.post(name: NSNotification.Name("typeoh.hotkeysChanged"), object: nil)
    }

    private func resetHotkeysToDefaults() {
        voiceHotkeyDraft = .defaultVoice
        editorHotkeyDraft = .defaultEditor
        scratchpadHotkeyDraft = .defaultScratchpad
        hotkeyError = nil
        saveHotkeys()
    }
}

// MARK: - Providers

@MainActor private struct ProvidersTab: View {
    @EnvironmentObject private var settings: SettingsStore

    /// Presence per provider — populated from `KeychainStore.hasKey`, which
    /// is a metadata-only query and does *not* trigger the keychain password
    /// prompt. Opening Settings is therefore free.
    @State private var keyPresent:      [ProviderID: Bool] = [:]
    /// Last-4 of the actual key — only filled in after the user explicitly
    /// taps Reveal, which performs the prompting load.
    @State private var revealedSuffix:  [ProviderID: String] = [:]
    @State private var editingProvider: ProviderID?
    @State private var draftKey        = ""
    @State private var saveError:       String?

    var body: some View {
        Form {
            Section {
                Picker("Active Provider", selection: $settings.activeProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { p in
                        HStack {
                            Text(p.displayName)
                            if p.requiresAPIKey && keyPresent[p] == false {
                                Image(appIcon: .needsAttention, size: 13)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .tag(p)
                    }
                }
                .onChange(of: settings.activeProvider) { _ in settings.save() }

                if settings.activeProvider.requiresAPIKey && keyPresent[settings.activeProvider] == false {
                    Label {
                        Text("\(settings.activeProvider.displayName) requires an API key — add it below.")
                    } icon: {
                        Image(appIcon: .warning, size: 14)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
            Section("API Keys") {
                ForEach(ProviderID.allCases.filter(\.requiresAPIKey), id: \.self) { apiKeyRow($0) }
                Text("Stored keys are kept in macOS Keychain. Reveal reads the actual key (you'll see a one-time keychain prompt — tick \"Always Allow\" to avoid future prompts).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let err = saveError {
                Section {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { refreshPresence() }
    }

    @ViewBuilder
    private func apiKeyRow(_ provider: ProviderID) -> some View {
        let present = keyPresent[provider] ?? false
        let suffix  = revealedSuffix[provider]
        LabeledContent(provider.displayName) {
            if editingProvider == provider {
                HStack {
                    SecureField("Paste key…", text: $draftKey)
                        .frame(width: 190)
                    Button("Save") {
                        let ok = KeychainStore.save(key: draftKey, for: provider)
                        if ok {
                            keyPresent[provider] = true
                            revealedSuffix[provider] = String(draftKey.suffix(4))
                            draftKey = ""; editingProvider = nil; saveError = nil
                        } else {
                            saveError = "Keychain error — make sure the app is signed and try again."
                        }
                    }.buttonStyle(.bordered)
                    Button("Cancel") { draftKey = ""; editingProvider = nil; saveError = nil }
                }
            } else {
                HStack {
                    if let suffix {
                        Text("••••" + suffix).foregroundStyle(.primary)
                    } else if present {
                        Text("Configured").foregroundStyle(.secondary)
                    } else {
                        Text("Not set").foregroundStyle(.secondary)
                    }
                    Button(present ? "Change" : "Set") {
                        draftKey = ""; editingProvider = provider
                    }
                    .buttonStyle(.bordered)
                    if present, suffix == nil {
                        Button("Reveal") {
                            if let key = KeychainStore.load(for: provider) {
                                revealedSuffix[provider] = String(key.suffix(4))
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    if present {
                        Button("Clear") {
                            KeychainStore.delete(for: provider)
                            keyPresent[provider] = false
                            revealedSuffix[provider] = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func refreshPresence() {
        for p in ProviderID.allCases where p.requiresAPIKey {
            keyPresent[p] = KeychainStore.hasKey(for: p)
        }
    }
}

// MARK: - Models


@MainActor private struct ModelsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var manager = ModelManager.shared
    @State private var ramMB: Double = ModelManager.processResidentMB
    @State private var ramTimer: Timer?
    @State private var showReloadPrompt = false
    @State private var pendingSwitchModel: String?
    @State private var pendingDeleteModel: WhisperModelInfo?

    private var languageOptions: [Locale.Language] {
        var seen = Set<String>()
        return Locale.availableIdentifiers
            .compactMap { identifier -> Locale.Language? in
                let language = Locale.Language(identifier: identifier)
                let minimal = language.minimalIdentifier
                guard !minimal.isEmpty, seen.insert(minimal).inserted else { return nil }
                return Locale.Language(identifier: minimal)
            }
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section("Whisper Model Configuration") {
                Picker("Active model", selection: $settings.whisperModel) {
                    ForEach(manager.catalogue) { m in
                        Text("\(m.displayName)  \(m.sizeDescription)").tag(m.id)
                    }
                }
                .onChange(of: settings.whisperModel) { newModel in
                    settings.save()
                    // If a different model is currently loaded, ask before
                    // unloading + reloading. Whisper reloads cost 1-5 s.
                    if let loaded = manager.loadedModelID, loaded != newModel,
                       manager.isDownloaded(newModel) {
                        pendingSwitchModel = newModel
                        showReloadPrompt = true
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    LabeledContent("Status") {
                        modelStatusLabel
                    }
                    Divider()
                    LabeledContent("Memory") {
                        Text(String(format: "%.0f MB", ramMB))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input language")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LangPickerButton(
                            title: settings.whisperInputLanguage.map { displayName(Locale.Language(identifier: $0)) } ?? "Auto-detect",
                            isAuto: settings.whisperInputLanguage == nil,
                            supported: languageOptions,
                            includeAuto: true
                        ) { language in
                            settings.whisperInputLanguage = language?.minimalIdentifier
                            settings.save()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output language")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        LangPickerButton(
                            title: settings.whisperOutputLanguage.map { displayName(Locale.Language(identifier: $0)) } ?? "Spoken language",
                            isAuto: settings.whisperOutputLanguage == nil,
                            supported: languageOptions,
                            includeAuto: true,
                            autoTitle: "Spoken language"
                        ) { language in
                            settings.whisperOutputLanguage = language?.minimalIdentifier
                            settings.save()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                Toggle("Keep model loaded in memory", isOn: Binding(
                    get: { settings.whisperKeepLoaded },
                    set: { value in
                        settings.whisperKeepLoaded = value
                        settings.save()
                        if !value {
                            // Free the model now so the toggle has immediate effect.
                            NotificationCenter.default.post(name: NSNotification.Name("typeoh.whisper.unload"), object: nil)
                        } else if manager.loadedModelID == nil,
                                  manager.isDownloaded(settings.whisperModel) {
                            // User re-enabled and nothing is loaded — warm up.
                            NotificationCenter.default.post(name: NSNotification.Name("typeoh.whisper.reload"), object: nil)
                        }
                    }
                ))
                .help("Off: model is dropped from RAM between dictations. Saves memory but next dictation pays a 1-5 s warm-up.")

                Text("Keeping the model loaded uses more memory while idle, but avoids the next dictation waiting for Whisper to warm up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("typeoh.whisper.reload"), object: nil)
                } label: {
                    Label {
                        Text("Reload Selected Model")
                    } icon: {
                        Image(appIcon: .reload, size: 16)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!manager.isDownloaded(settings.whisperModel))
            }
            if let err = manager.lastError {
                Section {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                ForEach(manager.catalogue) { m in
                    modelRow(m)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { startRAMPolling() }
        .onDisappear { stopRAMPolling() }
        .alert("Reload Whisper model?",
               isPresented: $showReloadPrompt,
               presenting: pendingSwitchModel) { _ in
            Button("Reload Selected Model") {
                NotificationCenter.default.post(name: NSNotification.Name("typeoh.whisper.reload"), object: nil)
                pendingSwitchModel = nil
            }
            Button("Later", role: .cancel) {
                pendingSwitchModel = nil
            }
        } message: { model in
            let info = manager.catalogue.first(where: { $0.id == model })
            Text("Restart Whisper to switch to \(info?.displayName ?? model). The currently loaded model will be unloaded and the new one loaded — this takes 1-5 s.")
        }
        .alert("Delete \(pendingDeleteModel?.displayName ?? "model")?",
               isPresented: Binding(
                   get: { pendingDeleteModel != nil },
                   set: { if !$0 { pendingDeleteModel = nil } }
               ),
               presenting: pendingDeleteModel) { model in
            Button("Delete", role: .destructive) {
                deleteModel(model)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteModel = nil
            }
        } message: { model in
            if model.id == settings.whisperModel {
                Text("This frees \(model.sizeDescription). It's your active model, so dictation won't work until you download it again or pick another.")
            } else {
                Text("This frees \(model.sizeDescription). You can download it again any time.")
            }
        }
    }

    private func deleteModel(_ model: WhisperModelInfo) {
        if manager.loadedModelID == model.id {
            NotificationCenter.default.post(name: NSNotification.Name("typeoh.whisper.unload"), object: nil)
        }
        manager.delete(model.id)
        pendingDeleteModel = nil
    }

    private func startRAMPolling() {
        ramMB = ModelManager.processResidentMB
        ramTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in ramMB = ModelManager.processResidentMB }
        }
    }

    private var whisperInputLanguageBinding: Binding<Locale.Language?> {
        Binding(
            get: { settings.whisperInputLanguage.map(Locale.Language.init(identifier:)) },
            set: { value in
                settings.whisperInputLanguage = value?.minimalIdentifier
                settings.save()
            }
        )
    }

    private var whisperOutputLanguageBinding: Binding<Locale.Language> {
        Binding(
            get: { Locale.Language(identifier: settings.whisperOutputLanguage ?? settings.whisperInputLanguage ?? "en") },
            set: { value in
                settings.whisperOutputLanguage = value.minimalIdentifier
                settings.save()
            }
        )
    }

    private func stopRAMPolling() {
        ramTimer?.invalidate()
        ramTimer = nil
    }

    @ViewBuilder
    private var modelStatusLabel: some View {
        HStack(spacing: 6) {
            if let loaded = manager.loadedModelID,
               let info = manager.catalogue.first(where: { $0.id == loaded }) {
                Image(appIcon: .granted, size: 16).foregroundStyle(.green)
                Text("Loaded: \(info.displayName)")
            } else if manager.isDownloaded(settings.whisperModel) {
                Image(appIcon: .statusDot, size: 16).foregroundStyle(.teal)
                Text("Ready").foregroundStyle(.secondary)
            } else {
                Image(appIcon: .needsAttention, size: 16).foregroundStyle(.orange)
                Text("No model").foregroundStyle(.secondary)
            }
        }
    }

    private func displayName(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    @ViewBuilder
    private func modelRow(_ m: WhisperModelInfo) -> some View {
        let downloaded = manager.isDownloaded(m.id)
        let isDownloadingThis = manager.downloadingModelID == m.id
        LabeledContent("\(m.displayName) (\(m.sizeDescription))") {
            if isDownloadingThis {
                HStack(spacing: 8) {
                    ProgressView(value: manager.downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 90)
                    Text("\(Int(manager.downloadProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if downloaded {
                HStack(spacing: 10) {
                    Image(appIcon: .granted, size: 16)
                        .foregroundStyle(.green)
                        .accessibilityLabel("Downloaded")
                    Button {
                        pendingDeleteModel = m
                    } label: {
                        Image(appIcon: .clear, size: 15)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete \(m.displayName) to free \(m.sizeDescription)")
                    .accessibilityLabel("Delete \(m.displayName)")
                }
            } else {
                Button("Download") {
                    Task { try? await manager.download(m.id) }
                }
                .buttonStyle(.bordered)
                .disabled(manager.isDownloading)
            }
        }
    }
}

// MARK: - Presets

@MainActor private struct PresetsTab: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var editingID: String?
    @State private var draftLabel  = ""
    @State private var draftEmoji  = "🎨"
    @State private var draftPrompt = ""

    var body: some View {
        Form {
            Section {
                Text("Custom presets show up alongside the built-in styles in LazyPad's sidebar. Up to \(CustomStylePreset.maxCount) custom presets are supported.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Your Presets") {
                if settings.customStylePresets.isEmpty {
                    Text("No custom presets yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.customStylePresets) { preset in
                    presetRow(preset)
                }
                if settings.customStylePresets.count < CustomStylePreset.maxCount {
                    Button {
                        beginAdding()
                    } label: {
                        Label {
                            Text("Add Preset")
                        } icon: {
                            Image(appIcon: .addPreset, size: 16)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if editingID != nil {
                Section(editingID == "new" ? "New Preset" : "Edit Preset") {
                    LabeledContent("Name") {
                        TextField("e.g. Pirate", text: $draftLabel)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Emoji") {
                        TextField("🎨", text: $draftEmoji)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $draftPrompt)
                            .font(.body)
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    HStack {
                        Button("Cancel") { editingID = nil }
                        Spacer()
                        Button("Save") { commitDraft() }
                            .buttonStyle(.borderedProminent)
                            .disabled(draftLabel.trimmingCharacters(in: .whitespaces).isEmpty ||
                                      draftPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func presetRow(_ preset: CustomStylePreset) -> some View {
        HStack {
            Text(preset.emoji)
            Text(preset.label).font(.body.weight(.medium))
            Text(preset.promptFragment)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Button("Edit") {
                editingID = preset.id
                draftLabel  = preset.label
                draftEmoji  = preset.emoji
                draftPrompt = preset.promptFragment
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            Button(role: .destructive) {
                settings.customStylePresets.removeAll { $0.id == preset.id }
                settings.save()
            } label: {
                Image(appIcon: .clear, size: 15)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Delete \(preset.label)")
            .accessibilityLabel("Delete \(preset.label)")
        }
    }

    private func beginAdding() {
        editingID = "new"
        draftLabel = ""
        draftEmoji = "🎨"
        draftPrompt = ""
    }

    private func commitDraft() {
        let label  = draftLabel.trimmingCharacters(in: .whitespaces)
        let emoji  = draftEmoji.trimmingCharacters(in: .whitespaces).isEmpty ? "🎨" : draftEmoji
        let prompt = draftPrompt.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !prompt.isEmpty else { return }

        if let id = editingID, id != "new",
           let idx = settings.customStylePresets.firstIndex(where: { $0.id == id }) {
            settings.customStylePresets[idx].label = label
            settings.customStylePresets[idx].emoji = emoji
            settings.customStylePresets[idx].promptFragment = prompt
        } else {
            guard settings.customStylePresets.count < CustomStylePreset.maxCount else { return }
            let newPreset = CustomStylePreset(
                id: "custom-\(UUID().uuidString.prefix(8))",
                label: label,
                emoji: emoji,
                promptFragment: prompt
            )
            settings.customStylePresets.append(newPreset)
        }
        settings.save()
        editingID = nil
    }
}

// MARK: - Translation

@MainActor private struct TranslationTab: View {
    @EnvironmentObject private var settings: SettingsStore

    @State private var sourceLanguage: Locale.Language? = nil
    @State private var targetLanguage: Locale.Language  = Locale.Language(identifier: "en")
    @State private var hasLoadedFromSettings = false

    var body: some View {
        Form {
            Section("Translation Provider") {
                Picker("Engine", selection: Binding(
                    get: { settings.translationProvider ?? .preferred },
                    set: { settings.translationProvider = $0; settings.save() }
                )) {
                    ForEach(TranslationProviderID.availableCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.inline)

                if !NativeTranslationSupport.isAvailable {
                    Text("Native macOS translation needs macOS 15 or later, so it isn't offered on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let current = settings.translationProvider ?? Optional(.preferred) {
                    Text(current.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Default Languages") {
                LanguagePicker(
                    sourceLanguage: $sourceLanguage,
                    targetLanguage: $targetLanguage,
                    compact: false,
                    availability: settings.translationProvider == .nativeOS ? .nativeOSOffline : .allLocaleLanguages
                )
                .onChange(of: sourceLanguage) { _ in persist() }
                .onChange(of: targetLanguage) { _ in persist() }

                Text("ReType and LazyPad use these defaults — translate buttons run instantly without re-asking.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadFromSettingsIfNeeded() }
    }

    private func loadFromSettingsIfNeeded() {
        guard !hasLoadedFromSettings else { return }
        sourceLanguage = settings.sourceLanguage.map(Locale.Language.init(identifier:))
        targetLanguage = Locale.Language(identifier: settings.targetLanguage)
        hasLoadedFromSettings = true
    }

    private func persist() {
        settings.sourceLanguage = sourceLanguage?.minimalIdentifier
        settings.targetLanguage = targetLanguage.minimalIdentifier
        settings.save()
    }
}
