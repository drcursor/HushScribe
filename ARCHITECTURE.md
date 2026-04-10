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

## Build

**Requirements:** Apple Silicon Mac, macOS 26+, Xcode 26.3+

```bash
git clone git@github.com:drcursor/HushScribe.git
cd HushScribe
./scripts/release.sh test
```

Builds, signs, and packages to `dist/HushScribe.dmg`. First launch downloads the Parakeet ASR model (~600 MB, cached after that). LLM summary models are downloaded separately in Settings → Models.

**Dev build:**

```bash
cd HushScribe
swift build
```

## Dependencies

| Library | Purpose |
|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Parakeet-TDT v3 ASR, Silero VAD, offline diarization |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | Whisper Base / Large v3 ASR on Apple Silicon |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | On-device LLM inference (Qwen3, Gemma 3) via MLX |
