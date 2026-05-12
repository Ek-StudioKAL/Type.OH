import Foundation
import FoundationModels

struct AppleOnDeviceProvider: TextAIProvider {

    func fix(text: String, emojify: Bool) async throws -> String {
        try checkAvailability()
        let fragment = "Fix all typos, grammar mistakes, and punctuation errors in the following text. Preserve the original meaning and tone exactly."
        return try await generate(prompt: textAIPrompt(fragment: fragment, text: text, emojify: emojify))
    }

    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String {
        try checkAvailability()
        return try await generate(prompt: textAIPrompt(fragment: preset.promptFragment, text: text, emojify: emojify))
    }

    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String {
        try checkAvailability()
        return try await generate(prompt: translationPrompt(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
    }

    private func generate(prompt: String) async throws -> String {
        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return cleanTextAIOutput(response.content)
    }

    private func checkAvailability() throws {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return }
        throw AppleAIError.unavailable(String(describing: availability))
    }

    enum AppleAIError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? {
            switch self {
            case .unavailable(let detail):
                "Apple Intelligence isn't available (\(detail)). Enable it in System Settings → Apple Intelligence & Siri, or pick a cloud provider in Settings → Providers."
            }
        }
    }
}
