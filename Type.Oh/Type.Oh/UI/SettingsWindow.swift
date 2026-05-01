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
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Hotkeys") {
                hotkeyRow("Voice recording", symbol: "⌃F13")
                hotkeyRow("AI Editor",        symbol: "⌥F13")
                Text("Hotkey reconfiguration coming in a future update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        toggleLoginItem(enabled)
                        settings.save()
                    }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func hotkeyRow(_ label: String, symbol: String) -> some View {
        LabeledContent(label) {
            Text(symbol)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private func toggleLoginItem(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}

// MARK: - Providers

private struct ProvidersTab: View {
    @Environment(SettingsStore.self) private var settings

    @State private var storedKeys:       [ProviderID: String] = [:]
    @State private var editingProvider:  ProviderID?
    @State private var draftKey         = ""

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Active Provider", selection: $settings.activeProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: settings.activeProvider) { settings.save() }
            }
            Section("API Keys") {
                ForEach(ProviderID.allCases.filter(\.requiresAPIKey), id: \.self) { apiKeyRow($0) }
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
                        KeychainStore.save(key: draftKey, for: provider)
                        storedKeys[provider] = draftKey
                        draftKey = ""; editingProvider = nil
                    }.buttonStyle(.bordered)
                    Button("Cancel") { draftKey = ""; editingProvider = nil }
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
            }
            Section {
                ForEach(manager.catalogue) { m in
                    modelRow(m)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func modelRow(_ m: WhisperModelInfo) -> some View {
        let downloaded = manager.isDownloaded(m.id)
        LabeledContent("\(m.displayName) (\(m.sizeDescription))") {
            if downloaded {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Download") {
                    Task { try? await manager.download(m.id) }
                }.buttonStyle(.bordered)
            }
        }
    }
}
