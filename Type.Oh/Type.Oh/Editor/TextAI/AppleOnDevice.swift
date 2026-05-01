import Foundation
import FoundationModels

struct AppleOnDeviceProvider: TextAIProvider {

    func fix(text: String, emojify: Bool) async throws -> String {
        let fragment = "Fix all typos, grammar mistakes, and punctuation errors in the following text. Preserve the original meaning and tone exactly."
        return try await generate(prompt: textAIPrompt(fragment: fragment, text: text, emojify: emojify))
    }

    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String {
        return try await generate(prompt: textAIPrompt(fragment: preset.promptFragment, text: text, emojify: emojify))
    }

    private func generate(prompt: String) async throws -> String {
        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }
}
