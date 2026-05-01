# Type.OH — Engineering Context

> Living engineering brief. Read this before changing architecture, adding a major feature, or onboarding a new contributor (human or AI). User-facing docs live in [README.md](README.md).

---

## 1. Origin & Goal

Type.OH started as a macOS **Action Extension** that would let users highlight text in any app, invoke it from the Services menu, and run AI operations on the selection (Translate / Improve / Suggest substitutions). The original PRD is preserved verbatim in §7 below.

The project then pivoted, for two reasons:

1. **Voice-to-text** was added to the product vision after seeing Yariv Gilad's open-source [Careless Whisper](https://github.com/YarivGilad/careless-whisper) — a tiny menu-bar app that records on a global hotkey, runs Whisper locally, and pastes the result into the focused app. The same plumbing (focus capture, accessibility paste, menu-bar lifecycle, settings store, global hotkeys) serves both voice and text-editing flows, so bundling them into a single app is cheaper than two.
2. **Action Extensions are heavyweight for v0.** Separate target, sandbox, code-signing, entitlements, IPC. We get the same UX (highlight text → invoke AI Editor) from a global hotkey + the Accessibility API. The Action Extension stays in the v2 backlog, not blocking MVP.

The result: **a single menu-bar macOS app, two flows, two hotkeys.**

---

## 2. Inspirations

### [Careless Whisper](https://github.com/YarivGilad/careless-whisper) (Yariv Gilad — Tauri + Rust)

The local source is mirrored under `docs/careless-whisper-main/` for offline reference. We are **not** copying the implementation — just borrowing the UX shape:

- Menu-bar / system-tray app, no Dock icon.
- Global hotkey toggles recording.
- Local Whisper inference (ggml/whisper.cpp in their stack; **WhisperKit** in ours).
- Captures the frontmost app *before* opening UI; re-activates it before pasting.
- Accessibility permission required; first-run flow opens System Settings to the right pane.

### Telegram bot — *AI Editor*

Screenshots in `docs/telegram_feature_screenshots/` define the **UX target for the text-editing panel**:

| File | Shows |
|---|---|
| `01_user_input.jpg` | Three top-level modes — Translate / Style / Fix — with style chips below. |
| `02_fix_typo.PNG` | "Fix" mode: Original / Result panes, mistakes underlined. |
| `03_style_Formal.PNG` | Style → Formal applied. |
| `04_style_Corp.PNG` | Style → Corp applied. |
| `05_translate_English.PNG` | From Hebrew → To English with language pickers. |
| `06_language_support.PNG` | Searchable language list. |
| `07_Emojify.jpg` | Emojify toggle augments the result. |

Our Style preset list is slimmed and renamed (Formal / Concise / Friendly / Corporate / **Pirate** 🏴‍☠️). The fun preset matters — it's the differentiator.

---

## 3. Why Native Swift (Not Tauri / Rust)

| Concern | Native Swift choice | Why over Tauri/Rust |
|---|---|---|
| Whisper inference | **WhisperKit** (Swift Package, MIT) | Core ML on the Neural Engine. One `import WhisperKit`. No whisper.cpp build, no Rust toolchain, no cross-compile. |
| Local LLM for Style/Fix | **Apple Foundation Models** (`LanguageModelSession`, macOS 26+) | Free, on-device, ~3B parameters, Neural Engine. No API key, no network, no cost. Tauri stack would have to ship a quantized model and a runtime. |
| Translation | **Apple Translation framework** (`TranslationSession`, macOS 15+) | Free, local. No equivalent in the Tauri ecosystem. |
| Menu bar / panels | `NSStatusItem` + `MenuBarExtra` + `NSPanel` (`.nonactivatingPanel`) | One-liners. No webview overhead. Doesn't steal focus from the source app — critical for AX selection + paste. |
| Global hotkeys | Carbon `RegisterEventHotKey` | Only reliable system-wide hotkey API on macOS. Tiny C-interop wrapper. |
| Read selection from any app | AX (`AXUIElementCopyAttributeValue` + `kAXSelectedTextAttribute`); fallback copy-via-⌘C | Same approach the Tauri app would need anyway. |
| Paste into focused app | `CGEvent` keyboard tap (⌘V) | Same as careless-whisper's `output/paste.rs`, but in Swift. |
| Settings persistence | `Codable` → JSON in `~/Library/Application Support/Type.OH/settings.json` | Same convention as careless-whisper. |
| Launch at login | `SMAppService.mainApp` | Modern API, no LaunchAgent plist. |

