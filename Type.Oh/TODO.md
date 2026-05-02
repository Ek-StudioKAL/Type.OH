# TODO — next session

Items are ordered by urgency. Each one names the most likely files to touch and a recommended Claude model.

> **Model legend.** Opus 4.7 = best for architecture and ambiguous multi-file work. Sonnet 4.6 = solid default for focused implementation/debug. Haiku 4.5 = fast and cheap for small mechanical edits.

---

## Completed in last session (2026-05-02)

- ✅ Menu redesign — About / Dictate / ReTypeOH / Settings / Quit
- ✅ Dock icon toggle (`SettingsStore.showInDock`, Settings → General)
- ✅ Window constraint crash — switched all panels to `NSHostingController` + `sizingOptions = .preferredContentSize`; panels are now resizable with `minSize`
- ✅ Responsive AI Editor panel — `minWidth: 460, idealWidth: 520, maxWidth: 900`
- ✅ Whisper model auto-reload after download — no restart required (`Notification.Name.whisperModelDownloaded`)
- ✅ "Re-run Setup Wizard" button added to Settings → General
- ✅ Unit tests: 20/20 passing (`SettingsStoreTests`, `StylePresetsTests`, `ModelManagerTests`, placeholder `Type_OhTests`) — Xcode target wired and green
- ✅ `SettingsStore.init(settingsURL:)` test-only initializer added so tests are isolated from user's saved settings
- ✅ `macos-swift-expert` skill created at `~/.claude/skills/macos-swift-expert/`

---

## P0 — Critical (blocks the core flows)

### application crash when moving between windows
The test files do not catch the crash that happens when moving between windows. The application always crashes when the user tries to move between style or translate tabs in some instances it was fixed after runing the setup wizard again. THE TEST FILES DO NOT CATCH THIS CRASH. THIS IS A CRITICAL ISSUE!

Settings always open up as the last window in the desktop. I want it to be opened as the first window in the desktop!

### I think this part is already fixed. can you confirm it? 

```txt 
###  Whisper model never finishes downloading / WORONG WHISPER MODEL!

The Models tab shows the Download button, but clicking it never lands a usable model. Voice flow is dead until this is fixed.

- Reproduce: Settings → Models → click Download next to `base`. Tail `~/Library/Application Support/Type.OH/models/` while it runs.
- Suspects:
  - `WhisperKit.download(variant:downloadBase:)` may be falling back to its default HF cache dir instead of honoring `downloadBase`.
  - The variant id (`openai_whisper-base`) might not match what `argmaxinc/whisperkit-coreml` ships — try logging the resolved repo path inside the progressCallback.
  - `ModelManager.modelFolderURL(for:)` assumes the path persisted in UserDefaults — confirm it matches actual on-disk layout after a successful download.
- Files: `Type.Oh/Voice/ModelManager.swift`, `Type.Oh/Voice/WhisperService.swift`.
- **Model: Sonnet 4.6.**
```

!!! "openai_whisper" this is must be a mistake! we use the apple package whisperKit. where the fuck this openai model came for? do not complicate it. the test files do not catch the crash happens when moving between windows !!! - IMPORTANT!!

### Translate tab UX errors

From manual testing (screenshots 06-08):
- "Auto-detect" source language shows "unsupported" error — validate that `nil` source maps correctly to Apple's `TranslationSession` auto-detect, or fall back gracefully.
- Translating English → English shows an ugly system error — guard: if source == target, show a friendly "already in target language" message.
- Files: `Type.Oh/UI/AIEditorPanel.swift`, `Type.Oh/Editor/TranslationService.swift` (if it exists).
- **Model: Sonnet 4.6.**

---

## P1 — High (broken UX)

### 4. API key saving throws an error

Adding a key in Settings → Providers fails. Reproduce, capture the actual error, fix the Keychain write.

- Likely: missing entitlement for keychain access groups, or `SecItemAdd` returning `errSecDuplicateItem` without an update fallback.
- Files: `Type.Oh/Core/KeychainStore.swift`, `Type.Oh/UI/SettingsWindow.swift`.
- **Model: Sonnet 4.6.**

### 5. Error banner — replace NSLog with in-app toast

`showBannerError` currently just NSLogs. Replace with a brief floating toast visible to the user so voice errors and model-load errors are actually surfaced.

- A small `NSPanel`-based toast at the bottom-center of the screen that auto-dismisses after 4 s is sufficient.
- File: `Type.Oh/AppDelegate.swift`, new `Type.Oh/UI/ToastOverlay.swift`.
- **Model: Haiku 4.5.**

---

## P2 — Medium (polish)

### 7. Settings window height

The `SettingsWindow` frame is `height: 360` — the new "Re-run Setup Wizard" button may clip. Increase to `420` or switch to auto-sizing.
- File: `Type.Oh/UI/SettingsWindow.swift:16`.
- **Model: Haiku 4.5.**

### 8. App icon placeholder

Generate a 1024×1024 + full macOS icon set. Suggested motif: stylized waveform fused with a text caret on a tinted background. Drop into `Type.Oh/Assets.xcassets/AppIcon.appiconset/`.
- **Model: Sonnet 4.6** with the `algorithmic-art` or `canvas-design` skill.

### 9. Onboarding re-run polish

When "Re-run Setup Wizard" fires, `hasCompletedOnboarding` should reset to `false` so the wizard flows from step 1 and sets it back to `true` on Finish. Currently the wizard shows but a returning user may see stale state.
- File: `Type.Oh/AppDelegate.swift`, `Type.Oh/UI/OnboardingWizard.swift`.
new screenshot for settings window and wizard screens are ready in '/Volumes/Works/Antygravity-workspaces/Type.OH/screenshots_02-05-2026-17.29.'
review it and fix the UI. Make it nicer.
- **Model: Sonnet 4.6.**

---

## P3 — Future / V2

### macOS 15+ backward compatibility

Right-click Services extension has been removed from scope. The next V2 feature is backward compat with macOS 15+ for users not on macOS 26 Tahoe.

- On macOS 15, `FoundationModels` is unavailable — cloud provider fallback becomes the default.
- All other flows (voice, hotkeys, panel UI) should degrade gracefully with `#available` guards.
- **Model: Opus 4.7.** Architectural — touches every file that uses `FoundationModels`.
