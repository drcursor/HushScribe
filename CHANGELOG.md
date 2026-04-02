# Changelog

> **Fork note:** HushScribe is a fork of [Tome](https://github.com/Gremble-io/Tome) by [Gremble-io](https://github.com/Gremble-io). Changes merged from the upstream Tome repository are marked with `[upstream]` in this changelog.

## [1.2.3] — 2026-04-02 (HushScribe rebrand)
- Renamed project to HushScribe (fork of Tome by Gremble-io)
- Replaced all user-visible references to Tome and gremble with HushScribe and drcursor
- Updated bundle ID to `com.drcursor.hushscribe`
- Updated default vault paths to `~/Documents/HushScribe/`
- Updated appcast and GitHub release URLs to `drcursor/HushScribe`

## [1.2.2] — 2026-03-31 [upstream]
- Raised VAD threshold on system audio stream to reduce echo bleed during calls

## [1.2.0] — 2026-03-30
- Upgraded FluidAudio to latest (actor-based AsrManager) — fixes Swift 6 build failures on Xcode 26.4+
- Build script now fails on missing code signing identity instead of silently shipping unsigned
- Added Gatekeeper troubleshooting to README

## [1.1.0] — 2026-03-29
- Multilingual transcription: Parakeet-TDT v3, 25 European languages with auto-detection
- Pinned FluidAudio to 0.12.1

## [1.0.1] — 2026-03-28
- Spectrum visualizer replaces static waveform (reactive bars, peak hold, dynamic glow)
- Visual redesign: warm glass UI, chat-style transcript bubbles
- Pulsing recording indicator, silence countdown, keyboard shortcuts (⌘R, ⌘⇧R, ⌘.)
- Diarization progress messages during post-session processing
- Error visibility and save confirmation banner
- Session cleanup and async handling fixes

## [1.0.0] — 2026-03-24
- Initial release
- Local transcription via Parakeet-TDT v2 on Apple Silicon
- Call capture (mic + system audio) with per-app filtering
- Voice memo mode
- Speaker diarization
- Vault-native .md output with YAML frontmatter
- Sparkle auto-updates
