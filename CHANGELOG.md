# Changelog

> **Fork note:** HushScribe is a fork of [Tome](https://github.com/Gremble-io/Tome) by [Gremble-io](https://github.com/Gremble-io). Changes merged from the upstream Tome repository are marked with `[upstream]` in this changelog.

## [2.11.0] — 2026-04-09

- **Transcript Viewer.** Dedicated window for browsing, previewing and summarising saved transcripts. Accessible from the toolbar and the menu bar ("Transcript Viewer…"). Includes a file picker with type filter (All / Meetings / Voice Memos) and date filter (All Time / Today / This Week / This Month), with file sizes shown. Speaker bubbles use the same colours as the live recording view.
- **Inline input device picker.** Clicking the current input device in the main window top bar now shows an inline dropdown to switch microphone — no need to open Settings.
- **Save summary UX.** After saving, the button shows "Saved · filename". Re-generating a summary resets the button and prompts to overwrite if the file already exists.
- **Markdown preview in summary pane.** Toggle between rendered Markdown and plain text. Preview is the default. The AI Summary separator band now contains the save button.
- **Speaker naming previews.** Speaker naming window now shows up to 3 short text excerpts per detected speaker to help identify who is who.
- **Synthesised highlights.** AI summary Highlights are now short topic-level headlines (e.g. "Timeline confirmed: deployment, sprint.") rather than verbatim sentences from the transcript. Uses clustering and named-entity extraction to produce distinct, third-person summaries.
- **Meeting auto-detection stop delay.** Configurable in Settings → Meeting Detection (0–60 s, default 5 s).
- **Meeting auto-detection toggle in onboarding.** The onboarding wizard now includes a toggle to enable meeting auto-detection on the relevant step.
- **Device fallback.** If no input device is configured, the system default is selected automatically on launch.
- **Main window resized.** Shorter and wider (480 × 360). Toolbar with icons for Transcript Viewer, Settings, and Hide.
- **"Experimental" label removed** from meeting auto-detection everywhere; browser-based meeting limitation noted instead.
- **"Get Started" closes immediately.** Finishing the onboarding wizard hides the main window without delay.

## [2.9.0] — 2026-04-08

- **Fix: microphone silent on system default input.** On first run (or when "System Default" is selected), the mic sometimes delivered no audio. Root causes: `defaultInputDeviceID()` could return `kAudioDeviceUnknown` (0), which was passed through to `AudioUnitSetProperty` and caused the capture stream to abort; and `AVAudioInputNode.outputFormat(forBus:)` can report `sampleRate=0`/`channelCount=0` immediately after mic permission is granted before the audio unit initialises. Fixed by: never treating device ID 0 as a valid device, and falling back to a standard 44.1 kHz/mono tap format when the engine reports an uninitialised format (AVAudioEngine converts from the real device format on start).
- **Shorter transcription intervals.** Speech segments are now flushed every ~6 seconds (down from ~30 seconds), so partial output appears much sooner during continuous speech.
- **Apple Speech partial results.** When using the Apple Speech model, in-progress words appear in the transcript as you speak (typing-effect), clearing when the final result is committed.

## [2.7.0] — 2026-04-06

- **Meeting auto-detection (experimental).** Enable "Auto-record meetings" from the menu bar. HushScribe watches for Zoom, Teams, Slack, FaceTime, Webex, Discord, Google Meet, and Loom — recording starts only when a call is actually in progress (meeting app running AND microphone actively in use), and stops 5 seconds after the call ends. Configurable start delay in Settings → Meeting Detection.
- **About HushScribe in menu bar.** "About HushScribe" now available directly from the status bar menu.
- **Tutorial updated.** New onboarding step covers meeting auto-detection.
- **Pause state reset on start.** Pause button always resets to its default state when a new recording begins.

## [2.6.5] — 2026-04-05

- **Auto-scroll.** Transcript view now follows new utterances as they arrive — no manual scrolling needed.
- **Pause indicator.** Top bar timer shows `· Paused` and a `⏸ Paused` label replaces the silence countdown when a session is paused.
- **System audio VAD sensitivity.** New slider in Settings → Recording to control how confidently speech must be detected in system audio before transcription runs. Default and recommended value: 0.92.

## [2.6.0] — 2026-04-05

- **On-device AI summary.** Each transcript now includes a **Summary** section inserted before the transcript body, containing Topics, Highlights, and To-Dos extracted entirely on-device using Apple's NaturalLanguage framework. No data leaves the device and no API key is required.

## [2.5.0] — 2026-04-05

- **Mute controls.** Each VU meter panel now has a small mute toggle button next to its label. Mic mute silences the microphone channel; System mute silences system audio. The icon turns red when muted and the corresponding meter goes dark. Muting suppresses both the audio level display and transcription for that stream.

## [2.4.1] — 2026-04-05

- **Split VU meter.** The waveform display is now divided into two panels — "Mic" on the left and "System" on the right — each with its own level, peak hold, and glow. Gives a live visual of what each audio stream is capturing.

## [2.4.0] — 2026-04-05

- **Multi-model transcription.** Transcription model is now selectable in Settings. Three options ship alongside the existing Parakeet-TDT v3:
  - **WhisperKit Base** and **WhisperKit Large v3** — OpenAI Whisper via [WhisperKit](https://github.com/argmaxinc/WhisperKit); models download automatically on first session start.
  - **Apple Speech** — macOS's built-in on-device SFSpeechRecognizer; no download required, prompts for Speech Recognition permission on first use.
- Selection is persisted across restarts.

## [2.3.1] — 2026-04-03

- Silence timeout countdown shown below waveform during recording; turns red at ≤30s; click to reset
- Configurable silence timeout in Settings (30s–10m, default 2m)
- README: added Differences compared to Tome, Planned Functionality sections

## [2.3.0] — 2026-04-03

- [upstream] Post-session speaker naming UI — after diarization completes, a prompt lets you assign real names to each detected speaker, which are then rewritten into the transcript. Contributed by [0xLeathery](https://github.com/0xLeathery/Tome/tree/feature/speaker-naming).
- Menu bar integration: app hides dock icon when window is closed; dock icon reappears when window is shown
- Status bar icon updated to pencil (feather pen theme); new app icon
- Removed Sparkle auto-update system; updates distributed via GitHub releases
- Added Settings and About HushScribe to menu bar menu
- 80s-style segmented LED VU meter replaces smooth spectrum visualizer
- Removed forced dark theme; app now follows macOS system appearance
- Onboarding step added for menu bar usage

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
