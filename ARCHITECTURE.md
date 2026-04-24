# HushScribe — Architecture

## How It Works

```
┌─────────────┐     ┌──────────────────────────────┐     ┌───────────────┐
│  Microphone  │────▶│                              │     │               │
└─────────────┘     │  HushScribe                  │     │  Obsidian     │
                    │  ┌──────────┐  ┌───────────┐ │────▶│  Vault        │
┌─────────────┐     │  │ ASR      │  │ AI Summary│ │     │  (.md files)  │
│  System      │────▶│  │ (local)  │  │ (local)   │ │     │               │
│  Audio       │     │  └──────────┘  └───────────┘ │     └───────────────┘
└─────────────┘     └──────────────────────────────┘
```

1. **Capture** picks up mic audio + system audio from a specific conferencing app via ScreenCaptureKit.
2. **Transcribe** runs VAD to detect speech segments, then the selected ASR model transcribes locally (Parakeet, WhisperKit, or Apple Speech).
3. **Diarize** splits system audio into individual speakers after the session ends.
4. **Write** drops structured `.md` with YAML frontmatter into your vault folder.
5. **Summarise** (optional) — open any transcript in the Transcript Viewer and generate Highlights + To-Dos on-device via Qwen3, Gemma 3, or Apple NL.

## Source Tree

```
HushScribe/Sources/HushScribe/
├── App/
│   └── HushScribeApp.swift             # App entry point, menu bar setup
├── Audio/
│   ├── MicCapture.swift                # AVAudioEngine mic input
│   └── SystemAudioCapture.swift        # ScreenCaptureKit + per-app filtering
├── Models/
│   ├── Models.swift                    # Domain types (Utterance, Speaker, etc.)
│   ├── RecordingState.swift            # Session state enum
│   ├── SummaryModel.swift              # LLM model list and HuggingFace IDs
│   └── TranscriptStore.swift           # Observable live transcript state
├── Services/
│   ├── LLMSummaryEngine.swift          # MLX-based on-device LLM inference
│   ├── MeetingMonitor.swift            # Auto-detect meeting apps + mic activity
│   └── SummaryService.swift            # Apple NL extractive summarisation
├── Settings/
│   └── AppSettings.swift               # UserDefaults-backed app configuration
├── Storage/
│   ├── SessionStore.swift              # Session metadata
│   └── TranscriptLogger.swift          # .md output with YAML frontmatter
├── Transcription/
│   ├── ASRBackend.swift                # ASR protocol shared by all backends
│   ├── SFSpeechBackend.swift           # Apple Speech (SFSpeechRecognizer)
│   ├── StreamingTranscriber.swift      # VAD + ASR pipeline per audio stream
│   ├── TranscriptionEngine.swift       # Dual-stream orchestration + lifecycle
│   └── WhisperKitBackend.swift         # WhisperKit ASR backend
└── Views/
    ├── ContentView.swift               # Main window (record controls + live transcript)
    ├── ControlBar.swift                # Record / pause / stop bar
    ├── OnboardingView.swift            # First-launch wizard
    ├── SettingsView.swift              # Settings window (tabbed)
    ├── SpeakerNamingView.swift         # Post-session speaker name assignment
    ├── SummarizeView.swift             # Transcript viewer + AI summary
    ├── TranscriptView.swift            # Live transcript bubbles
    └── WaveformView.swift              # Dual VU meters
```

## Key Data Flow

- `TranscriptionEngine` owns `MicCapture` and `SystemAudioCapture`. Each stream feeds a `StreamingTranscriber` which pipes audio through `VadManager` (FluidAudio) then the selected `ASRBackend`.
- Final utterances land in `TranscriptStore` as `Utterance` values; partial results are written to `volatileYouText` / `volatileThemText` for live display.
- `TranscriptLogger` writes the `.md` file on session stop. Post-session diarization runs via `OfflineDiarizerManager` (FluidAudio) and re-labels system audio speakers.
- `LLMSummaryEngine` loads MLX models on demand (cached in `~/Library/Caches/models/`). `SummarizeView` calls it with the transcript text and receives `(summary, thinking)`.

## Scripts

All scripts live in `scripts/` and are run from the **repository root**.

### `scripts/bump_version.sh`

Bumps `CFBundleShortVersionString` and `CFBundleVersion` in `HushScribe/Sources/HushScribe/Info.plist`.

```bash
scripts/bump_version.sh patch    # 3.5.0 → 3.5.1
scripts/bump_version.sh minor    # 3.5.0 → 3.6.0
scripts/bump_version.sh major    # 3.5.0 → 4.0.0
scripts/bump_version.sh 3.5.2    # explicit version
```

### `scripts/release.sh`

Full release pipeline. Requires a valid Developer ID certificate and a stored `notarytool` keychain profile named `HushScribe`.

Steps:
1. `swift build -c release` inside `HushScribe/`
2. Compile MLX Metal shaders into `mlx.metallib`
3. Assemble `dist/HushScribe.app` (binary, metallib, icon, logo, Info.plist)
4. Deep-sign all dylibs, frameworks, and the bundle with hardened runtime
5. Create and sign `dist/HushScribe.dmg`
6. Notarize and staple (skipped with the `test` argument)
7. Create GitHub release; body pulled from the matching `CHANGELOG.md` entry
8. Update `Casks/hushscribe.rb` with the new version and SHA-256, then `git push`

**Local test run** (skips notarization and GitHub release):
```bash
scripts/release.sh test
```

To rebuild and relaunch without resetting preferences:
```bash
rm dist/HushScribe.app/Contents/MacOS/HushScribe
scripts/release.sh test
dist/HushScribe.app/Contents/MacOS/HushScribe
```

To also reset all stored preferences:
```bash
defaults delete com.drcursor.hushscribe
```

### `scripts/test.sh`

Convenience one-liner used during development: rebuilds the release binary, wipes preferences, and relaunches the app from `dist/`. Not a test suite.

## Build

**Requirements:** Apple Silicon Mac, macOS 26+, Xcode 26.3+

**Release build** — produces a signed, notarized `dist/HushScribe.dmg` and creates a GitHub release:
```bash
git clone git@github.com:drcursor/HushScribe.git
cd HushScribe
scripts/release.sh
```

**Local test build** — builds and packages without notarizing or publishing:
```bash
scripts/release.sh test
```

**Dev build** — fast iteration, no packaging:
```bash
cd HushScribe && swift build
```

**Bump version before releasing:**
```bash
scripts/bump_version.sh minor   # or patch / major / x.y.z
```

First launch downloads the Parakeet ASR model (~600 MB, cached after that). LLM summary models are downloaded separately in Settings → Models.

## Dependencies

| Library | Purpose |
|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet-TDT v3 ASR, Silero VAD, offline diarization |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Whisper Base / Large v3 ASR on Apple Silicon |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | On-device LLM inference (Qwen3, Gemma 3) via MLX |
