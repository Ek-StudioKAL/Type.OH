import Foundation
import Observation

struct HotkeyConfig: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    // ⌃F13 — controlKey = 4096, F13 keyCode = 105
    static let defaultVoice  = HotkeyConfig(keyCode: 105, modifiers: 4096)
    // ⌥F13 — optionKey  = 2048, F13 keyCode = 105
    static let defaultEditor = HotkeyConfig(keyCode: 105, modifiers: 2048)
}

enum ProviderID: String, Codable, CaseIterable, Sendable {
    case appleOnDevice = "apple"
    case anthropic     = "anthropic"
    case openAI        = "openai"
    case google        = "google"

    var displayName: String {
        switch self {
        case .appleOnDevice: "Apple (On-Device)"
        case .anthropic:     "Anthropic Claude"
        case .openAI:        "OpenAI GPT"
        case .google:        "Google Gemini"
        }
    }

    var requiresAPIKey: Bool { self != .appleOnDevice }
}

@Observable
@MainActor
final class SettingsStore {
    var whisperModel:    String        = "openai_whisper-base"
    var voiceHotkey:     HotkeyConfig  = .defaultVoice
    var editorHotkey:    HotkeyConfig  = .defaultEditor
    var scratchpadHotkey: HotkeyConfig? = nil
    var activeProvider:  ProviderID    = .appleOnDevice
    var sourceLanguage:  String?       = nil     // nil = auto-detect
    var targetLanguage:  String        = "en"
    var emojify:         Bool          = false
    var spellingAssistanceEnabled: Bool = true
    var grammarAssistanceEnabled: Bool = true
    var textReplacementEnabled: Bool   = true
    var launchAtLogin:   Bool          = false
    var showInDock:      Bool          = true
    var hasCompletedOnboarding: Bool   = false

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Type.OH")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        load()
    }

    /// Test-only initializer. Skips load() so property defaults are used as-is.
    init(settingsURL: URL) {
        fileURL = settingsURL
    }

    func save() {
        try? JSONEncoder().encode(Snapshot(self)).write(to: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        snap.apply(to: self)
    }
}

private extension SettingsStore {
    struct Snapshot: Codable {
        var whisperModel, targetLanguage: String
        var sourceLanguage: String?
        var voiceHotkey, editorHotkey: HotkeyConfig
        var scratchpadHotkey: HotkeyConfig?
        var activeProvider: ProviderID
        var emojify, launchAtLogin: Bool
        var spellingAssistanceEnabled: Bool?
        var grammarAssistanceEnabled: Bool?
        var textReplacementEnabled: Bool?
        var smartTextEnabled: Bool?
        var showInDock: Bool?
        var hasCompletedOnboarding: Bool?

        init(_ s: SettingsStore) {
            whisperModel   = s.whisperModel
            voiceHotkey    = s.voiceHotkey
            editorHotkey   = s.editorHotkey
            scratchpadHotkey = s.scratchpadHotkey
            activeProvider = s.activeProvider
            sourceLanguage = s.sourceLanguage
            targetLanguage = s.targetLanguage
            emojify        = s.emojify
            spellingAssistanceEnabled = s.spellingAssistanceEnabled
            grammarAssistanceEnabled = s.grammarAssistanceEnabled
            textReplacementEnabled = s.textReplacementEnabled
            smartTextEnabled = nil
            launchAtLogin  = s.launchAtLogin
            showInDock     = s.showInDock
            hasCompletedOnboarding = s.hasCompletedOnboarding
        }

        func apply(to s: SettingsStore) {
            s.whisperModel   = whisperModel
            s.voiceHotkey    = voiceHotkey
            s.editorHotkey   = editorHotkey
            s.scratchpadHotkey = scratchpadHotkey
            s.activeProvider = activeProvider
            s.sourceLanguage = sourceLanguage
            s.targetLanguage = targetLanguage
            s.emojify        = emojify
            if let spellingAssistanceEnabled, let grammarAssistanceEnabled, let textReplacementEnabled {
                s.spellingAssistanceEnabled = spellingAssistanceEnabled
                s.grammarAssistanceEnabled = grammarAssistanceEnabled
                s.textReplacementEnabled = textReplacementEnabled
            } else {
                let legacyValue = smartTextEnabled ?? true
                s.spellingAssistanceEnabled = legacyValue
                s.grammarAssistanceEnabled = legacyValue
                s.textReplacementEnabled = legacyValue
            }
            s.launchAtLogin  = launchAtLogin
            s.showInDock     = showInDock ?? true
            s.hasCompletedOnboarding = hasCompletedOnboarding ?? false
        }
    }
}
