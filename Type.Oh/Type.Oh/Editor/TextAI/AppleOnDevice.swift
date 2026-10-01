// Apple Intelligence needs the FoundationModels SDK (macOS 26). The macOS 13 /
// Intel SwiftPM build compiles this file to nothing.
#if canImport(FoundationModels)
import Foundation
import FoundationModels

struct AppleOnDeviceProvider: TextAIProvider {

    func fix(text: String, emojify: Bool) async throws -> String {
        let fragment = "Fix all typos, grammar mistakes, and punctuation errors in the following text. Preserve the original meaning and tone exactly."
        return try await generate(prompt: textAIPrompt(fragment: fragment, text: text, emojify: emojify))
    }

    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String {
        try await generate(prompt: textAIPrompt(fragment: preset.promptFragment, text: text, emojify: emojify))
    }

    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String {
        try await generate(prompt: translationPrompt(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
    }

    private func generate(prompt: String) async throws -> String {
        // The Xcode target deploys to macOS 26, so this guard only matters for
        // a SwiftPM build made with a newer SDK and run on an older macOS.
        guard #available(macOS 26.0, *) else {
            throw AppleAIError.unavailable("requires macOS 26")
        }
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            throw AppleAIError.unavailable(String(describing: availability))
        }
        let session  = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return cleanTextAIOutput(response.content)
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
#endif
