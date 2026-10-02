import AppKit
import SwiftUI

/// Type.OH's own icon set: 24×24 monoline SVGs in `icons/svg/`, rendered to
/// vector PDFs in `Type.Oh/Icons/` by `tools/build-icons.swift` (regular
/// 1.5 px and `-bold` 2 px stroke). Xcode bundles that folder automatically;
/// build-app.sh copies it for the SwiftPM (macOS 13) build. Raw values are
/// the SVG names without their number prefix.
enum AppIcon: String, CaseIterable, Sendable {
    case fix
    case improve
    case style
    case translate
    case concise
    case dictate
    case pasteToApp = "paste-to-app"
    case paste
    case copy
    case clear
    case language
    case swapLanguages = "swap-languages"
    case autoDetect = "auto-detect"
    case search
    case generalSettings = "general-settings"
    case settings
    case aiProviders = "ai-providers"
    case voiceModel = "voice-model"
    case reload
    case addPreset = "add-preset"
    case add
    case boomer
    case genX = "gen-x"
    case millennial
    case genZ = "gen-z"
    case genAlpha = "gen-alpha"
    case anthropicProvider = "anthropic-provider"
    case googleProvider = "google-provider"
    case voiceToText = "voice-to-text"
    case aiEditor = "ai-editor"
    case lazypad
    case microphoneBlocked = "microphone-blocked"
    case accessibilityMissing = "accessibility-missing"
    case warning
    case needsAttention = "needs-attention"
    case granted
    case denied
    case selected
    case statusDot = "status-dot"
    case stepInactive = "step-inactive"
    case stepActive = "step-active"
    case genericAIProvider = "generic-ai-provider"
    case hideSidebar = "hide-sidebar"
    case showSidebar = "show-sidebar"
    case chevronDown = "chevron-down"
    case chevronUp = "chevron-up"
    case openAIProvider = "openai-provider"

    /// Template image, `size`×`size` points. `bold` is the 2 px stroke
    /// variant, used for active / hovered toolbar items.
    @MainActor
    func nsImage(size: CGFloat, bold: Bool = false) -> NSImage {
        AppIconCache.image(for: self, size: size, bold: bold)
    }
}

extension Image {
    /// An `AppIcon` drawn `size` points square; tint it with `.foregroundStyle`.
    @MainActor
    init(appIcon icon: AppIcon, size: CGFloat, bold: Bool = false) {
        self = Image(nsImage: icon.nsImage(size: size, bold: bold)).renderingMode(.template)
    }
}

@MainActor
private enum AppIconCache {
    private static var sources: [String: NSImage] = [:]
    private static var sized: [String: NSImage] = [:]

    static func image(for icon: AppIcon, size: CGFloat, bold: Bool) -> NSImage {
        let file = "icon-\(icon.rawValue)\(bold ? "-bold" : "")"
        let key = "\(file)@\(size)"
        if let image = sized[key] { return image }

        let source: NSImage
        if let cached = sources[file] {
            source = cached
        } else if let url = Bundle.main.url(forResource: file, withExtension: "pdf"),
                  let loaded = NSImage(contentsOf: url) {
            sources[file] = loaded
            source = loaded
        } else {
            assertionFailure("\(file).pdf is missing from the app bundle — run tools/build-icons.swift")
            return NSImage(size: NSSize(width: size, height: size))
        }

        // PDF reps stay vector at any size.
        let image = source.copy() as! NSImage
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        sized[key] = image
        return image
    }
}
