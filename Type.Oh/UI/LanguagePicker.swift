import SwiftUI
import Translation

struct LanguagePicker: View {
    @Binding var sourceLanguage: Locale.Language?
    @Binding var targetLanguage: Locale.Language

    @State private var supported: [Locale.Language] = []

    var body: some View {
        HStack(spacing: 10) {
            langMenu(
                current: sourceLanguage.map { displayName($0) } ?? "Auto",
                includeAuto: true
            ) { lang in
                sourceLanguage = lang
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            langMenu(
                current: displayName(targetLanguage),
                includeAuto: false
            ) { lang in
                if let lang { targetLanguage = lang }
            }
        }
        .task { supported = LanguageAvailability().supportedLanguages }
    }

    // MARK: - Helpers

    private func displayName(_ lang: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: lang.minimalIdentifier) ?? lang.minimalIdentifier
    }

    @ViewBuilder
    private func langMenu(
        current: String,
        includeAuto: Bool,
        onSelect: @escaping (Locale.Language?) -> Void
    ) -> some View {
        Menu {
            if includeAuto {
                Button("Auto-detect") { onSelect(nil) }
                Divider()
            }
            ForEach(supported, id: \.maximalIdentifier) { lang in
                Button(displayName(lang)) { onSelect(lang) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current).font(.callout)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
