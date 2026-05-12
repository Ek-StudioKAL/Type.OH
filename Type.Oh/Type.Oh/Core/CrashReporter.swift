import Foundation
import Darwin

/// Lightweight crash dumper. Captures uncaught Obj-C exceptions and POSIX
/// signals (SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE) and flushes a
/// timestamped trace to ~/Library/Logs/Type.OH/ so we have something to read
/// next launch instead of a silent quit. The default termination still
/// happens — this is best-effort, not recovery.
enum CrashReporter {
    private static let logDirectoryName = "Type.OH"

    static func install() {
        ensureLogDirectoryExists()
        rotateOldLogs()

        NSSetUncaughtExceptionHandler { exception in
            CrashReporter.write(
                kind: "uncaught-exception",
                summary: "\(exception.name.rawValue): \(exception.reason ?? "no reason")",
                symbols: exception.callStackSymbols
            )
        }

        let signals: [Int32] = [SIGABRT, SIGSEGV, SIGILL, SIGBUS, SIGFPE, SIGPIPE]
        for signum in signals {
            signal(signum) { sig in
                CrashReporter.write(
                    kind: "signal",
                    summary: "signal \(sig) (\(CrashReporter.name(for: sig)))",
                    symbols: Thread.callStackSymbols
                )
                // Reset to default and re-raise so the OS still produces a
                // standard crash report and the app actually terminates.
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
    }

    // MARK: - Paths

    static var logDirectoryURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(logDirectoryName, isDirectory: true)
    }

    private static func ensureLogDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: logDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    /// Keep at most 10 most recent crash logs. Anything older gets cleaned up.
    private static func rotateOldLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: logDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let crashLogs = files
            .filter { $0.lastPathComponent.hasPrefix("crash-") }
            .sorted {
                let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
        for stale in crashLogs.dropFirst(10) {
            try? fm.removeItem(at: stale)
        }
    }

    // MARK: - Write

    private static func write(kind: String, summary: String, symbols: [String]) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let filename = "crash-\(ts.replacingOccurrences(of: ":", with: "-")).log"
        let url = logDirectoryURL.appendingPathComponent(filename)

        var body = """
        Type.OH crash report
        Date: \(ts)
        Kind: \(kind)
        Summary: \(summary)
        Bundle: \(Bundle.main.bundleIdentifier ?? "(unknown)")
        Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        OS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        Stack:
        """
        for frame in symbols {
            body += "\n  \(frame)"
        }
        body += "\n"

        // Use POSIX write — Foundation may not be safe inside a signal handler
        // but in practice we've already lost the world; best effort.
        try? body.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func name(for signum: Int32) -> String {
        switch signum {
        case SIGABRT: return "SIGABRT"
        case SIGSEGV: return "SIGSEGV"
        case SIGILL:  return "SIGILL"
        case SIGBUS:  return "SIGBUS"
        case SIGFPE:  return "SIGFPE"
        case SIGPIPE: return "SIGPIPE"
        default:      return "unknown"
        }
    }
}
