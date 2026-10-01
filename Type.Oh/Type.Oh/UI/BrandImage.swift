import AppKit
import SwiftUI

/// Provider brand symbols. When the app is built by Xcode they come from the
/// asset catalog (`Claude`, `GPT`, `Gemini` symbolsets). When it is bundled by
/// `build-app.sh` (no `actool`), the same SVGs are copied loose into
/// `Contents/Resources` and loaded from there.
enum BrandImages {
    static func nsImage(named name: String) -> NSImage? {
        if let image = NSImage(named: name) {
            return image
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return image
        }
        return nil
    }
}

@MainActor struct BrandImage: View {
    let name: String

    var body: some View {
        if let image = BrandImages.nsImage(named: name) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
        } else {
            Image(systemName: "cpu")
                .resizable()
                .scaledToFit()
        }
    }
}
