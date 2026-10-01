import Foundation

/// Free Google Translate engine — the public endpoints behind Google's own
/// clients, no API key or account. Two backends are tried in order:
///
/// 1. `translate_a/t?client=dict-chrome-ex` (Chrome's translate extension):
///    `[["translated", "detected-source"]]`, or `["translated"]` when the
///    source language is given. Keeps paragraph breaks, takes long texts.
/// 2. `translate_a/single?client=gtx` (the translate.google.com web UI):
///    `[[["translated", "original", …], …], null, "detected-source", …]`.
///
/// Both are unofficial: Google may rate-limit bursts (HTTP 429 / a "Sorry…"
/// page) per IP for a while, so a failure on one backend falls through to the
/// other and the final error tells the user to wait or switch engines.
struct GoogleTranslateService: Sendable {
    static let shared = GoogleTranslateService()

    private let session: URLSession
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum Failure: LocalizedError {
        case rateLimited
        case http(Int)
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .rateLimited:
                "Google Translate is rate-limiting free requests from this Mac right now. Wait a few minutes, or switch the engine to Cloud Provider in Settings → Translation."
            case .http(let code):
                "Google Translate returned HTTP \(code)."
            case .unexpectedResponse:
                "Google Translate returned a response Type.OH couldn't read."
            }
        }
    }

    struct Result: Sendable {
        let text: String
        /// Code Google detected for the source, e.g. "en" (nil when the
        /// source language was given explicitly).
        let detectedSourceLanguage: String?
    }

    enum Backend: CaseIterable, Sendable {
        case chromeExtension
        case webUI

        var url: URL {
            switch self {
            case .chromeExtension: URL(string: "https://translate.googleapis.com/translate_a/t?client=dict-chrome-ex")!
            case .webUI:           URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&ie=UTF-8&oe=UTF-8")!
            }
        }
    }

    /// Translate `text` into `target`. `source == nil` means auto-detect.
    func translate(text: String, source: Locale.Language?, target: Locale.Language) async throws -> Result {
        var lastError: Error = Failure.unexpectedResponse
        for backend in Backend.allCases {
            do {
                return try await translate(text: text, source: source, target: target, via: backend)
            } catch {
                lastError = error
                NSLog("[Type.OH] Google Translate %@ failed: %@", String(describing: backend), error.localizedDescription)
            }
        }
        throw lastError
    }

    func translate(text: String, source: Locale.Language?, target: Locale.Language, via backend: Backend) async throws -> Result {
        var components = URLComponents(url: backend.url, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "sl", value: source.map(Self.googleCode) ?? "auto"),
            URLQueryItem(name: "tl", value: Self.googleCode(for: target)),
        ]
        var request = URLRequest(url: components.url!)
        // POST keeps long texts out of the URL (the GET form caps around 2 kB).
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded;charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data("q=\(Self.formEncode(text))".utf8)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        switch status {
        case 200: break
        case 429, 503: throw Failure.rateLimited
        default: throw Failure.http(status)
        }
        switch backend {
        case .chromeExtension: return try Self.parseChromeExtension(data)
        case .webUI:           return try Self.parse(data)
        }
    }

    // MARK: - Responses

    /// `[["translated", "detected"]]` (auto source) or `["translated"]`
    /// (explicit source). Several `q` values would give several items; we send one.
    static func parseChromeExtension(_ data: Data) throws -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let first = root.first else {
            throw Failure.unexpectedResponse
        }
        if let text = first as? String {
            return Result(text: text, detectedSourceLanguage: nil)
        }
        if let pair = first as? [Any], let text = pair.first as? String {
            return Result(text: text, detectedSourceLanguage: pair.count > 1 ? pair[1] as? String : nil)
        }
        throw Failure.unexpectedResponse
    }

    /// Web-UI shape: `[[["translated", "original", …], …], null, "detected-lang", …]`
    static func parse(_ data: Data) throws -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let sentences = root.first as? [Any] else {
            throw Failure.unexpectedResponse
        }
        let text = sentences
            .compactMap { ($0 as? [Any])?.first as? String }
            .joined()
        let detected = root.count > 2 ? root[2] as? String : nil
        return Result(text: text, detectedSourceLanguage: detected)
    }

    // MARK: - Language codes

    /// Google uses its own spellings for a few languages that `Locale.Language`
    /// identifies differently.
    static func googleCode(for language: Locale.Language) -> String {
        let id = language.minimalIdentifier
        switch id {
        case "zh", "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "nb", "nn": return "no"
        case "fil": return "tl"
        case "he": return "iw"
        case "jv": return "jw"
        case "mni-Mtei": return "mni-Mtei"
        default: break
        }
        // Google wants bare language codes except for the region/script cases above.
        return language.languageCode?.identifier ?? id
    }

    /// `application/x-www-form-urlencoded` encoding of a value.
    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? s
    }
}
