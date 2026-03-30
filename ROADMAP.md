# Roadmap

## Shipped

**Multilingual transcription (v1.1.0)**
Upgraded from Parakeet-TDT v2 (English-only) to v3 (25 European languages). Auto-detects spoken language.

**FluidAudio upgrade (v1.1.1)**
Upgraded to latest FluidAudio with actor-based `AsrManager`. Fixes Swift 6 build failures on Xcode 26.4+.

## Up next

**Custom vocabulary boosting**
Decode-time vocabulary biasing via CTC keyword spotting. Feed a text file of domain-specific terms and the transcriber prioritizes those words. No retraining needed.

**Per-stream model instances**
Create separate `AsrManager`/`VadManager` per audio stream to eliminate shared state across concurrent tasks.

**JSONL crash recovery**
Rebuild transcripts from session data if the app exits mid-session.
