# TODO — next session

Items are ordered by urgency. Each one names the most likely files to touch and a recommended Claude model.

> **Model legend.** Opus 4.7 = best for architecture and ambiguous multi-file work. Sonnet 4.6 = solid default for focused implementation/debug. Haiku 4.5 = fast and cheap for small mechanical edits.

Previous sessions: menu redesign, dock toggle, toast errors, API-key fix, AX read-via-copy reliability, lang-pack prep, generation-themed style presets, app icon + onboarding polish, **LazyPad workspace + provider sidebar (`f36ef79`)**.

---

## P0 — Blockers from live testing (2026-05-12)

### 1. LazyPad: typing lag + overwrite during fast input ✅

**Symptom (reported):** Autocomplete is laggy and *sometimes overwrites text while the user is typing*. After a few lines / a paragraph, the input window "goes crazy" — characters disappear or shift and the change can't be reverted.

**Root cause:** `Type.Oh/UI/NativeTextView.swift::updateNSView` does:

```swift
if textView.string != text {
    textView.string = text
    ...
}
```

SwiftUI re-renders are async, so during fast typing the `text` binding can lag behind `textView.string` (the user has typed more chars than SwiftUI has propagated). When `updateNSView` runs it sees a "mismatch" and destructively re-assigns `textView.string = text` — clobbering in-flight keystrokes, IME composition, and undo history.

**Shipped:** `NativeTextView.updateNSView` no longer assigns `textView.string = text` during normal SwiftUI refreshes. The coordinator tracks `lastSyncedText`, programmatic edits resync that cache, and out-of-band binding writes use `textStorage.replaceCharacters(in:with:)` behind `shouldChangeText`. This preserves in-flight typing, selection, IME composition, and undo history.

**Files:** `Type.Oh/UI/NativeTextView.swift`, `Type.Oh/UI/ScratchpadView.swift`.
**Model: Opus 4.7.**

### 2. LazyPad: long text becomes unrevertable ✅

Same root cause as #1 — once `textView.string =` runs, the undo stack is dropped and the scroll/selection state is reset.

**Shipped:** same `NativeTextView` rewrite as #1. Programmatic replacements now go through text storage and the bridge no longer clobbers the document on render passes. Also fixed the stale/ghost-line redraw issue by making the scroll view, clip view, and text view draw opaque text backgrounds and explicitly invalidating layout/display after text changes.

Manual verification still useful before release:

- Undo (⌘Z) restores characters after AI replace.
- Scroll position stays anchored during AI rewrite.
- IME composition (CJK / dead-keys) isn't interrupted by SwiftUI re-renders.

**Files:** same as #1.
**Model: Sonnet 4.6.**

### 3. ReType crashes on uneditable selection — should fall through to LazyPad ✅

**Symptom:** Invoking ReType while text is selected in a *non-editable* surface (web view static text, PDF, image OCR, etc.) crashes the app.

**Likely causes:**
- `SelectionReader.readViaAX` has `let focused = focusedRef as! AXUIElement` — force cast traps if AX returns an unexpected type.
- After the ReType panel applies its result, `PasteService.paste` posts ⌘V into a target that has no editable focus — paste may silently fail, but the bigger UX bug is that the user can't *use* the rewrite.

**Shipped:**
1. `SelectionReader` now verifies the focused AX value's CoreFoundation type before bridging it, so unexpected AX objects fail closed instead of trapping.
2. Capture now returns `CapturedSelection(text:isEditable:)`; editability is based on `AXUIElementIsAttributeSettable(..., kAXSelectedTextAttribute, ...)`.
3. `AppDelegate` routes non-editable captured text into LazyPad with a toast instead of opening ReType and attempting to paste back into an uneditable surface.

**Files:** `Type.Oh/Editor/SelectionReader.swift`, `Type.Oh/AppDelegate.swift`, possibly add a helper to `Core/FocusCapture.swift`.
**Model: Opus 4.7.**

