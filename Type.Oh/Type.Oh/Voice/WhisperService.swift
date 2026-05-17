import Foundation
import WhisperKit

actor WhisperService {
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    /// Snapshot of currently-loaded model name. Nil when nothing is loaded.
    var currentlyLoadedModel: String? { loadedModel }

    /// Load (or reload) the model from the exact folder URL returned by ModelManager.download().
    func loadModel(name: String, at folderURL: URL) async throws {
        if loadedModel == name, whisperKit != nil { return }
        let config = WhisperKitConfig(model: name, modelFolder: folderURL.path, download: false)
        whisperKit = try await WhisperKit(config)
        loadedModel = name
        await ModelManager.shared.markLoaded(name)
    }

    /// Ensure the model is loaded before transcription; loads on-demand if needed.
    func ensureLoaded(name: String, at folderURL: URL) async throws {
        guard loadedModel != name || whisperKit == nil else { return }
        try await loadModel(name: name, at: folderURL)
    }

    /// Drop the WhisperKit instance. Frees model RAM (200 MB – 3 GB depending on
    /// variant). Next dictation pays a 1-5 s warm-up to reload.
    func unload() async {
        whisperKit = nil
        loadedModel = nil
        await ModelManager.shared.markUnloaded()
    }

    func transcribe(audio: [Float], inputLanguage: String?) async throws -> String {
        guard let kit = whisperKit else { throw WhisperError.modelNotLoaded }
        let trimmedLanguage = inputLanguage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = trimmedLanguage?.isEmpty == true ? nil : trimmedLanguage
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            detectLanguage: language == nil,
            withoutTimestamps: true
        )
        let results = try await kit.transcribe(audioArray: audio, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    enum WhisperError: Error, LocalizedError {
        case modelNotLoaded
        case modelNotDownloaded(String)
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                "No Whisper model loaded. Download one in Settings → Whisper."
            case .modelNotDownloaded(let name):
                "Whisper model '\(name)' isn't downloaded yet. Open Settings → Whisper to download it."
            }
        }
    }
}
