import AppKit
import SwiftUI

extension View {
    /// `.focusEffectDisabled()` where it exists (macOS 14+). Hides the focus
    /// ring around the app's panels and Settings. The macOS 13.3 SDK doesn't
    /// declare it at all, so `#available` alone isn't enough there
    /// (`TYPEOH_MACOS13_SDK`, see Package.swift).
    ///
    /// Without it (macOS 13, or any build from Package.swift) the ring can't be
    /// hidden, so the window's opening focus is dropped instead: with keyboard
    /// navigation on (System Settings > Keyboard), a window focuses its first
    /// button when it opens and rings it (Settings' General tab, LazyPad's
    /// Hide). Tab still moves focus as usual.
    @MainActor @ViewBuilder
    func typeOhFocusEffectDisabled() -> some View {
        #if TYPEOH_MACOS13_SDK
        background(OpeningFocusDropper())
        #else
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            background(OpeningFocusDropper())
        }
        #endif
    }
}

@MainActor private struct OpeningFocusDropper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DropperView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DropperView: NSView {
        /// Armed while the window is off screen, so only the activation that
        /// opens it drops focus, not every return to it.
        private var isOpening = true

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            let center = NotificationCenter.default
            if let window {
                center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
                center.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
            }
            if let newWindow {
                center.addObserver(self, selector: #selector(windowDidBecomeKey),
                                   name: NSWindow.didBecomeKeyNotification, object: newWindow)
                center.addObserver(self, selector: #selector(windowWillClose),
                                   name: NSWindow.willCloseNotification, object: newWindow)
            }
            isOpening = !(newWindow?.isVisible ?? false)
        }

        @objc private func windowDidBecomeKey() {
            guard isOpening else { return }
            isOpening = false
            // The window picks its first key view as it turns key; let that
            // settle, then clear it. A focused text view or field is kept.
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.window, !(window.firstResponder is NSText) else { return }
                window.makeFirstResponder(nil)
            }
        }

        @objc private func windowWillClose() {
            isOpening = true
        }
    }
}
