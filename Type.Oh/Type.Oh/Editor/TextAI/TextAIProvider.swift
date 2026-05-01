import Foundation

protocol TextAIProvider: Sendable {
    func fix(text: String, emojify: Bool) async throws -> String
    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String
}

enum ProviderError: Error, LocalizedError {
    case missingAPIKey

    var errorDescription: String? { "API key not set. Add your key in Settings → Providers." }
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
