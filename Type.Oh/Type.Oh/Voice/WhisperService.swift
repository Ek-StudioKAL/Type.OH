import Foundation
import WhisperKit

actor WhisperService {
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Type.OH/models")
    }

    private func modelFolder(for name: String) -> URL {
        modelsDirectory
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(name)
    }

    func loadModel(_ name: String) async throws {
        if loadedModel == name, whisperKit != nil { return }
        let folder = modelFolder(for: name)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              !entries.isEmpty else {
            throw WhisperError.modelNotDownloaded(name)
        }
        let config = WhisperKitConfig(model: name, modelFolder: folder.path, download: false)
        whisperKit = try await WhisperKit(config)
        loadedModel = name
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