---

## P1 — Translation UX

### 4. Translate panel feels like a system menu, not a feature

**Symptom (reported):** "Translation function needs improvements in the UI scope."

**Current state:**
- `LanguagePicker` is now searchable and uses custom popovers instead of flat NSMenu lists.
- Source/target swap is implemented.
- Native macOS offline translation filters the source/target lists to `LanguageAvailability.supportedLanguages`.
- ReType and LazyPad both use the same language picker surface.

**Remaining polish:**
- "Recent languages" row above the full list (persist 3–5 most-used in `SettingsStore`).
- Consider an inline translation strip in ReType instead of the current toolbar popover.
- LazyPad popover: make action button sticky at the bottom if clipping appears on smaller displays.

**Files:** `Type.Oh/UI/LanguagePicker.swift`, `Type.Oh/UI/AIEditorPanel.swift`, `Type.Oh/UI/ScratchpadView.swift`, `Type.Oh/Core/SettingsStore.swift` (recents persistence).
**Model: Sonnet 4.6.**

---

## P2 — Robustness pass

### 5. Crash log / diagnostics dump ✅

Shipped this session — `Type.Oh/Core/CrashReporter.swift`. Installed from `AppDelegate.applicationDidFinishLaunching`. Captures `NSSetUncaughtExceptionHandler` plus SIGABRT/SIGSEGV/SIGILL/SIGBUS/SIGFPE/SIGPIPE, writes ISO-timestamped reports to `~/Library/Logs/Type.OH/crash-*.log`, rotates after 10 files, re-raises the signal so the OS still produces its own report.

### 6. Coalesce ScratchpadStore writes ✅

Shipped this session — `ScratchpadStore` now uses a single `DispatchSourceTimer` that resets its deadline on each `scheduleSave` call instead of spawning a Task per keystroke.

### 7. Idle memory readout helper ✅ (full profile pass still pending)

Shipped this session — `Type.Oh/Core/MemoryReporter.swift` exposes RSS via `mach_task_basic_info`. LazyPad status bar shows live `Mem: NNN MB` (3 s tick). Real Instruments profile pass is still TODO.

### 8. Keychain prompt-storm ✅

Shipped this session — three-part fix in `Type.Oh/Core/KeychainStore.swift`:
- **In-memory session cache.** Each provider's key is read from the keychain at most once per app launch; every subsequent read (including each AI generation) is served from RAM. Save and Delete invalidate the cache entry.
- **Non-prompting existence probe.** `KeychainStore.hasKey(for:)` uses `kSecReturnAttributes` (metadata only) — checking presence never triggers the password prompt.
- **Lazy reveal in UI.** `SettingsWindow.ProvidersTab` and `OnboardingWizard.ProviderStep` now show "Configured / Not set" using `hasKey`, with an explicit Reveal button that performs the prompting load on demand. Opening Settings or Setup is free of prompts.
- **Active-provider pre-warm on launch.** `AppDelegate` kicks `KeychainStore.prefetch(activeProvider)` off the main thread at startup so the once-per-session prompt happens at launch, not mid-generation.

Net effect: with "Always Allow" ticked, zero prompts ever. Without it, one prompt at app launch and one per provider only when the user explicitly Reveals or switches active provider.

### 9. Hotkey recorder — non-Cmd modifiers ignored ✅

Shipped this session — `HotkeyRecorderButton` was using NSButton's `keyDown`/`performKeyEquivalent` path, which only reliably fires for Cmd-modified events. Replaced with an `NSEvent.addLocalMonitorForEvents` monitor during recording so every key event is captured at the app level regardless of NSButton's routing.

### 10. Hotkey defaults app-wide ✅

Shipped — visible default hotkeys now consistently show `F13` for Dictate, `F14` for ReType, and `F15` for LazyPad across onboarding, About, and Settings. Reset Defaults restores all three defaults, including LazyPad's `F15`, instead of disabling it.

