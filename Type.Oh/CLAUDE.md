# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Type.OH** (also called iLazyKey) is a native macOS menu-bar app with two flows triggered by global hotkeys:

1. **Voice → Text** (`⌃F13`): Record speech → transcribe locally via WhisperKit → paste at cursor.
2. **AI Editor** (`⌥F13`): Select text in any app → floating panel → Translate / Style / Fix → replace in place.

Everything runs locally by default (WhisperKit on Neural Engine, Apple Foundation Models, Apple Translation). Optionally, users bring their own Anthropic / OpenAI / Google API key stored in the macOS Keychain.

## Requirements

- **macOS 26 Tahoe+**, **Apple Silicon**, **Apple Intelligence enabled** (required for Foundation Models)
- **Xcode 17+**
- Swift Package: `https://github.com/argmaxinc/WhisperKit`

## Build & Run

Open the project in Xcode and run:

```
# Open project
open Type.Oh.xcodeproj

# Build & run from Xcode: select Type.OH scheme → ⌘R
```

The app has `LSUIElement = YES` — no Dock icon, lives only in the menu bar.

## Architecture

Single app target. Key components by folder:

### `Core/`
- `SettingsStore.swift` — `@Observable`, persists to `~/Library/Application Support/Type.OH/settings.json`
- `KeychainStore.swift` — API key storage via `Security` framework (`com.typeoh.<provider>` / `apiKey`)
- `HotkeyManager.swift` — Carbon `RegisterEventHotKey` wrapper (only reliable global hotkey API on macOS)
- `FocusCapture.swift` — snapshots `NSWorkspace.frontmostApplication` *before* any UI opens (critical: must be captured before panels steal focus)
- `PasteService.swift` — writes to `NSPasteboard`, re-activates prior app, simulates `⌘V` via `CGEvent`

### `Voice/`
- `AudioRecorder.swift` — `AVAudioEngine`, 16 kHz mono f32, max-duration timer
- `WhisperService.swift` — `actor` wrapping WhisperKit; model loaded once, swapped on settings change
- `ModelManager.swift` — download/list/activate Whisper models (stored in `~/Library/Application Support/Type.OH/models/`)

### `Editor/`
- `SelectionReader.swift` — reads selected text via AX (`kAXSelectedTextAttribute`); fallback: copy-via-`⌘C`
- `TranslationService.swift` — Apple `TranslationSession` (local, free)
- `TextAI/TextAIProvider.swift` — protocol `improve(text:)` / `applyStyle(text:style:)` / `emojify(text:)` + `ProviderID` enum + `ProviderRegistry`
- `TextAI/AppleOnDevice.swift` — **default provider**, uses `FoundationModels` (`LanguageModelSession`)
- `TextAI/AnthropicProvider.swift` — Claude Sonnet 4.6 / Haiku 4.5
- `TextAI/OpenAIProvider.swift` — GPT-4o / 4o-mini
- `TextAI/GoogleProvider.swift` — Gemini 1.5/2.0 Flash
- `StylePresets.swift` — 5 presets as `(id, label, emoji, promptFragment)` tuples: Formal 🤝, Concise ✂️, Friendly 😊, Corporate 💼, Pirate 🏴‍☠️

### `UI/`
- `MenuBarContent.swift` — tray menu
- `RecordingOverlay.swift` — pulsing dot + timer in a non-activating `NSPanel`
- `AIEditorPanel.swift` — main editor: `ModeTabs` (Translate/Style/Fix) → `StyleChipRow` / `LanguagePicker` / `EmojifyToggle` / `DiffTextView` → Apply/Cancel
- `DiffTextView.swift` — Fix mode diff (original with strikethrough / result)
- `SettingsWindow.swift` — hotkeys, Whisper model download, language, provider + masked key display

### App Entry
- `Type_OhApp.swift` — `@main`, `MenuBarExtra`, AppDelegate adapter
- `AppDelegate.swift` — `NSStatusItem`, hotkey wiring, panel window lifecycle

## Critical Architectural Decisions

- **Focus must be captured before any UI opens.** `FocusCapture` must snapshot the frontmost app in the hotkey handler, before any panel becomes key.
- **`TextAIProvider` is the extension point for cloud providers.** Adding a new provider = new file conforming to the protocol + one entry in `ProviderRegistry`.
- **Accessibility permission cannot be requested programmatically** — detect via `AXIsProcessTrusted()`, open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` on first run.
- **`FoundationModels` requires macOS 26 + Apple Intelligence.** There is no macOS 15 fallback in v0.1 — that's a post-MVP exploration.
- **Whisper `translate` mode is audio→English only** — it cannot rewrite text. Voice and text-editing are strictly separate pipelines.
- **Action Extension (Services menu / right-click) is v2 backlog**, not MVP. The original PRD for it is preserved in `CONTEXT.md §7`.

## Entitlements Required

- `com.apple.security.network.client` — cloud providers + WhisperKit model download
- `NSMicrophoneUsageDescription` in Info.plist — voice recording

## MVP Verification Checklist

See `CONTEXT.md §8` for the full done-when list. Performance targets:
- Whisper `base`: 30 s clip transcribed < 10 s on Apple Silicon
- Foundation Models Style/Fix: < 3 s for a single paragraph
- Idle memory: < 300 MB (excluding loaded Whisper model)

## Reference Docs

- `CONTEXT.md` — full engineering brief, architecture rationale, locked decisions, and original Action Extension PRD (v2 backlog)
- `README.md` — user-facing install/usage docs and Whisper model table
- `docs/careless-whisper-main/` — offline mirror of the Tauri/Rust app that inspired the voice flow UX
- `docs/telegram_feature_screenshots/` — UX target screenshots for the AI Editor panel
