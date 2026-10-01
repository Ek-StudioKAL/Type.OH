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

    @Test func defaultStoreScratchpadHotkeyIsDefault() {
        #expect(freshStore().scratchpadHotkey == .defaultScratchpad)
    }

    // MARK: - Hotkey defaults

    @Test func defaultVoiceHotkeyIsControlOptionD() {
        #expect(HotkeyConfig.defaultVoice.keyCode == 2)
        #expect(HotkeyConfig.defaultVoice.modifiers == HotkeyConfig.controlOption)
    }

    @Test func defaultEditorHotkeyIsControlOptionR() {
        #expect(HotkeyConfig.defaultEditor.keyCode == 15)
        #expect(HotkeyConfig.defaultEditor.modifiers == HotkeyConfig.controlOption)
    }

    @Test func defaultScratchpadHotkeyIsControlOptionL() {
        #expect(HotkeyConfig.defaultScratchpad.keyCode == 37)
        #expect(HotkeyConfig.defaultScratchpad.modifiers == HotkeyConfig.controlOption)
    }

    @Test func legacyFKeyDefaultsMigrateButCustomHotkeysStay() {
        let store = freshStore()
        store.voiceHotkey = .legacyVoice
        store.editorHotkey = HotkeyConfig(keyCode: 0, modifiers: HotkeyConfig.controlOption) // custom ⌃⌥A
        store.scratchpadHotkey = .legacyScratchpad
        #expect(store.migrateLegacyHotkeys())
        #expect(store.voiceHotkey == .defaultVoice)
        #expect(store.editorHotkey.keyCode == 0)
        #expect(store.scratchpadHotkey == .defaultScratchpad)
        #expect(store.migrateLegacyHotkeys() == false)
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
