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

    @Test func defaultProviderIsAppleOnDevice() {
        #expect(freshStore().activeProvider == .appleOnDevice)
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

    // MARK: - ProviderID

    @Test func appleOnDeviceRequiresNoKey() {
        #expect(ProviderID.appleOnDevice.requiresAPIKey == false)
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
