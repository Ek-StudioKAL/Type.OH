import AppKit
import SwiftUI

/// The app's accent color, mirrored from `Assets.xcassets/AccentColor.colorset`.
///
/// Xcode compiles that color set into the app and macOS applies it as the
/// accent automatically. The SwiftPM build (`build-app.sh`) has no compiled
/// asset catalog, so `Color.accentColor` would fall back to the system accent
/// (blue). Applying `.typeOhAccent()` at every SwiftUI root restores it.
extension NSColor {
    static let typeOhAccent = NSColor(name: "TypeOhAccent") { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.906, green: 0.263, blue: 0.251, alpha: 1)   // dark appearance
            : NSColor(srgbRed: 0.898, green: 0.400, blue: 0.349, alpha: 1)   // light appearance
    }
}

extension Color {
    static let typeOhAccent = Color(nsColor: .typeOhAccent)
}

extension View {
    /// Apply the app accent to a view hierarchy (covers `Color.accentColor`,
    /// `.tint`-aware controls, and prominent buttons).
    func typeOhAccent() -> some View {
        self.accentColor(.typeOhAccent).tint(.typeOhAccent)
    }
}
