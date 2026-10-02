import Combine
import Foundation

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

/// Text-AI providers. The Apple on-device provider (FoundationModels / Apple
/// Intelligence) only exists when the SDK has FoundationModels — the Xcode
/// build for macOS 26 on Apple Silicon. The macOS 13 / Intel SwiftPM build
/// has the cloud providers only.
enum ProviderID: String, Codable, CaseIterable, Sendable {
    #if canImport(FoundationModels)
    case appleOnDevice = "apple"
    #endif
    case anthropic     = "anthropic"
    case openAI        = "openai"
    case google        = "google"

    /// Provider used when settings are fresh or reference a provider this
    /// build doesn't have (e.g. "apple" read by the Intel build).
    static var fallback: ProviderID {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return .appleOnDevice }
        #endif
        return .anthropic
    }

    var displayName: String {
        switch self {
        #if canImport(FoundationModels)
        case .appleOnDevice: "Apple (On-Device)"
        #endif
        case .anthropic:     "Anthropic Claude"
        case .openAI:        "OpenAI GPT"
        case .google:        "Google Gemini"
        }
    }

    var requiresAPIKey: Bool {
        #if canImport(FoundationModels)
        if self == .appleOnDevice { return false }
        #endif
        return true
    }

    /// Tolerant decoding so a settings.json written by a build with a
    /// different provider list doesn't invalidate every other setting.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProviderID(rawValue: raw) ?? .fallback
    }
}

/// Which engine handles the Translate action across the app.
enum TranslationProviderID: String, Codable, CaseIterable, Sendable {
    /// Google Translate's free public endpoint — no key, no account. The
    /// main engine (see `GoogleTranslateService`).
    case googleTranslate = "googleTranslate"
    /// Native macOS TranslationSession — no LLM, downloadable language
    /// packs, runs fully offline. Needs the Translation framework (macOS 15+).
    case nativeOS    = "nativeOS"
    /// Whatever cloud provider (`SettingsStore.activeProvider`) the user
    /// has configured.
    case apiLLM      = "apiLLM"

    /// Engines that can actually run on this macOS. Native translation is
    /// hidden on releases without the Translation framework.
    static var availableCases: [TranslationProviderID] {
        allCases.filter { $0 != .nativeOS || NativeTranslationSupport.isAvailable }
    }

    /// Engine used when the user hasn't chosen one.
    static let preferred: TranslationProviderID = .googleTranslate

    var displayName: String {
        switch self {
        case .googleTranslate: "Google Translate (free)"
        case .nativeOS: "Native macOS (offline)"
        case .apiLLM:   "Cloud Provider (API key)"
        }
    }

    var detail: String {
        switch self {
        case .googleTranslate: "Uses Google Translate's public web service. Free, no key, 100+ languages, needs internet. Unofficial: heavy use can be rate-limited for a while."
        case .nativeOS: "Uses macOS Translation. Fast, offline, limited languages, no AI rewrite — but may sound stiffer."
        case .apiLLM:   "Uses your selected cloud provider — best quality, costs API credits."
        }
    }

    /// "localLLM" (the removed Apple on-device LLM engine) and any unknown
    /// value decode as the default engine instead of failing the whole
    /// settings file.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TranslationProviderID(rawValue: raw) ?? .preferred
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var whisperModel:    String        = "openai_whisper-base"
    @Published var whisperInputLanguage: String?  = nil     // nil = auto-detect
    @Published var whisperOutputLanguage: String? = nil     // nil = keep spoken language
    @Published var voiceHotkey:     HotkeyConfig  = .defaultVoice
    @Published var editorHotkey:    HotkeyConfig  = .defaultEditor
    @Published var scratchpadHotkey: HotkeyConfig? = .defaultScratchpad
    @Published var activeProvider:  ProviderID    = .fallback
    @Published var sourceLanguage:  String?       = nil     // nil = auto-detect
    @Published var targetLanguage:  String        = "en"
    @Published var emojify:         Bool          = false
    @Published var spellingAssistanceEnabled: Bool = true
    @Published var grammarAssistanceEnabled: Bool = true
    @Published var textReplacementEnabled: Bool   = true
    @Published var launchAtLogin:   Bool          = false
    @Published var showInDock:      Bool          = true
    @Published var hasCompletedOnboarding: Bool   = false
    @Published var customStylePresets: [CustomStylePreset] = []
    // Translation framework — picks which engine handles the Translate flow.
    // `nil` means "ask me on first use" (auto-open Settings → Translation).
    @Published var translationProvider: TranslationProviderID? = nil
    /// When true (the default), Whisper stays loaded in memory between dictations
    /// so subsequent dictation hotkey presses are instant. Turn off to free ~200 MB-3 GB
    /// while idle, at the cost of a 1-5 s warm-up on next use.
    @Published var whisperKeepLoaded: Bool = true

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
        var whisperInputLanguage: String?
        var whisperOutputLanguage: String?
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

        @MainActor
        init(_ s: SettingsStore) {
            whisperModel   = s.whisperModel
            whisperInputLanguage = s.whisperInputLanguage
            whisperOutputLanguage = s.whisperOutputLanguage
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

        @MainActor
        func apply(to s: SettingsStore) {
            s.whisperModel   = whisperModel
            s.whisperInputLanguage = whisperInputLanguage
            s.whisperOutputLanguage = whisperOutputLanguage
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
            // Native macOS translation can't run without the Translation framework;
            // fall back to the default engine rather than failing every translate.
            if translationProvider == .nativeOS, !NativeTranslationSupport.isAvailable {
                s.translationProvider = .preferred
            } else {
                s.translationProvider = translationProvider
            }
            s.whisperKeepLoaded = whisperKeepLoaded ?? true
        }
    }
}
