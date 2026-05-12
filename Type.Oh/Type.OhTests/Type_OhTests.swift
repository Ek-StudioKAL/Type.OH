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

    @Test func customPresetIsEquatableByAllFields() {
        let lhs = CustomStylePreset(
            id: "custom-test",
            label: "Test",
            emoji: "T",
            promptFragment: "Rewrite in a test style."
        )
        let rhs = CustomStylePreset(
            id: "custom-test",
            label: "Test",
            emoji: "T",
            promptFragment: "Rewrite in a test style."
        )

        #expect(lhs == rhs)
    }
}
