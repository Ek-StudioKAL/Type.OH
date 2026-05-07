import Foundation

@MainActor
final class ScratchpadStore {
    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("Type.OH", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("scratchpad.txt")
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func scheduleSave(_ text: String) {
        saveTask?.cancel()
        saveTask = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    func saveNow(_ text: String) {
        saveTask?.cancel()
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
