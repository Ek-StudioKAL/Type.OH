# Type.OH

Type.OH is a native macOS writing and dictation utility with three main workflows:

- `LazyPad`: a lightweight free-writing window with native AppKit text editing, translation, style actions, and provider selection
- `ReType`: a selected-text rewrite window for fixing, improving, styling, and translating text from other apps
- `Dictate`: hold-to-record speech transcription with Whisper

## Requirements

- macOS with Xcode installed
- Accessibility permission for cross-app text capture/paste workflows
- Microphone permission for dictation
- Optional API keys in the macOS Keychain for Anthropic, OpenAI, or Gemini

## Important Note

This repository does **not** currently produce a signed or notarized app.

That means:

- macOS may warn that the app is from an unidentified developer
- some users may need to launch it with `Right-click -> Open`
- Gatekeeper or quarantine flags can block first launch, especially if the app is moved or zipped

## Running From Xcode

1. Open `Type.Oh/Type.Oh.xcodeproj` in Xcode.
2. Select the main app scheme.
3. Build and run the app.
4. Complete the setup wizard.
5. Grant Accessibility and Microphone access when prompted.

## Testing This Repo Outside Xcode

You can also build the app from this repository and run the built `.app` directly.

Typical flow:

1. Build a Release app:

```bash
xcodebuild -project Type.Oh/Type.Oh.xcodeproj -scheme Type.Oh -configuration Release build
```

2. Locate the built app under Xcode DerivedData, for example:

```text
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/Type.Oh.app
```

3. If macOS blocks launch, try one of these:

- Finder: right-click `Type.Oh.app` and choose `Open`
- System Settings: allow the app from the Privacy & Security pane after the first launch attempt

4. If the app was downloaded, copied, or archived and macOS added quarantine attributes, you may need:

```bash
xattr -dr com.apple.quarantine /path/to/Type.Oh.app
```

5. Launch the app:

```bash
open /path/to/Type.Oh.app
```

## Setup Notes

- Cloud provider keys are stored in the user Keychain, not in this repository.
- Apple on-device AI availability depends on OS support and Apple Intelligence availability.
- LazyPad autosaves its text in Application Support.

## Current Development Notes

- The app includes provider-specific sidebar icons from the asset catalog.
- The app defaults to showing in the Dock.
- The first setup completion opens LazyPad automatically.
