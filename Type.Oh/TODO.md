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
- ✅ Unit test files created (`SettingsStoreTests`, `StylePresetsTests`, `ModelManagerTests`) — need Xcode target wiring (see P1 #6)
- ✅ `macos-swift-expert` skill created at `~/.claude/skills/macos-swift-expert/`

---

## P0 — Critical (blocks the core flows)

### 1. Whisper model never finishes downloading / fails to load

The Models tab shows the Download button, but clicking it never lands a usable model. Voice flow is dead until this is fixed.

- Reproduce: Settings → Models → click Download next to `base`. Tail `~/Library/Application Support/Type.OH/models/` while it runs.
- Suspects:
  - `WhisperKit.download(variant:downloadBase:)` may be falling back to its default HF cache dir instead of honoring `downloadBase`.
  - The variant id (`openai_whisper-base`) might not match what `argmaxinc/whisperkit-coreml` ships — try logging the resolved repo path inside the progressCallback.
  - `ModelManager.modelFolderURL(for:)` assumes the path persisted in UserDefaults — confirm it matches actual on-disk layout after a successful download.
- Files: `Type.Oh/Voice/ModelManager.swift`, `Type.Oh/Voice/WhisperService.swift`.
- **Model: Sonnet 4.6.**

### 2. AI Editor opens with an empty text box

Selected text isn't making it into the editor — `SelectionReader.readSelectedText(from:)` is returning nil.

- Likely AX permission isn't actually granted, or the `⌘C` fallback is racing the panel activation.
- Verify `AXIsProcessTrusted()` at hotkey time and log the AX error.
- Files: `Type.Oh/Editor/SelectionReader.swift`, `Type.Oh/UI/AIEditorPanel.swift`, `Type.Oh/AppDelegate.swift`.
- **Model: Sonnet 4.6.**

### 3. Translate tab UX errors

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

### 6. Wire up Xcode test target

Test files exist at `Type.OhTests/` but are not attached to a test scheme. Steps:
1. Xcode: File → New → Target → Unit Testing Bundle → name `Type.OhTests`
2. Set "Target to be Tested" to `Type.Oh`
3. Delete the auto-generated placeholder `.swift` file; the three existing files are already in the project group
4. Run `⌘U` to confirm all pass

No code changes needed — purely Xcode project configuration.

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
- **Model: Haiku 4.5.**

---

## P3 — Future / V2

### macOS 15+ backward compatibility

Right-click Services extension has been removed from scope. The next V2 feature is backward compat with macOS 15+ for users not on macOS 26 Tahoe.

- On macOS 15, `FoundationModels` is unavailable — cloud provider fallback becomes the default.
- All other flows (voice, hotkeys, panel UI) should degrade gracefully with `#available` guards.
- **Model: Opus 4.7.** Architectural — touches every file that uses `FoundationModels`.
