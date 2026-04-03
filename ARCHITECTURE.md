# HushScribe — Architecture

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌───────────────┐
│  Microphone  │────▶│                  │     │               │
└─────────────┘     │  HushScribe      │     │  Obsidian     │
                    │  ┌────────────┐  │────▶│  Vault        │
┌─────────────┐     │  │ Parakeet   │  │     │  (.md files)  │
│  System      │────▶│  │ TDT v3    │  │     │               │
│  Audio       │     │  └────────────┘  │     └───────┬───────┘
└─────────────┘     └──────────────────┘             │
                                                     ▼
                                              ┌──────────────┐
                                              │  AI Agent    │
                                              │  Layer       │
                                              │  (notes,     │
                                              │   actions,   │
                                              │   updates)   │
                                              └──────────────┘
```

1. **Capture** picks up mic audio + system audio from a specific conferencing app via ScreenCaptureKit.
2. **Transcribe** runs VAD to detect speech segments, then Parakeet transcribes locally.
3. **Diarize** splits the system audio into individual speakers after the session ends.
4. **Write** drops structured `.md` with YAML frontmatter into your vault folder.
5. **Agent picks up** whatever you've got downstream processes the transcript.

## Architecture

```
Tome/Sources/Tome/
├── App/
│   └── HushScribeApp.swift             # App entry point, menu bar, app delegate
├── Audio/
│   ├── SystemAudioCapture.swift        # ScreenCaptureKit + per-app filtering
│   └── MicCapture.swift                # AVAudioEngine mic input
├── Models/
│   ├── Models.swift                    # Domain types (Utterance, Speaker, etc.)
│   └── TranscriptStore.swift           # Observable transcript state
├── Transcription/
│   ├── TranscriptionEngine.swift       # Dual-stream capture + diarization
│   └── StreamingTranscriber.swift      # VAD + Parakeet ASR pipeline
├── Storage/
│   ├── TranscriptLogger.swift          # .md output with YAML frontmatter
│   └── SessionStore.swift              # Session metadata
├── Settings/
│   └── AppSettings.swift
└── Views/
    ├── ContentView.swift
    ├── ControlBar.swift
    ├── TranscriptView.swift
    ├── WaveformView.swift
    ├── SettingsView.swift
    ├── OnboardingView.swift
    └── SpeakerNamingView.swift
```

## Build

**Requirements:** Apple Silicon Mac, macOS 26+, Xcode 26.3+

```bash
git clone git@github.com:drcursor/HushScribe.git
cd HushScribe
./scripts/build_swift_app.sh
```

Builds and installs to `/Applications`. First launch downloads the Parakeet ASR model (~600MB, cached after that).

**Dev build:**

```bash
cd HushScribe
swift build
```
