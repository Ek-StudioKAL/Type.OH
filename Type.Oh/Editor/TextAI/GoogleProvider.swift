import Foundation

struct GoogleProvider: TextAIProvider {
    let apiKey: String
    private let model = "gemini-1.5-flash"

    func fix(text: String, emojify: Bool) async throws -> String {
        let fragment = "Fix all typos, grammar mistakes, and punctuation errors in the following text. Preserve the original meaning and tone exactly."
        return try await complete(textAIPrompt(fragment: fragment, text: text, emojify: emojify))
    }

    func applyStyle(_ preset: StylePreset, to text: String, emojify: Bool) async throws -> String {
        return try await complete(textAIPrompt(fragment: preset.promptFragment, text: text, emojify: emojify))
    }

    private func complete(_ prompt: String) async throws -> String {
        guard !apiKey.isEmpty else { throw ProviderError.missingAPIKey }

        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]]
        ])

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONDecoder().decode(Response.self, from: data)
        return json.candidates.first?.content.parts.first?.text ?? ""
    }

    private struct Response: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String }
                let parts: [Part]
            }
            let content: Content
        }
        let candidates: [Candidate]
    }
}
