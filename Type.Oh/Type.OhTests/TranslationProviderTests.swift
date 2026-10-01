import Testing
import Foundation
@testable import Type_Oh

struct TranslationProviderTests {

    @Test func allTranslationProvidersHaveDisplayNamesAndDetails() {
        for provider in TranslationProviderID.allCases {
            #expect(!provider.displayName.isEmpty, "\(provider) has an empty display name")
            #expect(!provider.detail.isEmpty, "\(provider) has an empty detail string")
        }
    }

    @Test func translationProviderRawValuesRemainStable() {
        #expect(TranslationProviderID.googleTranslate.rawValue == "googleTranslate")
        #expect(TranslationProviderID.nativeOS.rawValue == "nativeOS")
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

    @Test func defaultTranslationEngineIsGoogleTranslate() {
        #expect(TranslationProviderID.preferred == .googleTranslate)
    }

    @Test func removedAppleLLMEngineDecodesAsGoogleTranslate() throws {
        let decoded = try JSONDecoder().decode(TranslationProviderID.self, from: Data("\"localLLM\"".utf8))
        #expect(decoded == .googleTranslate)
    }

    @Test func googleTranslateParsesSentencesAndDetectedLanguage() throws {
        let json = #"[[["שלום עולם. ","Hello world. ",null,null,3],["מה שלומך?","How are you?",null,null,3]],null,"en"]"#
        let result = try GoogleTranslateService.parse(Data(json.utf8))
        #expect(result.text == "שלום עולם. מה שלומך?")
        #expect(result.detectedSourceLanguage == "en")
    }

    @Test func googleTranslateParsesChromeExtensionShapes() throws {
        let auto = try GoogleTranslateService.parseChromeExtension(Data(#"[["Hallo Welt.\n\nZweiter Absatz.","en"]]"#.utf8))
        #expect(auto.text == "Hallo Welt.\n\nZweiter Absatz.")
        #expect(auto.detectedSourceLanguage == "en")
        let explicit = try GoogleTranslateService.parseChromeExtension(Data(#"["Where is the library?"]"#.utf8))
        #expect(explicit.text == "Where is the library?")
        #expect(explicit.detectedSourceLanguage == nil)
    }

    @Test func googleLanguageCodesUseGoogleSpellings() {
        #expect(GoogleTranslateService.googleCode(for: Locale.Language(identifier: "zh-Hans")) == "zh-CN")
        #expect(GoogleTranslateService.googleCode(for: Locale.Language(identifier: "zh-Hant")) == "zh-TW")
        #expect(GoogleTranslateService.googleCode(for: Locale.Language(identifier: "he")) == "iw")
        #expect(GoogleTranslateService.googleCode(for: Locale.Language(identifier: "en")) == "en")
        #expect(GoogleTranslateService.googleCode(for: Locale.Language(identifier: "pt-BR")) == "pt")
    }
}
