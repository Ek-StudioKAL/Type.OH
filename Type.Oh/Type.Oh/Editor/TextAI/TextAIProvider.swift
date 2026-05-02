import Foundation

protocol TextAIProvider: Sendable {
    func fix(text: String, emojify: Bool) async throws -> String
    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String
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
    if emojify { prompt += "\n\nSprinkle in relevant emojis throughout the response." }
    prompt += "\n\nReturn only the rewritten text, nothing else."
    return prompt
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
