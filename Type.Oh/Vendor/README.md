# Vendored dependencies

Needed to build Type.OH on macOS 13 with a swift.org toolchain (no Xcode).

- `WhisperKit/` — argmaxinc/WhisperKit **v0.10.1** (MIT), `Sources/` only.
  Newest release that compiles against the macOS 13.3 SDK; later releases use
  `MLState` (macOS 15). `Package.swift` points at the local swift-transformers
  and the CLI target was dropped.
- `swift-transformers/` — huggingface/swift-transformers **v0.1.8** (Apache-2.0),
  `Sources/` only. One patch: `Sources/Models/LanguageModelTypes.swift`
  `generate(config:prompt:callback:)` uses an explicit closure instead of a
  method reference, which crashes swift.org 5.10/6.0 compilers ("Found ownership
  error"). Behaviour is identical.

WhisperKit patches for the macOS 13.3 SDK (all no-ops at runtime on macOS 13):
- `Core/Text/TokenSampler.swift`, `Core/Utils/Utils.swift`: the `MLTensor`
  sampling path (macOS 15) is compiled out (`#if TYPEOH_SDK_HAS_MLTENSOR`); the
  BNNS path is used, which is what runs on macOS 13/14 anyway.
- `Core/Audio/AudioProcessor.swift`: `AVAudioApplication.requestRecordPermission`
  (macOS 14 SDK) replaced by the existing `AVCaptureDevice` fallback.

Intel (x86_64) patch in WhisperKit (`Core/Utils/Utils.swift`, `Core/TextDecoder.swift`):
WhisperKit's `FloatType` is `Float` on x86_64 (Swift has no `Float16` there)
but it created float16 arrays and wrote `Float`s into them — a 2× buffer
overrun that crashed every transcription on Intel. Now `initMLMultiArray`
creates float32 arrays on x86_64 (`whisperFloatArrayType`), Core ML converts
them to the models' float16 inputs, and float16 outputs (logits, KV-cache
updates, alignment weights, prefill caches) are converted back with
`MLMultiArray.toFloatTypeArray()` (vImage half→float, stride-aware). Setting
`WHISPERKIT_VERIFY_F16=1` in the environment logs a per-array self-check.
No-ops on Apple Silicon.

Compute units on Intel (set by the app in `WhisperService`): mel + encoder on
`.cpuAndGPU`, decoder on `.cpuOnly`. The decoder produces garbage on the Intel
GPU, and Core ML's pure-CPU path crashes (SIGFPE in Espresso) on the mel model.
