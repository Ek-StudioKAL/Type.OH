import Foundation

/// Routes the Translate action to whichever engine the user picked in
/// Settings → Translation. Falls back gracefully if no engine is selected
/// (callers handle the `engineUnselected` error by opening Settings).
@MainActor
enum TranslationDispatcher {

    enum Failure: LocalizedError {
        case engineUnselected
        case nativeMissingLanguagePack
        case noActiveProvider

        var errorDescription: String? {
            switch self {
            case .engineUnselected:
                "Pick a translation engine in Settings → Translation."
            case .nativeMissingLanguagePack:
                "macOS doesn't have a language pack for this pair. Pick the language from a translate panel to trigger the download prompt."
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
        guard let engine = settings.translationProvider else {
            throw Failure.engineUnselected
        }

        switch engine {
        case .nativeOS:
            return try await NativeTranslationCoordinator.shared.translate(
                text: text,
                source: source,
                target: target
            )

        case .localLLM:
            let provider = AppleOnDeviceProvider()
            return try await provider.translate(
                text: text,
                sourceLanguage: source.map(localized),
                targetLanguage: localized(target)
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
