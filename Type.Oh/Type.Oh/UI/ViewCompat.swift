import SwiftUI

extension View {
    /// `.focusEffectDisabled()` where it exists (macOS 14+). Hides the focus
    /// ring around the app's panels and Settings; macOS 13 keeps the ring.
    /// The macOS 13.3 SDK doesn't declare it at all, so `#available` alone
    /// isn't enough there (`TYPEOH_MACOS13_SDK`, see Package.swift).
    @ViewBuilder
    func typeOhFocusEffectDisabled() -> some View {
        #if TYPEOH_MACOS13_SDK
        self
        #else
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
        #endif
    }
}
