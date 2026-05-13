import Foundation
import Observation

struct HotkeyConfig: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    // Extended F-keys F13 (105), F14 (107), F15 (113) make great global
    // shortcuts — almost no app uses them and they're chord-free.
    static let defaultVoice      = HotkeyConfig(keyCode: 105, modifiers: 0) // F13
    static let defaultEditor     = HotkeyConfig(keyCode: 107, modifiers: 0) // F14
    static let defaultScratchpad = HotkeyConfig(keyCode: 113, modifiers: 0) // F15
}

struct CustomStylePreset: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var emoji: String
    var promptFragment: String

    /// Sidebar can hold up to this many custom presets (alongside the 5
    /// built-ins). Enforced at the UI/save layer.
    static let maxCount = 8
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

/// Which engine handles the Translate action across the app.
enum TranslationProviderID: String, Codable, CaseIterable, Sendable {
    /// Native macOS TranslationSession — no LLM, downloadable language
    /// packs, runs fully offline.
    case nativeOS    = "nativeOS"
    /// Apple FoundationModels (on-device LLM). Higher quality, slower.
    case localLLM    = "localLLM"
    /// Whatever cloud provider (`SettingsStore.activeProvider`) the user
    /// has configured.
    case apiLLM      = "apiLLM"

    var displayName: String {
        switch self {
        case .nativeOS: "Native macOS (offline)"
        case .localLLM: "Apple On-Device LLM"
        case .apiLLM:   "Cloud Provider (API key)"
        }
    }

    var detail: String {
        switch self {
        case .nativeOS: "Uses macOS Translation. Fast, offline, limited languages, no AI rewrite — but may sound stiffer."
        case .localLLM: "Uses Apple's on-device language model. Free, private, slower than Native OS."
        case .apiLLM:   "Uses your selected cloud provider — best quality, costs API credits."
        }
    }
}

@Observable
@MainActor
final class SettingsStore {
    var whisperModel:    String        = "openai_whisper-base"
    var voiceHotkey:     HotkeyConfig  = .defaultVoice
    var editorHotkey:    HotkeyConfig  = .defaultEditor
    var scratchpadHotkey: HotkeyConfig? = .defaultScratchpad
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
    var customStylePresets: [CustomStylePreset] = []
    // Translation framework — picks which engine handles the Translate flow.
    // `nil` means "ask me on first use" (auto-open Settings → Translation).
    var translationProvider: TranslationProviderID? = nil
    /// When true (the default), Whisper stays loaded in memory between dictations
    /// so subsequent ⌃F13 presses are instant. Turn off to free ~200 MB-3 GB
    /// while idle, at the cost of a 1-5 s warm-up on next use.
    var whisperKeepLoaded: Bool = true

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
        var customStylePresets: [CustomStylePreset]?
        var translationProvider: TranslationProviderID?
        var whisperKeepLoaded: Bool?

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
            customStylePresets = s.customStylePresets
            translationProvider = s.translationProvider
            whisperKeepLoaded = s.whisperKeepLoaded
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
            s.customStylePresets = customStylePresets ?? []
            s.translationProvider = translationProvider
            s.whisperKeepLoaded = whisperKeepLoaded ?? true
        }
    }
}
