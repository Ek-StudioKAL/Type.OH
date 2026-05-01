import Foundation

struct OpenAIProvider: TextAIProvider {
    let apiKey: String
    private let model = "gpt-4o-mini"

    func fix(text: String, emojify: Bool) async throws -> String {
        let fragment = "Fix all typos, grammar mistakes, and punctuation errors in the following text. Preserve the original meaning and tone exactly."
        return try await complete(textAIPrompt(fragment: fragment, text: text, emojify: emojify))
    }

    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String {
        return try await complete(textAIPrompt(fragment: preset.promptFragment, text: text, emojify: emojify))
    }

    private func complete(_ prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey }

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)",  forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model":    model,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONDecoder().decode(Response.self, from: data)
        return json.choices.first?.message.content ?? ""
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
