import Foundation

protocol TextAIProvider: Sendable {
    func fix(text: String, emojify: Bool) async throws -> String
    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String
    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String
}

enum ProviderError: Error, LocalizedError {
    case missingAPIKey
    case apiError(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "API key not set — open Settings → Providers to add it."
        case .apiError(let msg):
            "API error: \(msg)"
        case .httpError(let code):
            "Server returned HTTP \(code). Check your API key and account status."
        }
    }
}

// Shared prompt builder used by every provider.
func textAIPrompt(fragment: String, text: String, emojify: Bool) -> String {
    var prompt = "\(fragment)\n\nText:\n\(text)"
    prompt += "\n\nKeep the response in the same language as the input."
    if emojify { prompt += "\n\nSprinkle in relevant emojis throughout the response." }
    prompt += "\n\nReturn only the rewritten text. Do not include explanations, notes, policies, or quoted instructions."
    return prompt
}

func translationPrompt(text: String, sourceLanguage: String?, targetLanguage: String) -> String {
    var prompt = "Translate the following text into \(targetLanguage)."
    if let sourceLanguage, !sourceLanguage.isEmpty {
        prompt += " The source language is \(sourceLanguage)."
    } else {
        prompt += " Detect the source language automatically."
    }
    prompt += " Preserve the original meaning, tone, paragraph breaks, and formatting where possible."
    prompt += "\n\nText:\n\(text)"
    prompt += "\n\nReturn only the translated text, nothing else."
    return prompt
}

func cleanTextAIOutput(_ output: String) -> String {
    let bannedLines = Set([
        "The original input language will remain unchanged unless the user specifically requests a translation. No language switching is allowed.",
        "Preserve the original input language unless the user explicitly asks for translation. Do not switch languages.",
        "Keep the response in the same language as the input."
    ])

    let cleanedLines = output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { line in
            let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !bannedLines.contains(normalized)
        }

    return cleanedLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor
enum ProviderRegistry {
    static func provider(for id: ProviderID) -> any TextAIProvider {
        switch id {
        case .appleOnDevice: AppleOnDeviceProvider()
        case .anthropic:     AnthropicProvider(apiKey: KeychainStore.load(for: .anthropic) ?? "")
        case .openAI:        OpenAIProvider(apiKey:    KeychainStore.load(for: .openAI)    ?? "")
        case .google:        GoogleProvider(apiKey:    KeychainStore.load(for: .google)    ?? "")
        }
    }
}
