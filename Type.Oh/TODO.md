# TODO — next session

Items are ordered by urgency. Each one names the most likely files to touch and a recommended Claude model.

> **Model legend.** Opus 4.7 = best for architecture and ambiguous multi-file work. Sonnet 4.6 = solid default for focused implementation/debug. Haiku 4.5 = fast and cheap for small mechanical edits.

Previous sessions: menu redesign, dock toggle, toast errors, API-key fix, AX read-via-copy reliability, lang-pack prep, generation-themed style presets, app icon + onboarding polish, **LazyPad workspace + provider sidebar (`f36ef79`)**.

---

## P0 — Blockers from live testing (2026-05-12)

### 1. LazyPad: typing lag + overwrite during fast input

**Symptom (reported):** Autocomplete is laggy and *sometimes overwrites text while the user is typing*. After a few lines / a paragraph, the input window "goes crazy" — characters disappear or shift and the change can't be reverted.

**Root cause:** `Type.Oh/UI/NativeTextView.swift::updateNSView` does:

```swift
if textView.string != text {
    textView.string = text
    ...
}
```

SwiftUI re-renders are async, so during fast typing the `text` binding can lag behind `textView.string` (the user has typed more chars than SwiftUI has propagated). When `updateNSView` runs it sees a "mismatch" and destructively re-assigns `textView.string = text` — clobbering in-flight keystrokes, IME composition, and undo history.

**Fix:** Convert this to a one-way data flow:
- Add a `programmaticUpdateInProgress` flag (or seq-no) on the coordinator/controller.
- Only push from SwiftUI → NSTextView when the change *originated outside the text view* (e.g. AI replace via `NativeTextViewController.replaceCharacters`, or `Clear` action). User keystrokes propagate the *other* way only.
- Use `textStorage.replaceCharacters(in:with:)` + `shouldChangeText` for programmatic updates so undo and selection are preserved.

**Files:** `Type.Oh/UI/NativeTextView.swift`, `Type.Oh/UI/ScratchpadView.swift`.
**Model: Opus 4.7.**

### 2. LazyPad: long text becomes unrevertable

Same root cause as #1 — once `textView.string =` runs, the undo stack is dropped and the scroll/selection state is reset. After #1 lands, manually verify:

- Undo (⌘Z) restores characters after AI replace.
- Scroll position stays anchored during AI rewrite.
- IME composition (CJK / dead-keys) isn't interrupted by SwiftUI re-renders.

**Files:** same as #1.
**Model: Sonnet 4.6.**

### 3. ReType crashes on uneditable selection — should fall through to LazyPad

**Symptom:** Invoking ReType while text is selected in a *non-editable* surface (web view static text, PDF, image OCR, etc.) crashes the app.

**Likely causes:**
- `SelectionReader.readViaAX` has `let focused = focusedRef as! AXUIElement` — force cast traps if AX returns an unexpected type.
- After the ReType panel applies its result, `PasteService.paste` posts ⌘V into a target that has no editable focus — paste may silently fail, but the bigger UX bug is that the user can't *use* the rewrite.

**Fix:**
1. Replace the force-cast with a safe cast that returns `nil` (no crash on edge cases).
2. Detect uneditability at capture time: check `AXUIElementIsAttributeSettable(focused, kAXSelectedTextAttribute)` (or fall back to "no AX selection, but clipboard copy produced text"). When uneditable, route the selection to **LazyPad** with the text pre-loaded instead of opening the ReType compact panel.
3. Same routing also applies to "no editable focus at all" — LazyPad becomes the safe landing pad.

**Files:** `Type.Oh/Editor/SelectionReader.swift`, `Type.Oh/AppDelegate.swift`, possibly add a helper to `Core/FocusCapture.swift`.
**Model: Opus 4.7.**

---

## P1 — Translation UX

### 4. Translate panel feels like a system menu, not a feature

**Symptom (reported):** "Translation function needs improvements in the UI scope."

**Current state:**
- `LanguagePicker` is two NSMenu buttons → flat list of *every* locale identifier, no search.
- In `AIEditorPanel` it sits awkwardly under the mode tabs.
- In `ScratchpadView` it's behind a popover where the action button can clip below the screen on smaller displays.

**Fix:**
- Searchable language picker with a TextField filter on top.
- "Recent languages" row above the full list (persist 3–5 most-used in `SettingsStore`).
- Swap-source/target arrow button between the two pickers.
- Inline translation strip in ReType (chip-style, like style presets), not a popover.
- LazyPad popover: make the language picker the *primary* surface, action button sticky at the bottom.

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

### ReType styling parity with new LazyPad

ReType (`AIEditorPanel`) still uses the old compact-panel look. Mirror LazyPad's chrome: roomier spacing, inline translate (already done), match status-bar accent, possibly a slim sidebar for style chips. Decide whether to share the sidebar/toolbar primitives between the two views.
- **Files:** `Type.Oh/UI/AIEditorPanel.swift`, possibly extract shared sidebar/toolbar into `UI/Components/`.
- **Model: Sonnet 4.6.**

### Google Translate without API key

User asked about a no-API Google Translate fallback. The only viable approach without an API key is scraping the free web endpoint, which is brittle (rate limits, terms of service, CAPTCHA exposure). Skip for now and surface DeepL Free as a cleaner alternative if budget allows.
- **Model: Opus 4.7** when revisited — needs reliability research and ToS review first.

### Cloud-provider model picker

Users currently can't pick Claude Haiku vs Sonnet, GPT-4o-mini vs 4o, etc. Add `selectedModel: [ProviderID: String]` to `SettingsStore` and a picker per provider in Settings → Providers. Wire through each provider's request builder.
- **Files:** `SettingsStore.swift`, `Editor/TextAI/*.swift`, `SettingsWindow.swift`.
- **Model: Sonnet 4.6.**