One project, one language, one Xcode. Faster to ship, lower binary size, lower memory.

---

## 4. Architecture

Single Xcode project, **one app target**, `LSUIElement = YES` (menu bar only, no Dock icon).

```
Type.OH (macOS app)
│
├── App lifecycle
│   ├── AppDelegate              # NSStatusItem, hotkey registration, panel lifecycle
│   └── SettingsStore            # @Observable, persists to ~/Library/Application Support/Type.OH/settings.json
│
├── Hotkey & focus
│   ├── HotkeyManager            # Carbon RegisterEventHotKey wrapper
│   └── FocusCapture             # NSWorkspace.frontmostApplication snapshot before opening UI
│
├── Voice flow (Whisper)
│   ├── AudioRecorder            # AVAudioEngine, 16 kHz mono f32, max-duration timer
│   ├── WhisperService           # WhisperKit wrapper (actor); model loaded once, swapped on settings change
│   ├── ModelManager             # download / list / activate Whisper models
│   └── RecordingOverlay         # small floating SwiftUI overlay (pulsing dot + timer) hosted in NSPanel
│
├── AI Editor flow (text)
│   ├── SelectionReader          # AX read; fallback copy-via-⌘C
│   ├── TranslationService       # Apple Translation framework
│   ├── TextAI/                  # Pluggable provider abstraction
│   │   ├── TextAIProvider       # protocol: improve(text) / applyStyle(text, style) / emojify(text)
│   │   ├── AppleOnDevice        # FoundationModels (DEFAULT — free, local)
│   │   ├── AnthropicProvider    # Claude Sonnet 4.6 / Haiku 4.5
│   │   ├── OpenAIProvider       # GPT-4o / 4o-mini
│   │   └── GoogleProvider       # Gemini 1.5/2.0 Flash
│   ├── StylePresets             # Formal/Concise/Friendly/Corporate/Pirate → prompt fragments
│   └── AIEditorPanel            # SwiftUI panel matching the Telegram screenshots:
│       ├── ModeTabs (Translate / Style / Fix)
│       ├── StyleChipRow
│       ├── LanguagePicker (Translate mode)
│       ├── EmojifyToggle
│       ├── Original / Result panes (DiffTextView for Fix mode)
│       └── Apply / Cancel buttons
│
├── Output
│   └── PasteService             # write to NSPasteboard, re-activate prior app, simulate ⌘V via CGEvent
│
└── Settings UI
    └── SettingsWindow           # SwiftUI: hotkeys, Whisper model, languages, provider + key, launch-at-login
```

---

## 5. File Layout (Xcode)

```
Type.OH.xcodeproj/
Type.OH/
├── Type_OHApp.swift                       # @main, MenuBarExtra, AppDelegate adapter
├── AppDelegate.swift                      # status item, hotkey wiring, panel windows
├── Info.plist                             # LSUIElement=YES, NSMicrophoneUsageDescription
├── Type.OH.entitlements                   # Hardened Runtime, network.client, audio-input
│
├── Core/
│   ├── SettingsStore.swift
│   ├── KeychainStore.swift                # provider API key storage (SecItemAdd / Copy / Delete)
│   ├── HotkeyManager.swift                # Carbon wrapper
│   ├── FocusCapture.swift                 # remembers frontmost app
│   └── PasteService.swift                 # ⌘V via CGEvent + clipboard write
│
├── Voice/
│   ├── AudioRecorder.swift                # AVAudioEngine → [Float] @ 16 kHz
│   ├── WhisperService.swift               # WhisperKit wrapper (actor)
│   └── ModelManager.swift
│
├── Editor/
│   ├── SelectionReader.swift              # AX read; fallback copy-via-⌘C
│   ├── TranslationService.swift           # Apple Translation framework
│   ├── TextAI/
│   │   ├── TextAIProvider.swift           # protocol + ProviderID enum + ProviderRegistry
│   │   ├── AppleOnDevice.swift            # FoundationModels (default)
│   │   ├── AnthropicProvider.swift
│   │   ├── OpenAIProvider.swift
│   │   └── GoogleProvider.swift
│   └── StylePresets.swift
│
├── UI/
│   ├── MenuBarContent.swift               # tray menu (Settings, Quit, status)
│   ├── RecordingOverlay.swift
│   ├── AIEditorPanel.swift
│   ├── ModeTabs.swift
│   ├── StyleChipRow.swift
│   ├── LanguagePicker.swift
│   ├── DiffTextView.swift                 # Fix mode "Original / Result" with strike-through
│   └── SettingsWindow.swift
│
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings
```

