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

    func transcribe(audio: [Float]) async throws -> String {
        guard let kit = whisperKit else { throw WhisperError.modelNotLoaded }
        let results = try await kit.transcribe(audioArray: audio)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    enum WhisperError: Error, LocalizedError {
        case modelNotLoaded
        case modelNotDownloaded(String)
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded:
                "No Whisper model loaded. Download one in Settings → Models."
            case .modelNotDownloaded(let name):
                "Whisper model '\(name)' isn't downloaded yet. Open Settings → Models to download it."
            }
        }
    }
}
