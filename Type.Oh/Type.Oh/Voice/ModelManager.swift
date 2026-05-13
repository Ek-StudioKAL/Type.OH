import Foundation
import Observation
import WhisperKit

extension Notification.Name {
    static let whisperModelDownloaded = Notification.Name("typeoh.whisperModelDownloaded")
}

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
    private(set) var downloadingModelID: String?
    private(set) var lastError: String?
    private(set) var loadedModelID: String?

    var isDownloading: Bool { downloadingModelID != nil }

    func markLoaded(_ modelID: String) {
        loadedModelID = modelID
    }

    func markUnloaded() {
        loadedModelID = nil
    }

    /// Resident memory of this process, in MB. Used to display approximate RAM usage in Settings.
    static var processResidentMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    // Exact folder URLs returned by WhisperKit.download(), keyed by modelID.
    // WhisperKit's HubApi appends repo.type.rawValue ("models") + repo.id + variantPath,
    // so the real path differs from a naive manual construction. We capture and persist it.
    private var _downloadedPaths: [String: URL] = [:]

    private static let defaultsKey = "whisper.downloadedPaths"

    let modelsDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Type.OH/models")
    }()

    private init() {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        if let dict = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] {
            _downloadedPaths = dict.compactMapValues { URL(string: $0) }
        }
    }

    /// The exact folder URL for a downloaded model, or nil if not yet downloaded.
    func modelFolderURL(for modelID: String) -> URL? {
        _downloadedPaths[modelID]
    }

    func isDownloaded(_ modelID: String) -> Bool {
        guard let folder = modelFolderURL(for: modelID) else { return false }
        return (try? FileManager.default
            .contentsOfDirectory(atPath: folder.path)
            .isEmpty == false) ?? false
    }

    func download(_ modelID: String) async throws {
        downloadingModelID = modelID
        downloadProgress = 0
        lastError = nil
        defer { downloadingModelID = nil; downloadProgress = 0 }
        do {
            let folderURL = try await WhisperKit.download(
                variant: modelID,
                downloadBase: modelsDirectory,
                progressCallback: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = fraction
                    }
                }
            )
            // Persist the exact returned path so isDownloaded() and loadModel() use the right folder.
            _downloadedPaths[modelID] = folderURL
            var stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
            stored[modelID] = folderURL.absoluteString
            UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: .whisperModelDownloaded, object: modelID)
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }
}