---

## 6. Decisions Locked In

- **Min OS**: macOS 26 Tahoe + Apple Silicon + Apple Intelligence. macOS 15 fallback is a v2 exploration once MVP works.
- **Default text AI**: Apple **Foundation Models** (on-device, free, no setup). First-run is local-first.
- **Optional cloud providers**: Anthropic, OpenAI, Google — and only those three (user trust constraint). User picks one in Settings, brings their own key.
- **Keychain for API keys**: `Security` framework, service `com.typeoh.<provider>`, account `apiKey`. Settings UI shows masked "•••• last 4" with Set / Clear buttons per provider.
- **Style presets** (5, slim, one fun): **Formal** 🤝, **Concise** ✂️, **Friendly** 😊, **Corporate** 💼, **Pirate** 🏴‍☠️. Defined in `StylePresets.swift` as `(id, label, emoji, promptFragment)` tuples — adding more is a one-liner.
- **Default hotkeys**: voice = `⌃ F13`, AI Editor = `⌥ F13`. Both reconfigurable in Settings via a hotkey-recorder field.
- **Emojify**: a toggle that augments any Style/Fix prompt (matches Telegram screenshots).
- **Whisper for style**: not viable. Whisper is speech→text only; its "translate" mode is hardcoded audio→English. Voice and text rewriting stay in separate lanes.

### Permissions

| Permission | Where declared | Purpose |
|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` in Info.plist | Voice recording. macOS prompts on first `AVAudioEngine` start. |
| Accessibility | **User-granted in System Settings** — cannot be declared | Read selected text + simulate ⌘V. Detect via `AXIsProcessTrusted()`; open the right pane on first run via `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. |
| Network client | `com.apple.security.network.client` entitlement | Cloud provider calls + first-time WhisperKit model download. |

---

## 7. Original Action Extension PRD (historical / v2 backlog)

Preserved verbatim from the project's first README. The Action Extension is **out of scope for v0.1** but on the v2 backlog — when we add it, this is the spec.

> ### Project Specification: macOS AI Text Assistant Service
>
> #### Overview
> A native macOS application and Action Extension that allows users to highlight text in *any* macOS application, right-click (or use a shortcut), and process the text using local and cloud AI. The app provides three main features: Translate, Improve Message, and Suggest Substitutions. Once processed, the app replaces the original highlighted text with the new text.
>
> #### Tech Stack
> * **Platform:** macOS 15.0+ (Mandatory for native Translation framework)
> * **Language:** Swift 6
> * **UI Framework:** SwiftUI
> * **Extension Type:** macOS Action Extension (`NSExtensionPointIdentifier`: `com.apple.services`)
> * **Local ML:** Apple `Translation` Framework (`TranslationSession`)
> * **Cloud AI:** Google Gemini API (using the official `GoogleGenAI` Swift SDK)
>
> #### Core Requirements & Constraints
>
> ##### 1. Action Extension Configuration (`Info.plist`)
> * The extension must only activate when text is selected.
> * Configure `NSExtensionAttributes` → `NSExtensionActivationRule` to explicitly require `NSPasteboard.PasteboardType.string`.
> * The service should accept text and return text.
>
> ##### 2. The User Interface (SwiftUI)
> * The extension must present a clean, floating SwiftUI View (not a massive window).
> * **State 1:** Loading/Processing indicator.
> * **State 2:** Results View showing:
>   * A segmented control or tab view to switch between: "Translate", "Improve", and "Substitutions".
>   * A text editor showing the preview of the processed text.
>   * A "Replace" button to commit the changes and close the extension.
>   * A "Cancel" button to dismiss without changes.
>
> ##### 3. Local Translation (Cost-Saving)
> * Must use Apple's native `Translation` framework introduced in macOS 15.
> * Implement a programmatic translation flow without forcing the default Apple UI, using `TranslationSession` to translate the inputted string to the user's preferred language.
>
> ##### 4. Cloud AI (Gemini 1.5 Flash)
> * Use the Gemini API to process the text for improvements and substitutions.
> * Use the `gemini-1.5-flash` model.
> * **System Prompt Requirement:** The AI must return structured JSON.
>   ```json
>   {
>     "improved_version": "The fully corrected and improved text.",
>     "substitutions": [
>       {
>         "original_word": "bad phrasing",
>         "options": ["poor phrasing", "suboptimal wording"]
>       }
>     ]
>   }
>   ```
>
> ##### 5. Text Replacement Logic
> * When the user clicks "Replace", the SwiftUI view must pass the final string back to the `ActionRequestHandler` (the `NSExtensionContext`).
> * Use `NSItemProvider` to load the new string into the `NSExtensionItem` and call `completeRequest(returningItems:completionHandler:)` so the host app replaces the text.
>
> #### Implementation Steps (For the AI Agent)
> 1. **Setup & Config:** Create the Xcode project, add the Action Extension target, and configure the `Info.plist` for text-only activation.
> 2. **Action Request Handler:** Write the Swift code to extract the highlighted `String` from the `NSExtensionContext`.
> 3. **SwiftUI UI:** Build the floating interface with the options, preview area, and Replace/Cancel buttons. Include a bridging layer (`NSViewController` to SwiftUI).
> 4. **Local Translation:** Implement a `TranslationService.swift` using Apple's macOS 15 Translation API.
> 5. **Gemini API Integration:** Implement a `GeminiService.swift` to handle the API call, pass the JSON system prompt, and decode the response.
> 6. **Return Data:** Implement the logic to pass the newly formatted text back to the host app and terminate the extension gracefully.

