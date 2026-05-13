import SwiftUI
import ServiceManagement

enum SettingsTab: String, Codable, Sendable {
    case general, providers, presets, translation, models
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

struct SettingsWindow: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            ProvidersTab()
                .tabItem { Label("Providers", systemImage: "brain.filled.head.profile") }
                .tag(SettingsTab.providers)
            PresetsTab()
                .tabItem { Label("Presets", systemImage: "paintbrush") }
                .tag(SettingsTab.presets)
            TranslationTab()
                .tabItem { Label("Translation", systemImage: "translate") }
                .tag(SettingsTab.translation)
            ModelsTab()
                .tabItem { Label("Whisper", systemImage: "waveform") }
                .tag(SettingsTab.models)
        }
        .frame(width: 600, height: 640)
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
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var voiceHotkeyDraft = HotkeyConfig.defaultVoice
    @State private var editorHotkeyDraft = HotkeyConfig.defaultEditor
    @State private var scratchpadHotkeyDraft: HotkeyConfig? = nil
    @State private var hotkeyError: String?

    var body: some View {
        @Bindable var settings = settings
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
                    Button("Save Hotkeys") {
                        saveHotkeys()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Reset Defaults") {
                        resetHotkeysToDefaults()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
                Text("Changes take effect as soon as you save them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        toggleLoginItem(enabled)
                        settings.save()
                    }
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { _, show in
                        NSApp.setActivationPolicy(show ? .regular : .accessory)
                        settings.save()
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

private struct ProvidersTab: View {
    @Environment(SettingsStore.self) private var settings

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
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Active Provider", selection: $settings.activeProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { p in
                        HStack {
                            Text(p.displayName)
                            if p.requiresAPIKey && keyPresent[p] == false {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .imageScale(.small)
                            }
                        }
                        .tag(p)
                    }
                }
                .onChange(of: settings.activeProvider) { settings.save() }

                if settings.activeProvider.requiresAPIKey && keyPresent[settings.activeProvider] == false {
                    Label(
                        "\(settings.activeProvider.displayName) requires an API key — add it below.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
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

private struct ModelsTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var manager = ModelManager.shared
    @State private var ramMB: Double = ModelManager.processResidentMB
    @State private var ramTimer: Timer?
    @State private var showReloadPrompt = false
    @State private var pendingSwitchModel: String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Active model", selection: $settings.whisperModel) {
                    ForEach(manager.catalogue) { m in
                        Text("\(m.displayName)  \(m.sizeDescription)").tag(m.id)
                    }
                }
                .onChange(of: settings.whisperModel) { _, newModel in
                    settings.save()
                    // If a different model is currently loaded, ask before
                    // unloading + reloading. Whisper reloads cost 1-5 s.
                    if let loaded = manager.loadedModelID, loaded != newModel,
                       manager.isDownloaded(newModel) {
                        pendingSwitchModel = newModel
                        showReloadPrompt = true
                    }
                }

                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        if let loaded = manager.loadedModelID,
                           let info   = manager.catalogue.first(where: { $0.id == loaded }) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Loaded: \(info.displayName)")
                        } else if manager.isDownloaded(settings.whisperModel) {
                            Image(systemName: "circle.fill").foregroundStyle(.teal)
                            Text("Ready — loads on first use").foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Text("No model downloaded").foregroundStyle(.secondary)
                        }
                    }
                }

                LabeledContent("Memory in use") {
                    Text(String(format: "%.0f MB", ramMB))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Loading") {
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

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("typeoh.whisper.reload"), object: nil)
                } label: {
                    Label("Reload Selected Model", systemImage: "arrow.clockwise")
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
    }

    private func startRAMPolling() {
        ramMB = ModelManager.processResidentMB
        ramTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in ramMB = ModelManager.processResidentMB }
        }
    }

    private func stopRAMPolling() {
        ramTimer?.invalidate()
        ramTimer = nil
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
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
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

private struct PresetsTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var editingID: String?
    @State private var draftLabel  = ""
    @State private var draftEmoji  = "🎨"
    @State private var draftPrompt = ""

    var body: some View {
        @Bindable var settings = settings
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
                        Label("Add Preset", systemImage: "plus.circle")
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
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
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

private struct TranslationTab: View {
    @Environment(SettingsStore.self) private var settings

    @State private var sourceLanguage: Locale.Language? = nil
    @State private var targetLanguage: Locale.Language  = Locale.Language(identifier: "en")
    @State private var hasLoadedFromSettings = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Translation Provider") {
                Picker("Engine", selection: Binding(
                    get: { settings.translationProvider ?? .nativeOS },
                    set: { settings.translationProvider = $0; settings.save() }
                )) {
                    ForEach(TranslationProviderID.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.inline)

                if let current = settings.translationProvider {
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
                .onChange(of: sourceLanguage) { persist() }
                .onChange(of: targetLanguage) { persist() }

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
