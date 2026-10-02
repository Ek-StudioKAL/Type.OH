import Testing
import Foundation
@testable import Type_Oh

@MainActor
struct SettingsStoreTests {

    /// Fresh store backed by a temp path that doesn't exist — all property defaults are preserved.
    private func freshStore() -> SettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typeoh-test-\(UUID().uuidString).json")
        return SettingsStore(settingsURL: url)
    }

    // MARK: - Default values

    @Test func defaultWhisperModel() {
        #expect(freshStore().whisperModel == "openai_whisper-base")
    }

    @Test func defaultWhisperLanguages() {
        let store = freshStore()
        #expect(store.whisperInputLanguage == nil)
        #expect(store.whisperOutputLanguage == nil)
    }

    @Test func defaultProviderIsFallback() {
        #expect(freshStore().activeProvider == .fallback)
    }

    @Test func defaultShowInDockIsTrue() {
        #expect(freshStore().showInDock == true)
    }

    @Test func defaultOnboardingNotCompleted() {
        #expect(freshStore().hasCompletedOnboarding == false)
    }

    @Test func defaultStoreScratchpadHotkeyIsF15() {
        #expect(freshStore().scratchpadHotkey == .defaultScratchpad)
    }

    // MARK: - Hotkey defaults

    @Test func defaultVoiceHotkeyIsF13() {
        #expect(HotkeyConfig.defaultVoice.keyCode == 105)
        #expect(HotkeyConfig.defaultVoice.modifiers == 0)
    }

    @Test func defaultEditorHotkeyIsF14() {
        #expect(HotkeyConfig.defaultEditor.keyCode == 107)
        #expect(HotkeyConfig.defaultEditor.modifiers == 0)
    }

    @Test func defaultScratchpadHotkeyIsF15() {
        #expect(HotkeyConfig.defaultScratchpad.keyCode == 113)
        #expect(HotkeyConfig.defaultScratchpad.modifiers == 0)
    }

    @Test func savedHotkeysReloadUnchanged() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("typeoh-test-\(UUID().uuidString).json")
        let store = SettingsStore(settingsURL: url)
        let controlOptionD = HotkeyConfig(keyCode: 2, modifiers: 0x1000 | 0x0800)
        store.voiceHotkey = controlOptionD
        store.save()

        let reloaded = SettingsStore(settingsURL: url)
        #expect(reloaded.voiceHotkey == controlOptionD)
        #expect(reloaded.editorHotkey == .defaultEditor)
        #expect(reloaded.scratchpadHotkey == .defaultScratchpad)
    }

    // MARK: - ProviderID

    #if canImport(FoundationModels)
    @Test func appleOnDeviceIsFallbackAndRequiresNoKey() {
        #expect(ProviderID.fallback == .appleOnDevice)
        #expect(ProviderID.appleOnDevice.requiresAPIKey == false)
    }
    #else
    @Test func appleProviderDecodesAsFallbackWithoutFoundationModels() throws {
        let decoded = try JSONDecoder().decode(ProviderID.self, from: Data("\"apple\"".utf8))
        #expect(decoded == .fallback)
        #expect(ProviderID.fallback == .anthropic)
    }
    #endif

    @Test func unknownProviderDecodesAsFallback() throws {
        let decoded = try JSONDecoder().decode(ProviderID.self, from: Data("\"mistral\"".utf8))
        #expect(decoded == .fallback)
    }

    @Test func cloudProvidersRequireKey() {
        for p in [ProviderID.anthropic, .openAI, .google] {
            #expect(p.requiresAPIKey, "\(p) should require an API key")
        }
    }

    @Test func providerDisplayNamesNonEmpty() {
        for p in ProviderID.allCases {
            #expect(!p.displayName.isEmpty, "\(p) display name is empty")
        }
    }
}
