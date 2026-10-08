# Type.OH on the Touch Bar

macOS exposes Automator **Quick Actions** on the Touch Bar through the
"Quick Actions" Control Strip button (and through Fn when the Fn mode is set
to Quick Actions, which is how this Mac is configured). Each Quick Action here
is a one-line shell workflow:

    open -g "typeoh://dictate"      # or retype / lazypad / settings

The app handles the `typeoh://` scheme in `AppDelegate.application(_:open:)`
and runs the same code path as the global hotkey. `-g` keeps the app you were
in frontmost, so focus capture and paste-back behave exactly like the hotkey.

    ./touchbar/install.sh            # installs 3 workflows into ~/Library/Services
    ./touchbar/install.sh --strip    # also pins Quick Actions in the compact strip
    ./touchbar/uninstall.sh [--strip]

Notes
- Quick Actions are listed by name; tap "Quick Actions" then "Dictate"
  (icons: microphone, text box, compose; only Apple's Touch Bar icons work).
  Tap it again while recording to stop and transcribe (same toggle as the dictation hotkey).
- System Settings → Extensions → Touch Bar Quick Actions controls which ones
  appear; System Settings → Keyboard → Customize Control Strip places the
  button.
- Inside the app, LazyPad and ReType have their own Touch Bar while their
  window is in front (`UI/TypeOhTouchBar.swift`): Dictate / Improve / Fix /
  Concise / Translate and the styles in LazyPad (next to the typing
  suggestions); Fix / Improve / Style / Translate / Insert in ReType.
- A persistent, single-tap button *outside* the Quick Actions list is the
  app's own Control Strip button (Settings → General → Touch Bar), which uses
  the private DFRFoundation API from a helper process (`UI/ControlStrip.swift`).
- Alternative without the Touch Bar: Shortcuts.app → "Open URL" `typeoh://…`,
  which also gets a menu-bar entry.
