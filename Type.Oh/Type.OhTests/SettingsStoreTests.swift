import Testing
import Foundation
@testable import Type_Oh

@MainActor
struct SettingsStoreTests {

    // MARK: - Default values

    @Test func defaultWhisperModel() {
        let store = SettingsStore()
        #expect(store.whisperModel == "openai_whisper-base")
    }

    @Test func defaultProviderIsAppleOnDevice() {
        let store = SettingsStore()
        #expect(store.activeProvider == .appleOnDevice)
    }

    @Test func defaultShowInDockIsFalse() {
        let store = SettingsStore()
        #expect(store.showInDock == false)
    }

    @Test func defaultOnboardingNotCompleted() {
        let store = SettingsStore()
        #expect(store.hasCompletedOnboarding == false)
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
