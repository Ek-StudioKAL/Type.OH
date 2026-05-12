import Testing
@testable import Type_Oh

struct TextAIProviderTests {

    @Test func rewritePromptDoesNotContainLeakyLanguagePolicySentence() {
        let prompt = textAIPrompt(
            fragment: "Fix the text.",
            text: "hello",
            emojify: false
        )

        #expect(!prompt.contains("The original input language will remain unchanged"))
        #expect(!prompt.contains("No language switching is allowed"))
        #expect(prompt.contains("Return only the rewritten text"))
    }

    @Test func cleanOutputRemovesLeakedLanguagePolicyLineAtEnd() {
        let output = "Fixed text.\nThe original input language will remain unchanged unless the user specifically requests a translation. No language switching is allowed."

        #expect(cleanTextAIOutput(output) == "Fixed text.")
    }

    @Test func cleanOutputRemovesLeakedLanguagePolicyLineInMiddle() {
        let output = "First paragraph.\nPreserve the original input language unless the user explicitly asks for translation. Do not switch languages.\nSecond paragraph."

        #expect(cleanTextAIOutput(output) == "First paragraph.\nSecond paragraph.")
    }

    @Test func cleanOutputTrimsWhitespaceAroundProviderResponse() {
        #expect(cleanTextAIOutput("\n\nResult text.\n") == "Result text.")
    }

    @Test func translationPromptReturnsOnlyTranslatedTextInstruction() {
        let prompt = translationPrompt(text: "bonjour", sourceLanguage: "French", targetLanguage: "English")

        #expect(prompt.contains("Translate the following text into English"))
        #expect(prompt.contains("Return only the translated text"))
    }
}
