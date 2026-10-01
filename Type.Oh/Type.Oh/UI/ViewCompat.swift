import SwiftUI

extension View {
    /// `.focusEffectDisabled()` where it exists (macOS 14+). Hides the focus
    /// ring around the app's panels and Settings; macOS 13 keeps the ring.
    @ViewBuilder
    func typeOhFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }
}
