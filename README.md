# Type.OH / iLazyKey (alternative name)

A native macOS menu-bar app that does two things, both with a single hotkey:

1. **Voice → Text** — press a hotkey, speak, the transcribed text is pasted where your cursor was. Runs **locally** with OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit) on the Apple Neural Engine. No audio leaves your machine.
2. **AI Editor** — highlight text in any app, press a second hotkey, a floating panel opens. **Translate**, **Style** (Formal, Concise, Friendly, Corporate, Pirate 🏴‍☠️), or **Fix** (typos, grammar). Hit Apply — the selected text is replaced in place.

Everything runs **locally and free** by default:

- **Voice** → OpenAI Whisper via WhisperKit on the Neural Engine.
- **Translate** → Apple's on-device Translation framework.
- **Style / Fix** → Apple Intelligence's on-device language model via the **Foundation Models framework** (macOS 26 Tahoe).

Optionally, bring your own API key for **Anthropic Claude**, **OpenAI**, or **Google Gemini** if you want a heavier cloud model for Style / Fix. Keys are stored in the macOS Keychain. No telemetry. No third parties beyond the provider you choose.

> The app has no Dock icon — it lives in the **menu bar** (top-right of your screen).

---

## Install

1. Download the latest `.dmg` from the [Releases](#) page.
2. Drag **Type.OH** to **Applications**.
3. Launch from Applications or Spotlight.

### "Type.OH is damaged and can't be opened"

Standard macOS warning for apps not signed with a paid Apple Developer certificate. One-time fix in Terminal:

```sh
xattr -cr "/Applications/Type.OH.app"
```

### First launch

The Settings window opens automatically.

1. **Pick a Whisper model** and click Download (start with `base` — ~142 MB, fast).
2. **Style / Fix** works out-of-the-box on Apple Silicon Macs with Apple Intelligence enabled — no API key needed. Optionally add an Anthropic / OpenAI / Google key in **Settings → Provider** to use a cloud model instead.
3. macOS will ask for **Microphone** access the first time you record — allow it.
4. Open **System Settings → Privacy & Security → Accessibility** and enable **Type.OH**. This is required so the app can read your selected text and paste results back into other apps.

---

## Default Hotkeys

| Action | Hotkey |
|---|---|
| Start / stop voice recording | `⌃ F13` |
| Open AI Editor on selected text | `⌥ F13` |

Both are configurable in Settings.

## Whisper Models

| Model | Size | Speed | RAM & Hardware Notes |
|---|---|---|---|
| tiny | ~75 MB | Fastest | ~200MB RAM. Recommended for MacBook Air 8GB RAM. |
| base | ~142 MB | Fast | ~400MB RAM. Default; snappy on any Apple Silicon Mac. |
| small | ~466 MB | Moderate | ~1GB RAM. Good balance of speed and accuracy. |
| medium | ~1.5 GB | Slow | ~2.5GB RAM. 16GB RAM recommended. |
| large-v3 | ~3 GB | Slowest | ~5GB RAM. Most accurate; 16GB+ RAM. M Pro/Max/Ultra recommended for decent speeds. |

Models are downloaded from Hugging Face and stored in `~/Library/Application Support/Type.OH/models/`.

## Permissions

- **Microphone** — voice recording
- **Accessibility** — read selected text + paste results into other apps

---

## Building from Source

<details>
<summary>For developers who want to build the app themselves</summary>

### Prerequisites

- **macOS 26 Tahoe or later** (required for the Foundation Models framework — the on-device LLM that powers Style / Fix)
- **Apple Silicon** (M1 or later) with **Apple Intelligence enabled**
- **Xcode 17** or later

### Build

```sh
git clone https://github.com/<you>/Type.OH.git
cd Type.OH
open Type.OH.xcodeproj
```

In Xcode: select the `Type.OH` scheme → ⌘R to run.

### Tech Stack

- **Swift 6 + SwiftUI**
- **WhisperKit** — local Whisper inference via Core ML on the Neural Engine
- **Apple Foundation Models** (`FoundationModels`) — on-device LLM for Style / Fix
- **Apple Translation framework** — local, on-device translation
- **Pluggable cloud providers** (optional, BYOK in Keychain) — Anthropic, OpenAI, Google behind a `TextAIProvider` protocol
- **AVAudioEngine** — mic capture
- **Carbon `RegisterEventHotKey`** — global hotkeys
- **AX API + `CGEvent`** — read selection / simulate paste

### Project Structure

```
Type.OH/
├── Core/         # Settings, hotkeys, focus capture, paste
├── Voice/        # AudioRecorder, WhisperService, ModelManager
├── Editor/       # SelectionReader, TranslationService, TextAI providers, StylePresets
├── UI/           # MenuBar, RecordingOverlay, AIEditorPanel, SettingsWindow
└── Resources/
```

See [CONTEXT.md](CONTEXT.md) for the full engineering brief, architecture, and the original Action Extension PRD that this project pivoted from.

</details>
