import SwiftUI
import Translation

enum LanguagePickerAvailability: Equatable {
    case allLocaleLanguages
    case nativeOSOffline
}

struct LanguagePicker: View {
    @Binding var sourceLanguage: Locale.Language?
    @Binding var targetLanguage: Locale.Language
    /// When true the row is compact (no headings, narrower spacing) so it fits
    /// inline in ReType. When false the row is roomier and shows "From / To" labels.
    var compact: Bool = false
    var availability: LanguagePickerAvailability = .allLocaleLanguages

    @State private var supported: [Locale.Language] = []

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if !compact {
                    Text("From")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                LangPickerButton(
                    title: sourceLanguage.map(displayName) ?? "Auto",
                    isAuto: sourceLanguage == nil,
                    supported: supported,
                    includeAuto: true,
                    onSelect: { sourceLanguage = $0 }
                )
            }

            Button {
                swap()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("Swap source and target")
            .disabled(sourceLanguage == nil)
            .opacity(sourceLanguage == nil ? 0.45 : 1.0)
            .offset(y: compact ? 0 : 9)

            VStack(alignment: .leading, spacing: 3) {
                if !compact {
                    Text("To")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                LangPickerButton(
                    title: displayName(targetLanguage),
                    isAuto: false,
                    supported: supported,
                    includeAuto: false,
                    onSelect: { if let lang = $0 { targetLanguage = lang } }
                )
            }
        }
        .task(id: availability) {
            supported = await availableLanguages(for: availability)
            sanitizeSelection()
        }
    }

    private func swap() {
        guard let src = sourceLanguage else { return }
        sourceLanguage = targetLanguage
        targetLanguage = src
    }

    private func displayName(_ lang: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: lang.minimalIdentifier) ?? lang.minimalIdentifier
    }

    private func availableLanguages(for availability: LanguagePickerAvailability) async -> [Locale.Language] {
        switch availability {
        case .allLocaleLanguages:
            return allLocaleLanguages()
        case .nativeOSOffline:
            if #available(macOS 26.4, *) {
                let availability = LanguageAvailability(preferredStrategy: .lowLatency)
                return sortedUniqueLanguages(await availability.supportedLanguages)
            } else {
                return sortedUniqueLanguages(await LanguageAvailability().supportedLanguages)
            }
        }
    }

    private func allLocaleLanguages() -> [Locale.Language] {
        var seen = Set<String>()
        let languages = Locale.availableIdentifiers
            .compactMap { identifier -> Locale.Language? in
                let language = Locale.Language(identifier: identifier)
                let minimal = language.minimalIdentifier
                guard !minimal.isEmpty else { return nil }
                guard seen.insert(minimal).inserted else { return nil }
                return Locale.Language(identifier: minimal)
            }
        return sortedUniqueLanguages(languages)
    }

    private func sortedUniqueLanguages(_ languages: [Locale.Language]) -> [Locale.Language] {
        var seen = Set<String>()
        return languages
            .compactMap { language -> Locale.Language? in
                let minimal = language.minimalIdentifier
                guard !minimal.isEmpty else { return nil }
                guard seen.insert(minimal).inserted else { return nil }
                return Locale.Language(identifier: minimal)
            }
            .sorted {
                displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending
            }
    }

    private func sanitizeSelection() {
        guard !supported.isEmpty else { return }
        if let sourceLanguage, !containsSupported(sourceLanguage) {
            self.sourceLanguage = nil
        }
        if !containsSupported(targetLanguage) {
            targetLanguage = supported.first(where: { $0.minimalIdentifier == "en" }) ?? supported[0]
        }
    }

    private func containsSupported(_ language: Locale.Language) -> Bool {
        supported.contains { $0.minimalIdentifier == language.minimalIdentifier }
    }
}

/// Searchable popover language picker. Tap the button → popover with a search
/// field on top, a "Common" section, and the full A–Z list below.
struct LangPickerButton: View {
    let title: String
    let isAuto: Bool
    let supported: [Locale.Language]
    let includeAuto: Bool
    var autoTitle: String = "Auto-detect"
    let onSelect: (Locale.Language?) -> Void

    @State private var isShowingPopover = false
    @State private var query = ""

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            HStack(spacing: 6) {
                if isAuto {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 130, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            popoverContent
                .frame(width: 280, height: 360)
        }
    }

    @ViewBuilder
    private var popoverContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search languages", text: $query)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if includeAuto, query.isEmpty {
                        row(label: autoTitle, systemImage: "sparkle") {
                            onSelect(nil)
                            isShowingPopover = false
                        }
                        Divider().padding(.leading, 12)
                    }

                    if query.isEmpty {
                        sectionHeader("Common")
                        ForEach(commonLanguages, id: \.maximalIdentifier) { lang in
                            languageRow(lang)
                        }
                        Divider().padding(.leading, 12).padding(.top, 4)
                        sectionHeader("All")
                    }

                    ForEach(filteredLanguages, id: \.maximalIdentifier) { lang in
                        languageRow(lang)
                    }

                    if filteredLanguages.isEmpty && !query.isEmpty {
                        Text("No matches")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private func languageRow(_ lang: Locale.Language) -> some View {
        row(label: displayName(lang), systemImage: nil) {
            onSelect(lang)
            isShowingPopover = false
        }
    }

    @ViewBuilder
    private func row(label: String, systemImage: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                Text(label)
                    .font(.callout)
                Spacer(minLength: 0)
                if label == title {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filteredLanguages: [Locale.Language] {
        guard !query.isEmpty else { return supported }
        let lc = query.localizedLowercase
        return supported.filter {
            displayName($0).localizedLowercase.contains(lc)
                || $0.minimalIdentifier.localizedLowercase.contains(lc)
        }
    }

    private var commonLanguages: [Locale.Language] {
        let codes = ["en", "es", "fr", "de", "it", "pt", "zh-Hans", "ja", "ko", "ru", "ar"]
        return codes
            .map { Locale.Language(identifier: $0) }
            .filter { common in
                supported.contains { $0.minimalIdentifier == common.minimalIdentifier }
            }
    }

    private func displayName(_ lang: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: lang.minimalIdentifier) ?? lang.minimalIdentifier
    }
}
