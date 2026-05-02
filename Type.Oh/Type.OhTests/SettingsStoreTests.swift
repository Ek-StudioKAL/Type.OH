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

    @Test func defaultShowInDockIsFalse() {
        #expect(freshStore().showInDock == false)
    }

    @Test func defaultOnboardingNotCompleted() {
        #expect(freshStore().hasCompletedOnboarding == false)
    }

    // MARK: - Hotkey defaults

    @Test func defaultVoiceHotkeyIsCtrlF13() {
        #expect(HotkeyConfig.defaultVoice.keyCode == 105)
        #expect(HotkeyConfig.defaultVoice.modifiers == 4096)
    }

    @Test func defaultEditorHotkeyIsOptF13() {
        #expect(HotkeyConfig.defaultEditor.keyCode == 105)
        #expect(HotkeyConfig.defaultEditor.modifiers == 2048)
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
