import Foundation
import WhisperKit

actor WhisperService {
    private var whisperKit: WhisperKit?
    private var loadedModel: String?
    /// The load in progress, if any. A first Core ML load of a large model
    /// can take a minute; callers that ask for the same model while it runs
    /// (launch warm-up, then a dictation) wait on it instead of starting a
    /// second load.
    private var inFlightLoad: (id: UUID, name: String, task: Task<Void, Error>)?

    /// Snapshot of currently-loaded model name. Nil when nothing is loaded.
    var currentlyLoadedModel: String? { loadedModel }

    /// Load (or reload) the model from the exact folder URL returned by ModelManager.download().
    func loadModel(name: String, at folderURL: URL) async throws {
        if loadedModel == name, whisperKit != nil { return }
        if let inFlightLoad, inFlightLoad.name == name {
            try await inFlightLoad.task.value
            return
        }

        let config = WhisperKitConfig(
            model: name,
            modelFolder: folderURL.path,
            computeOptions: Self.computeOptions,
            download: false
        )
        let id = UUID()
        let task = Task {
            defer { if self.inFlightLoad?.id == id { self.inFlightLoad = nil } }
            let kit = try await WhisperKit(config)
            // `unload()` during the load cancels it; don't install the model.
            try Task.checkCancellation()
            self.whisperKit = kit
            self.loadedModel = name
            await ModelManager.shared.markLoaded(name)
        }
        inFlightLoad = (id, name, task)
        try await task.value
    }

    /// Intel Macs have no Neural Engine, so WhisperKit's Apple Silicon defaults
    /// (`cpuAndNeuralEngine`) don't apply. Measured on a 2017 MacBook Pro
    /// (Radeon Pro, macOS 13.7): the text decoder returns garbage on the GPU,
    /// and Core ML's pure-CPU path crashes inside the mel model, so mel and
    /// encoder run on the GPU and the decoder on the CPU. That combination
    /// transcribes a 5 s clip with `base` in about 4 s.
    private static var computeOptions: ModelComputeOptions? {
        #if arch(x86_64)
        return ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndGPU,
            textDecoderCompute: .cpuOnly,
            prefillCompute: .cpuOnly
        )
        #else
        return nil
        #endif
    }

    /// Ensure the model is loaded before transcription; loads on-demand if needed.
    func ensureLoaded(name: String, at folderURL: URL) async throws {
        guard loadedModel != name || whisperKit == nil else { return }
        try await loadModel(name: name, at: folderURL)
    }

    /// Drop the WhisperKit instance. Frees model RAM (200 MB – 3 GB depending on
    /// variant). Next dictation pays a 1-5 s warm-up to reload.
    func unload() async {
        inFlightLoad?.task.cancel()
        inFlightLoad = nil
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
