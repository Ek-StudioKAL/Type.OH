# TODO — next session

Items are ordered by urgency. Each one names the most likely files to touch and a recommended Claude model.

> **Model legend.** Opus 4.7 = best for architecture and ambiguous multi-file work. Sonnet 4.6 = solid default for focused implementation/debug. Haiku 4.5 = fast and cheap for small mechanical edits.

---

## Completed (2026-05-02)

- ✅ Menu redesign — About / Dictate / ReTypeOH / Settings / Quit
- ✅ Dock icon toggle (`SettingsStore.showInDock`, Settings → General)
- ✅ Window constraint crash — `NSHostingController` + `sizingOptions = .preferredContentSize` on all panels
- ✅ Tab-switch crash — removed `withAnimation` from `ModeTabs` (layout thrash during animation was the cause)
- ✅ Responsive AI Editor — `minWidth: 460, idealWidth: 520, maxWidth: 900`
- ✅ Whisper model download confirmed working — `small` and `large-v3` downloaded and recognized. The `openai_whisper-*` prefix is WhisperKit's internal model ID (argmax distributes OpenAI's Whisper as CoreML on HuggingFace). Users see only "tiny", "base", "small" etc. — not a bug.
- ✅ Whisper auto-reload after download — no restart required
- ✅ Settings window z-order — activates app before opening (`NSApp.activate(ignoringOtherApps:)` in MenuBarContent)
- ✅ Settings window height increased to 430
- ✅ Status indicator color — teal `circle.fill` when downloaded-but-not-loaded (was gray/empty)
- ✅ Translate UX — same-language guard + friendly error messages instead of raw Apple errors
- ✅ Style presets replaced — Boomer 📋 / Gen X 🕶️ / Millennial 🥑 / Gen Z 💅 / Gen Alpha 🔥
- ✅ `docs/styles.md` — documents each preset and its prompt
- ✅ Unit tests 20/20 green — `StylePresetsTests` updated for new preset IDs
- ✅ `SettingsStore.init(settingsURL:)` test-only initializer (tests isolated from user settings)
- ✅ `macos-swift-expert` skill created at `~/.claude/skills/macos-swift-expert/`
- ✅ "Re-run Setup Wizard" button in Settings → General

---

## P0 — Blocking first release

### 1. AI Editor opens with empty text box

Selected text isn't captured — `SelectionReader.readSelectedText(from:)` returns nil. This breaks the core editor flow.

- Verify `AXIsProcessTrusted()` at hotkey fire time. Log the AX error code.
- The `⌘C` fallback may be racing the panel activation — increase the sleep delay or capture before the panel opens.
- Files: `Type.Oh/Editor/SelectionReader.swift`, `Type.Oh/AppDelegate.swift`.
- **Model: Sonnet 4.6.**

### 2. API key saving throws an error

Settings → Providers → Set key fails silently or crashes.

- Likely `SecItemAdd` returning `errSecDuplicateItem` with no update fallback.
- Check `KeychainStore.save(key:for:)` — add `SecItemUpdate` when `errSecDuplicateItem` is returned.
- Files: `Type.Oh/Core/KeychainStore.swift`.
- **Model: Haiku 4.5.** Small targeted fix.

### 3. Error banner — replace NSLog with visible toast

Errors (model load failure, voice errors, paste errors) are NSLog-only — invisible to the user.

- Add a small floating toast panel that auto-dismisses after 4 s.
- File: `Type.Oh/AppDelegate.swift`, new `Type.Oh/UI/ToastOverlay.swift`.
- **Model: Haiku 4.5.**

---

## P1 — High (rough UX)

### 4. Translate — language pack auto-download prompt

When the user picks a target language, Apple's TranslationSession can prompt to download the language pack. Currently this only happens when Translate is tapped — it should prompt immediately when the user selects the language pair.

- Use `TranslationSession.Configuration` with `prepareTranslation()` to trigger the download prompt on language selection.
- File: `Type.Oh/UI/AIEditorPanel.swift`, `Type.Oh/UI/LanguagePicker.swift`.
- **Model: Sonnet 4.6.**

### 5. Onboarding re-run — reset `hasCompletedOnboarding`

When "Re-run Setup Wizard" is triggered, `hasCompletedOnboarding` should be reset so the wizard flows cleanly from step 1. Currently it shows but the flag isn't cleared.

- In `AppDelegate.showOnboarding()`, set `settingsStore.hasCompletedOnboarding = false` before showing the panel.
- File: `Type.Oh/AppDelegate.swift`.
- **Model: Haiku 4.5.**

---

## P2 — Polish (pre-release nice-to-have)

### 6. App icon

Generate a placeholder 1024×1024 + full macOS icon set. Suggested motif: stylized waveform fused with a text caret. Drop into `Type.Oh/Assets.xcassets/AppIcon.appiconset/`.
- **Model: Sonnet 4.6** with the `algorithmic-art` or `canvas-design` skill.

### 7. UI polish pass — onboarding & settings

Screenshots in `screenshots_02-05-2026-17.29/` show the wizard and Settings are functional but plain. Improve visual hierarchy, spacing, and progress bar prominence.
- Files: `Type.Oh/UI/OnboardingWizard.swift`, `Type.Oh/UI/SettingsWindow.swift`.
- **Model: Sonnet 4.6.**

---

## P3 — V2

### macOS 15+ backward compatibility

On macOS 15, `FoundationModels` is unavailable — cloud provider fallback becomes the default. All other flows should degrade gracefully with `#available` guards.
- **Model: Opus 4.7.** Architectural.
