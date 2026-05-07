import SwiftUI
import ServiceManagement

struct SettingsWindow: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
            ProvidersTab()
                .tabItem { Label("Providers", systemImage: "brain.filled.head.profile") }
            ModelsTab()
                .tabItem { Label("Models", systemImage: "waveform") }
        }
        .frame(width: 520, height: 620)
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
        scratchpadHotkeyDraft = nil
        hotkeyError = nil
        saveHotkeys()
    }
}

// MARK: - Providers

private struct ProvidersTab: View {
    @Environment(SettingsStore.self) private var settings

    @State private var storedKeys:       [ProviderID: String] = [:]
    @State private var editingProvider:  ProviderID?
    @State private var draftKey         = ""
    @State private var saveError:        String?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Active Provider", selection: $settings.activeProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { p in
                        HStack {
                            Text(p.displayName)
                            if p.requiresAPIKey && storedKeys[p] == nil {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .imageScale(.small)
                            }
                        }
                        .tag(p)
                    }
                }
                .onChange(of: settings.activeProvider) { settings.save() }

                if settings.activeProvider.requiresAPIKey && storedKeys[settings.activeProvider] == nil {
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
                Text("If a key you entered before isn't working, tap Change to re-enter it.")
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
        .onAppear { loadKeys() }
    }

    @ViewBuilder
    private func apiKeyRow(_ provider: ProviderID) -> some View {
        let stored = storedKeys[provider]
        LabeledContent(provider.displayName) {
            if editingProvider == provider {
                HStack {
                    SecureField("Paste key…", text: $draftKey)
                        .frame(width: 190)
                    Button("Save") {
                        let ok = KeychainStore.save(key: draftKey, for: provider)
                        if ok {
                            storedKeys[provider] = draftKey
                            draftKey = ""; editingProvider = nil; saveError = nil
                        } else {
                            saveError = "Keychain error — make sure the app is signed and try again."
                        }
                    }.buttonStyle(.bordered)
                    Button("Cancel") { draftKey = ""; editingProvider = nil; saveError = nil }
                }
            } else {
                HStack {
                    Text(stored.map { "••••" + String($0.suffix(4)) } ?? "Not set")
                        .foregroundStyle(stored == nil ? .secondary : .primary)
                    Button(stored == nil ? "Set" : "Change") { draftKey = ""; editingProvider = provider }
                        .buttonStyle(.bordered)
                    if stored != nil {
                        Button("Clear") { KeychainStore.delete(for: provider); storedKeys[provider] = nil }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func loadKeys() {
        for p in ProviderID.allCases where p.requiresAPIKey {
            storedKeys[p] = KeychainStore.load(for: p)
        }
    }
}

// MARK: - Models

private struct ModelsTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var manager = ModelManager.shared
    @State private var ramMB: Double = ModelManager.processResidentMB
    @State private var ramTimer: Timer?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Active model", selection: $settings.whisperModel) {
                    ForEach(manager.catalogue) { m in
                        Text("\(m.displayName)  \(m.sizeDescription)").tag(m.id)
                    }
                }
                .onChange(of: settings.whisperModel) { settings.save() }

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
