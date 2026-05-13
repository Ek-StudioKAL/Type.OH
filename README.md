# Type.OH

Type.OH is a native macOS writing and dictation utility for moving quickly between dictation, selected-text rewrites, translation, and longer-form editing.

## Workflows

- `LazyPad`: a persistent writing window with native AppKit text editing, provider switching, custom style presets, translation, and autosave.
- `ReType`: a selected-text popup for fixing, restyling, and translating text from other apps.
- `Dictate`: hold-to-record speech transcription with local Whisper models.

## Screenshots

![Menu bar menu](screenshots/menubar_menu.png)

![ReType popup window](screenshots/ReTypo_popup_window.png)

![ReType translation window](screenshots/ReTypo_popup_window_translation.png)

![LazyPad window](screenshots/SketchPad-LazyPad-window.png)

## Requirements

- macOS with Xcode installed.
- Accessibility permission for cross-app text capture and paste workflows.
- Microphone permission for dictation.
- A downloaded Whisper model for local speech transcription.
- Optional API keys in macOS Keychain for Anthropic, OpenAI, or Gemini.
- Apple Intelligence availability if using the Apple on-device LLM provider.

## Setup

1. Open `Type.Oh/Type.Oh.xcodeproj` in Xcode.
2. Select the main app scheme.
3. Build and run the app.
4. Complete the setup wizard.
5. Grant Accessibility and Microphone access when prompted.
6. Download a Whisper model from `Settings -> Whisper`.
7. Add cloud provider keys in `Settings -> Providers` if you want to use Anthropic, OpenAI, or Gemini.

## Hotkeys

The defaults are:

- `F13`: voice dictation.
- `F14`: ReType selected-text editor.
- `F15`: LazyPad.

You can change or reset these in `Settings -> General`.

## Translation

Type.OH supports three translation engines:

- Native macOS Translation: offline and fast, with limited languages.
- Apple On-Device LLM: private local model when Apple Intelligence is available.
- Cloud Provider: uses the currently selected Anthropic, OpenAI, or Gemini provider.

## Running Outside Xcode

You can also build the app from this repository and run the built `.app` directly.

```bash
xcodebuild -project Type.Oh/Type.Oh.xcodeproj -scheme Type.Oh -configuration Release build
```

The built app appears under Xcode DerivedData, for example:

```text
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Release/Type.Oh.app
```

Launch it with:

```bash
open /path/to/Type.Oh.app
```

If macOS blocks first launch, right-click `Type.Oh.app` in Finder and choose `Open`, or allow it from System Settings after the first launch attempt.

If the app was downloaded, copied, or archived and macOS added quarantine attributes, you may need:

```bash
xattr -dr com.apple.quarantine /path/to/Type.Oh.app
```

## Important Note

This repository does not currently produce a signed or notarized app. macOS may warn that the app is from an unidentified developer, and some users may need to launch it with `Right-click -> Open`.

## Development Notes

- Cloud provider keys are stored in the user Keychain, not in this repository.
- LazyPad autosaves its text in Application Support.
- Provider-specific sidebar icons live in the asset catalog.
- The app defaults to showing in the Dock.
- The first setup completion opens LazyPad automatically.
