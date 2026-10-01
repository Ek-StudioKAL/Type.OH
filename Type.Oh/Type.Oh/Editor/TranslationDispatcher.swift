import Foundation

/// Routes the Translate action to whichever engine the user picked in
/// Settings → Translation. With no explicit choice the default engine
/// (`TranslationProviderID.preferred`, Google Translate) is used, so
/// translation works out of the box without any setup.
@MainActor
enum TranslationDispatcher {

    enum Failure: LocalizedError {
        case engineUnselected
        case nativeMissingLanguagePack
        case nativeUnavailable
        case noActiveProvider

        var errorDescription: String? {
            switch self {
            case .engineUnselected:
                "Pick a translation engine in Settings → Translation."
            case .nativeMissingLanguagePack:
                "macOS doesn't have a language pack for this pair. Pick the language from a translate panel to trigger the download prompt."
            case .nativeUnavailable:
                "Native macOS translation needs macOS 15 or later. Switch the engine to Cloud Provider in Settings → Translation."
            case .noActiveProvider:
                "No active cloud provider — set one in Settings → Providers, or switch the translation engine."
            }
        }
    }

    static func translate(
        text: String,
        source: Locale.Language?,
        target: Locale.Language,
        using settings: SettingsStore
    ) async throws -> String {
        let engine = settings.translationProvider ?? .preferred

        switch engine {
        case .googleTranslate:
            return try await GoogleTranslateService.shared.translate(
                text: text,
                source: source,
                target: target
            ).text

        case .nativeOS:
            guard NativeTranslationSupport.isAvailable else {
                throw Failure.nativeUnavailable
            }
            return try await NativeTranslationCoordinator.shared.translate(
                text: text,
                source: source,
                target: target
            )

        case .apiLLM:
            let provider = ProviderRegistry.provider(for: settings.activeProvider)
            return try await provider.translate(
                text: text,
                sourceLanguage: source.map(localized),
                targetLanguage: localized(target)
            )
        }
    }

    private static func localized(_ lang: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: lang.minimalIdentifier)
            ?? lang.minimalIdentifier
    }
}
