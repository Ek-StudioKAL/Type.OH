import Testing
@testable import Type_Oh

struct TypeOhCoreTests {

    @Test func providerRawValuesRemainStable() {
        #expect(ProviderID.appleOnDevice.rawValue == "apple")
        #expect(ProviderID.anthropic.rawValue == "anthropic")
        #expect(ProviderID.openAI.rawValue == "openai")
        #expect(ProviderID.google.rawValue == "google")
    }

    @Test func customPresetLimitIsPositiveAndFitsSidebar() {
        #expect(CustomStylePreset.maxCount == 8)
    }

    @Test func customPresetStoresAllFields() {
        let preset = CustomStylePreset(
            id: "custom-test",
            label: "Test",
            emoji: "T",
            promptFragment: "Rewrite in a test style."
        )

        #expect(preset.id == "custom-test")
        #expect(preset.label == "Test")
        #expect(preset.emoji == "T")
        #expect(preset.promptFragment == "Rewrite in a test style.")
    }
}