### 11. LLM prompt leakage cleanup ✅

Shipped — removed the brittle language-preservation policy sentence from the shared rewrite prompt and added `cleanTextAIOutput(_:)` for every provider (Apple on-device, Anthropic, OpenAI, Gemini). The sanitizer strips leaked policy lines before results reach the UI. Covered by `TextAIProviderTests`.

### 12. README + screenshots ✅

Shipped — refreshed `README.md` with current setup, workflows, hotkeys, translation notes, and screenshots from `screenshots/`.

### 13. Provider sidebar icons ✅

Shipped — LazyPad provider rows use the custom asset symbols `GPT`, `Claude`, and `Gemini`; Apple on-device uses the SF Symbol `apple.intelligence`.

---

## P3 — V2 backlog

- macOS 15+ backwards compatibility (Foundation Models unavailable → cloud fallback default).
- Action Extension (Services menu / right-click) — preserved in `CONTEXT.md §7`.
- Streaming AI responses in the result pane (token-by-token reveal).
- Per-provider model picker in Settings (Sonnet vs Haiku, GPT-4o vs 4o-mini, etc.).

---

## Open after 2026-05-12 round 3 (LazyPad polish round)

### + button reliability ✅

Shipped — `SettingsTabRoute.open(...) + AppDelegate.sendAction(showSettingsWindow:)` raced and sometimes silently no-op'd when the Settings scene wasn't realized yet. Now both `ScratchpadView` and `AIEditorPanel` use `@Environment(\.openSettings)` directly (the official SwiftUI action). The `openSettingsAt(_:)` helper sets the pending tab in UserDefaults *and* fires the live notification, so either path (fresh mount or already-open) lands on the right tab.

### Native-OS translation ✅ (TranslationSession integration)

Shipped — `Type.Oh/UI/NativeTranslationDriver.swift` is a hidden SwiftUI driver that bridges the imperative `TranslationDispatcher.translate(.nativeOS, ...)` call into the SwiftUI `.translationTask(_:)` API. `NativeTranslationCoordinator` (Observable singleton) parks a continuation while the driver runs `session.translate(text)`; a `generation` counter re-fires the task even when the configuration is byte-identical. Mounted as a 0×0 background overlay in both LazyPad (`ScratchpadView`) and ReType (`AIEditorPanel`). `TranslationDispatcher` signature now carries `Locale.Language` directly so the configuration can be constructed natively. Removed the `nativeNotYetImplemented` placeholder; added `nativeMissingLanguagePack` for the genuine "no installed pack" case.

### ReType styling parity with new LazyPad ✅

Shipped — `AIEditorPanel` rebuilt around LazyPad's visual idioms:
- Top toolbar with icon+label buttons (Fix / Style / Translate as mode pills, plus Paste / Copy on the right). The active mode lights up in the accent color (matching LazyPad's sidebar selection).
- Mode tabs removed in favor of toolbar mode buttons; the style chip row only appears when Style mode is active.
- Input rendered as a "card" (rounded rect, secondary tint, 1pt stroke) — identical chrome to LazyPad's editor frame. Result card uses the accent tint + accent stroke so it visually pops as the "applied" surface.
- Errors moved into a dedicated red-tinted banner (with the "API key missing" CTA buttons preserved).
- Status bar at the bottom mirrors LazyPad: character count + mode label on the left, provider + translation pair in the middle, status/error on the right.
- Translate language picker moved into a popover triggered from the toolbar (with right-click context menu for swap / reset to auto-detect, matching LazyPad).
- Native translation driver mounted as `.background()` (same pattern as LazyPad).

Toolbar primitive is duplicated locally (`toolbarButton(title:systemImage:isActive:)`) rather than extracted to `UI/Components/` — the two views' buttons diverge enough on active-state behavior that a shared abstraction would be premature. Revisit if a third surface needs the same chrome.