---

## 8. Verification (MVP done-when)

1. **Build & launch** — ⌘R from Xcode. App appears in menu bar; no Dock icon.
2. **Voice path** — open TextEdit, click in a document, press `⌃F13`, speak a sentence, press `⌃F13` again. Transcript appears at the cursor inside TextEdit.
3. **AI Editor — Fix** — type a sentence with typos in TextEdit, select it, press `⌥F13`. Panel opens with the original; tap **Fix**, see corrected result; tap **Apply**; selected text in TextEdit is replaced.
4. **AI Editor — Style → Pirate** — repeat with a casual sentence; pick `Style → Pirate`; Apply (gut-check the fun preset).
5. **AI Editor — Translate** — select Hebrew text, press `⌥F13`, choose `Translate → English`. (First run downloads the Apple Translation language pack — that's expected.)
6. **Permissions** — first launch with Accessibility disabled should open System Settings to the right pane and show an in-app banner.
7. **Background** — close all visible windows; the app keeps running in the menu bar; hotkeys still work.
8. **Settings persistence** — change the hotkey, quit, relaunch, confirm new hotkey is active.
9. **Provider switch** — add an Anthropic key in Settings, switch provider to Anthropic, run Style → Pirate again; verify result came from Claude (longer / different style than the on-device model).

Performance targets:

- 30 s clip transcribed by Whisper `base` in < 10 s on Apple Silicon.
- Foundation Models Style/Fix response in < 3 s for a single paragraph.
- Idle memory < 300 MB excluding the loaded Whisper model.

---

## 9. Out of Scope for MVP (post-v0.1 backlog)

- **Action Extension target** (Services menu / right-click) — see §7.
- macOS 15 fallback (Writing Tools or required cloud provider when Foundation Models unavailable).
- Transcription history.
- Per-app profiles (different model / language by frontmost app).
- Streaming partial transcription.
- Custom user-defined Style presets.
- Windows / Linux support.
- App Store distribution + notarization (ad-hoc signing is fine for v0).

---

## 10. Building Now — First Steps in Xcode

The Xcode project itself doesn't exist yet. Bootstrap from Xcode (`File → New → Project → macOS → App`):

- Product Name: `Type.OH`
- Interface: SwiftUI · Language: Swift · Storage: None · Tests: optional
- Once created, set **Deployment Target: macOS 26.0**, set **`LSUIElement` = YES** in Info.plist, and add the entitlements above.
- Add Swift Packages:
  - `https://github.com/argmaxinc/WhisperKit`
- Create the folder structure from §5 inside the `Type.OH/` group.

After that, implementation order (matches `careless-whisper`'s phased plan, adapted):

1. `SettingsStore` + `KeychainStore` (Phase 1)
2. `HotkeyManager` + `FocusCapture` + `PasteService` (Phase 2 — shared plumbing)
3. `MenuBarContent` + minimal `SettingsWindow` (Phase 3 — visible app)
4. **Voice flow**: `AudioRecorder` → `WhisperService` → `ModelManager` → `RecordingOverlay` (Phase 4)
5. **Text flow**: `SelectionReader` → `TranslationService` → `AppleOnDevice` provider → `AIEditorPanel` (Phase 5)
6. Cloud providers + provider picker in Settings (Phase 6)
7. Polish: launch-at-login, first-run permission flow, model-download UI (Phase 7)
