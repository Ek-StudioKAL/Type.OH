import Foundation

@MainActor
final class ScratchpadStore {
    private let fileURL: URL
    private let debounce: DispatchTimeInterval = .milliseconds(400)

    /// Single reusable timer. Each call to `scheduleSave` resets the deadline
    /// rather than spawning a new Task — Task-per-keystroke churned the
    /// scheduler on long edits.
    private var saveTimer: DispatchSourceTimer?
    private var pendingText: String = ""

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        let directory = directoryURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Type.OH", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("scratchpad.txt")
    }

    deinit {
        saveTimer?.cancel()
    }

    func load() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func scheduleSave(_ text: String) {
        pendingText = text

        if let timer = saveTimer {
            // Reset the existing timer's deadline.
            timer.schedule(deadline: .now() + debounce)
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + debounce)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let textToWrite = self.pendingText
            self.saveTimer?.cancel()
            self.saveTimer = nil
            try? textToWrite.write(to: self.fileURL, atomically: true, encoding: .utf8)
        }
        saveTimer = timer
        timer.resume()
    }

    func saveNow(_ text: String) {
        saveTimer?.cancel()
        saveTimer = nil
        pendingText = text
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
