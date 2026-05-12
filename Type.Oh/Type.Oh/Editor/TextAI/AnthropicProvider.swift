import Foundation

struct AnthropicProvider: TextAIProvider {
    let apiKey: String
    private let model = "claude-haiku-4-5-20251001"

    func fix(text: String, emojify: Bool) async throws -> String {
        let fragment = "Fix all typos, grammar mistakes, and punctuation errors in the following text. Preserve the original meaning and tone exactly."
        return try await complete(textAIPrompt(fragment: fragment, text: text, emojify: emojify))
    }

    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String {
        return try await complete(textAIPrompt(fragment: preset.promptFragment, text: text, emojify: emojify))
    }

    func translate(text: String, sourceLanguage: String?, targetLanguage: String) async throws -> String {
        try await complete(translationPrompt(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage))
    }

    private func complete(_ prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,             forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",       forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model":      model,
            "max_tokens": 2048,
            "messages":   [["role": "user", "content": prompt]]
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 200

        if statusCode != 200 {
            if let apiErr = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw ProviderError.apiError(apiErr.error.message)
            }
            throw ProviderError.httpError(statusCode)
        }

        let json = try JSONDecoder().decode(Response.self, from: data)
        return cleanTextAIOutput(json.content.first?.text ?? "")
    }

    private struct APIErrorResponse: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    private struct Response: Decodable {
        struct Block: Decodable { let text: String }
        let content: [Block]
    }
}
