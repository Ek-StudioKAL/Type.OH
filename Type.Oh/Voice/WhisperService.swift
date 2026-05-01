import Foundation

// Stub — add the WhisperKit Swift Package (https://github.com/argmaxinc/WhisperKit),
// then replace the TODO stubs with the real implementation.

actor WhisperService {
    // TODO: private var whisperKit: WhisperKit?

    private var loadedModel: String?

    func loadModel(_ name: String) async throws {
        // TODO: whisperKit = try await WhisperKit(model: name, modelFolder: modelsDirectory.path)
        loadedModel = name
    }

    func transcribe(audio: [Float]) async throws -> String {
        guard loadedModel != nil else { throw WhisperError.modelNotLoaded }
        // TODO: let results = try await whisperKit!.transcribe(audioArray: audio)
        //       return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return "[WhisperKit not yet integrated — add the SPM package first]"
    }

    enum WhisperError: Error, LocalizedError {
        case modelNotLoaded

        var errorDescription: String? { "No Whisper model loaded. Download one in Settings." }
    }
}
