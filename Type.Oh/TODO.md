# TODO — next session

Items are ordered by urgency. Each one names the most likely files to touch and a recommended Claude model.

> **Model legend.** Opus 4.7 = best for architecture and ambiguous multi-file work. Sonnet 4.6 = solid default for focused implementation/debug. Haiku 4.5 = fast and cheap for small mechanical edits.

---

## P0 — Critical (blocks the core flows)

### 1. Whisper model never finishes downloading / fails to load
The Models tab shows the Download button, but clicking it never lands a usable model. Voice flow is dead until this is fixed.

- Reproduce: Settings → Models → click Download next to `base`. Tail `~/Library/Application Support/Type.OH/models/` while it runs.
- Suspects:
  - `WhisperKit.download(variant:downloadBase:)` may be falling back to its default HF cache dir instead of honoring `downloadBase`.
  - The variant id (`openai_whisper-base`) might not match what `argmaxinc/whisperkit-coreml` ships — try logging the resolved repo path inside the progressCallback.
  - `ModelManager.modelFolderURL(for:)` assumes `argmaxinc/whisperkit-coreml/{id}/` — confirm against actual on-disk layout after a successful download.
- Files: `Type.Oh/Voice/ModelManager.swift`, `Type.Oh/Voice/WhisperService.swift`.
- **Model: Sonnet 4.6.** Focused debug, two files.

### 2. AI Editor opens with an empty text box
Selected text isn't making it into the editor — `SelectionReader.readSelectedText(from:)` is returning nil. Add **Copy** and **Paste** buttons inside the editor as a manual fallback regardless.

- Likely AX permission isn't actually granted, or the `⌘C` fallback is racing the panel activation.
- Verify `AXIsProcessTrusted()` at hotkey time and log the AX error.
- Files: `Type.Oh/Editor/SelectionReader.swift`, `Type.Oh/UI/AIEditorPanel.swift`, `Type.Oh/AppDelegate.swift`.
- **Model: Sonnet 4.6.**

### 3. First-launch onboarding wizard (crucial)
Right now the app launches into nothing — no Whisper model, no Apple Intelligence check, no API key. Build a wizard (can reuse the existing SettingsWindow tabs with step instructions) that walks:

1. Apple Intelligence status (`SystemLanguageModel.default.availability`)
2. Permissions: Microphone + Accessibility (deep-link to System Settings if missing)
3. Whisper model download (default to `base`, show RAM/disk per option)
4. Provider/API key selection
5. "All set — loaded & ready" summary with active model + RAM use

Gate behind `SettingsStore.hasCompletedOnboarding`. Also surface model load status + RAM in Settings → Models permanently.

- Files: new `Type.Oh/UI/OnboardingWizard.swift`, `Type.Oh/Core/SettingsStore.swift`, `Type.Oh/AppDelegate.swift`, `Type.Oh/UI/SettingsWindow.swift`.
- **Model: Opus 4.7.** Multi-file UX flow, several judgment calls about reuse vs duplication.

---

## P1 — High (broken UX)

### 4. API key adding throws an error
Adding a key in Settings → Providers fails. Reproduce, capture the actual error, fix the Keychain write.

- Likely candidates: missing entitlement for keychain access groups, or `SecItemAdd` returning `errSecDuplicateItem` without an update fallback.
- Files: `Type.Oh/Core/KeychainStore.swift`, `Type.Oh/UI/SettingsWindow.swift`.
- **Model: Sonnet 4.6.**

### 5. Editor & recording panels open behind other windows
Both panels should appear frontmost the moment the hotkey fires. `panel.level = .floating` is set, but `NSApp.activate()` may not be promoting the menu-bar app to front under `LSUIElement`.

- Try: `NSApp.setActivationPolicy(.regular)` briefly while the panel is open, then revert; or use `panel.makeKeyAndOrderFront(nil)` after a `RunLoop.main.perform` hop.
- File: `Type.Oh/AppDelegate.swift`.
- **Model: Haiku 4.5.** Small, mechanical.

---

## P2 — Medium (polish)

### 6. Redesign menu-bar menu
Replace the current menu with:
1. **Type.OH** → opens an About panel (version, credits, API status, Whisper model status, Settings button)
2. **Dictate** → toggles voice recording (same as ⌃F13)
3. **ReTypeOH** → opens the AI Editor and keeps it open for longer multi-edit sessions (don't auto-close on Apply)
4. **Settings…**
5. **Quit Type.OH**

- Files: `Type.Oh/UI/MenuBarContent.swift`, new `Type.Oh/UI/AboutPanel.swift`, `Type.Oh/UI/AIEditorPanel.swift` (sticky-mode flag), `Type.Oh/AppDelegate.swift`.
- **Model: Sonnet 4.6.**

### 7. Optional Dock icon
Add a `SettingsStore.showInDock` toggle. When on: `NSApp.setActivationPolicy(.regular)`. When off: `.accessory`. Persist and apply on launch.

- Files: `Type.Oh/Core/SettingsStore.swift`, `Type.Oh/AppDelegate.swift`, `Type.Oh/UI/SettingsWindow.swift`.
- **Model: Haiku 4.5.**

### 8. Temporary app icon
Generate a placeholder for Dock + app (1024×1024 + the full macOS icon set). Suggested motif: a stylized waveform fused with a text caret on a tinted background. Drop into `Type.Oh/Assets.xcassets/AppIcon.appiconset/`.

- **Model: Sonnet 4.6** with the `algorithmic-art` or `canvas-design` skill, or hand off to an image generator and just wire the assets.

---

## P3 — Future / v2

### 9. Right-click "Type.OH" as a System Service
Add an Action Extension target so Type.OH appears in the Services menu and the right-click context menu on any selected text. Original PRD lives in `CONTEXT.md §7`.

- New target: `Type.OH Editor Extension`. Share the `Editor/` code via an internal framework or app group.
- Watch out for sandbox + extension entitlement mismatches.
- **Model: Opus 4.7.** Extension targets are finicky and Apple-specific.
