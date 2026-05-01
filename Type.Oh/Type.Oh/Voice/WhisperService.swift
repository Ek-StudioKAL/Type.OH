import Foundation
import WhisperKit

actor WhisperService {
    private var whisperKit: WhisperKit?

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Type.OH/models")
    }

    func loadModel(_ name: String) async throws {
        let config = WhisperKitConfig(model: name, modelFolder: modelsDirectory.path)
        whisperKit = try await WhisperKit(config)
    }

    func transcribe(audio: [Float]) async throws -> String {
        guard let kit = whisperKit else { throw WhisperError.modelNotLoaded }
        let results = try await kit.transcribe(audioArray: audio)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    enum WhisperError: Error, LocalizedError {
        case modelNotLoaded
        var errorDescription: String? { "No Whisper model loaded. Download one in Settings." }
    }
}
