import Testing
@testable import Type_Oh

struct TranslationProviderTests {

    @Test func allTranslationProvidersHaveDisplayNamesAndDetails() {
        for provider in TranslationProviderID.allCases {
            #expect(!provider.displayName.isEmpty, "\(provider) has an empty display name")
            #expect(!provider.detail.isEmpty, "\(provider) has an empty detail string")
        }
    }

    @Test func translationProviderRawValuesRemainStable() {
        #expect(TranslationProviderID.nativeOS.rawValue == "nativeOS")
        #expect(TranslationProviderID.localLLM.rawValue == "localLLM")
        #expect(TranslationProviderID.apiLLM.rawValue == "apiLLM")
    }

    @Test func nativeOSDescriptionMentionsLimitedLanguages() {
        #expect(TranslationProviderID.nativeOS.detail.contains("limited languages"))
    }

    @Test func unselectedTranslationEngineHasActionableError() {
        let error = TranslationDispatcher.Failure.engineUnselected

        #expect(error.errorDescription == "Pick a translation engine in Settings → Translation.")
    }

    @Test func nativeMissingLanguagePackHasActionableError() {
        let error = TranslationDispatcher.Failure.nativeMissingLanguagePack

        #expect(error.errorDescription?.contains("language pack") == true)
    }

    @Test func noActiveProviderHasActionableError() {
        let error = TranslationDispatcher.Failure.noActiveProvider

        #expect(error.errorDescription?.contains("cloud provider") == true)
    }
}
