import Foundation
import Observation

struct WhisperModelInfo: Identifiable, Sendable {
    let id: String
    let displayName: String
    let sizeDescription: String
}

@Observable
@MainActor
final class ModelManager {
    static let shared = ModelManager()

    let catalogue: [WhisperModelInfo] = [
        WhisperModelInfo(id: "openai_whisper-tiny",    displayName: "tiny",    sizeDescription: "~75 MB"),
        WhisperModelInfo(id: "openai_whisper-base",    displayName: "base",    sizeDescription: "~142 MB"),
        WhisperModelInfo(id: "openai_whisper-small",   displayName: "small",   sizeDescription: "~466 MB"),
        WhisperModelInfo(id: "openai_whisper-medium",  displayName: "medium",  sizeDescription: "~1.5 GB"),
        WhisperModelInfo(id: "openai_whisper-large-v3",displayName: "large-v3",sizeDescription: "~3 GB"),
    ]

    private(set) var downloadProgress: Double = 0
    private(set) var isDownloading = false

    let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Type.OH/models")
    }()

    private init() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    func isDownloaded(_ modelID: String) -> Bool {
        FileManager.default.fileExists(atPath: modelsDirectory.appendingPathComponent(modelID).path)
    }

    func download(_ modelID: String) async throws {
        // TODO: replace with WhisperKit.download(variant:downloadBase:)
        isDownloading = true
        defer { isDownloading = false; downloadProgress = 0 }
        for i in 1...10 {
            try await Task.sleep(for: .milliseconds(200))
            downloadProgress = Double(i) / 10.0
        }
    }
}
