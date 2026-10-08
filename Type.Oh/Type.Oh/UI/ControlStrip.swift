import AppKit
import IOKit

/// What the Type.OH button in the Touch Bar's Control Strip does
/// (Settings → General → Touch Bar).
enum ControlStripAction: String, Codable, CaseIterable, Sendable {
    case off, dictate, retype, lazypad

    static let `default`: ControlStripAction = .retype

    var title: String {
        switch self {
        case .off: "None"
        case .dictate: "Dictate"
        case .retype: "ReType"
        case .lazypad: "LazyPad"
        }
    }

    var icon: AppIcon? {
        switch self {
        case .off: nil
        case .dictate: .dictate
        case .retype: .aiEditor
        case .lazypad: .lazypad
        }
    }
}

/// One Type.OH button in the Touch Bar's Control Strip, shown whatever app is
/// in front (MacBook Pro with a Touch Bar). It appears in the collapsed
/// Control Strip only, and macOS doesn't list it under Customize Control
/// Strip.
///
/// The button lives in a helper process, `Contents/Helpers/TypeOhStrip.app`
/// (`ControlStripHelper/main.swift`, built by build-app.sh): a process that
/// adds a Control Strip button stops showing its own windows' Touch Bars, so
/// LazyPad's and ReType's buttons would vanish. Tapping it opens
/// `typeoh://<action>` in the background, like the Quick Actions. Without the
/// helper (the Xcode build doesn't bundle it) there's just no button.
@MainActor
final class ControlStrip {
    private var action: ControlStripAction = .off
    private var helper: NSRunningApplication?
    private var helperStarted = Date.distantPast

    init() {
        // The helper exits when the Control Strip restarts (it forgets the
        // button); start a new one unless it died right after launching.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                guard let self, let ended, ended.processIdentifier == self.helper?.processIdentifier,
                      Date().timeIntervalSince(self.helperStarted) > 5 else { return }
                self.helper = nil
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if self.helper == nil { self.startHelper() }
            }
        }
    }

    /// Shows the button for `action`, or removes it for `.off`.
    func show(_ action: ControlStripAction) {
        guard action != self.action else { return }
        hide()
        self.action = action
        startHelper()
    }

    /// Removes the button (on quit, or before switching actions).
    func hide() {
        action = .off
        let helper = self.helper
        self.helper = nil
        helper?.terminate()
    }

    /// Launched through Launch Services rather than as a child process, so
    /// macOS doesn't attribute the helper to Type.OH.
    private func startHelper() {
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/TypeOhStrip.app")
        guard let icon = action.icon, Self.hasTouchBar,
              FileManager.default.fileExists(atPath: helperURL.path),
              let iconURL = Bundle.main.url(forResource: "icon-\(icon.rawValue)", withExtension: "pdf") else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [action.rawValue, iconURL.path, action.title, String(ProcessInfo.processInfo.processIdentifier)]
        let launchedAction = action
        helperStarted = Date()
        NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration) { app, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    NSLog("[Type.OH] Control Strip helper failed to start: %@", error.localizedDescription)
                    return
                }
                // The setting changed while it was launching.
                guard self.action == launchedAction, self.helper == nil else {
                    app?.terminate()
                    return
                }
                self.helper = app
            }
        }
    }

    /// True on a Mac with a Touch Bar: TouchBarServer, which only runs there,
    /// publishes a virtual HID device named "TouchBarUserDevice".
    static let hasTouchBar: Bool = {
        guard let matching = IOServiceMatching("IOHIDUserDevice") as NSMutableDictionary? else { return false }
        matching["IOPropertyMatch"] = ["Product": "TouchBarUserDevice"]
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return false }
        IOObjectRelease(service)
        return true
    }()
}
