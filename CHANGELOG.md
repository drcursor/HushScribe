# Changelog

> **Fork note:** HushScribe is a fork of [Tome](https://github.com/Gremble-io/Tome) by [Gremble-io](https://github.com/Gremble-io). Changes merged from the upstream Tome repository are marked with `[upstream]` in this changelog.

## [3.5.0] — 2026-04-23

- **Transcript Viewer redesign.** The viewer now has a collapsible **Browse** sidebar (resizable by dragging the divider) for navigating saved transcripts. Transcripts with a saved summary show a sparkle badge. The toolbar has a single row: Browse toggle, Export, model picker, and Generate Summary.
- **Export as Markdown.** New export option alongside SRT and JSON. Produces a `# Title` header with `**Speaker** \`time\`` blocks.
- **Auto-load saved summary.** When opening a transcript, the corresponding `{name} summary.md` is loaded automatically if it exists — the summary tab appears without regenerating.
- **Model name in summary tab.** The tab shows "AI Summary · Qwen3 0.6B" (or whichever model was used) once generation completes.
- **Model name saved in summary file.** The `model:` field is written to the frontmatter of saved `.md` summary files.
- **Custom prompts as Generate menu.** When custom prompts are defined in Settings, the Generate Summary button becomes a drop menu listing "Default Summary" and each named custom prompt. The separate prompt picker dropdown has been removed from the toolbar.
- **Default model in Settings.** The "Use" button in Settings → Models → AI Summaries is now labelled "Default" and the active model shows a "Default" badge.

## [3.4.0] — 2026-04-23

- **Gemma 4 E4B summary model.** Gemma 4 E4B (4-bit quantized, instruction-tuned) is now available as an AI summary model alongside Qwen3 and Gemma 3. Download it in Settings → Models. Runs entirely on-device on Apple Silicon.
- **mlx-swift-lm updated** to latest version, adding Gemma 4 architecture support.
- **AI Summary model label.** The summary band header now shows the name of the model that generated the summary (e.g. "AI Summary · Qwen3 0.6B") instead of the generic "AI Summary".
- **Show Models in Finder.** Settings → Models now has "Show Models in Finder" buttons: one for AI summary models (`~/Library/Caches/models/`), and two for transcription models — Parakeet/FluidAudio (`~/Library/Application Support/FluidAudio/Models/`) and WhisperKit (`~/Documents/huggingface/models/…`).

## [3.3.0] — 2026-04-19

- **Status bar auto-record indicator.** A small white dot appears in the top-right corner of the menu bar icon when auto-meeting recording is enabled, giving a persistent at-a-glance reminder that the feature is active.
- **Speaker naming: natural sort order.** Speakers in the post-session naming window now appear in numeric order (Speaker 1, 2, 3 … 10, 11) instead of lexicographic order (1, 10, 11, 2 …).
- **Speaker naming: scrollable list.** When a recording has many speakers the naming window now scrolls, so all entries remain reachable regardless of how many speakers were detected.
- **Partial diarization on early stop.** If a file import is stopped mid-way, diarization now processes only the audio that was actually transcribed — not the entire source file. The exported WAV is trimmed to the processed duration so diarizer timestamps align correctly with the transcript.

## [3.2.0] — 2026-04-19

- **Transcribe File.** New "Transcribe File" toolbar button (⌃F) opens a file picker accepting any audio or video format (M4A, MP4, MOV, MP3, WAV, …). The file is decoded to 16 kHz mono PCM and processed through the same VAD → ASR → diarization pipeline as a live Call Capture session. Speaker diarization and the speaker-naming prompt run automatically after the file finishes (or after the user stops early). Output is a standard `.md` transcript in the vault, with `type: fleeting` frontmatter.

## [3.1.1] — 2026-04-12

- Updated app icons and logo.

## [3.1.0] — 2026-04-11

- **Settings → Main tab.** A new first tab in Settings consolidates app-level options. The notification sound toggle (moved from Privacy) lives here, along with a "Reset All Settings" button that wipes all stored preferences after confirmation. After reset, the settings window closes, the app switches to detached mode, and the onboarding wizard restarts as on first launch.
- **Notification sound.** Optional subtle sound (system "Tink") plays when a recording session starts or stops. Off by default; toggle in Settings → Main.
- **Auto-record toggle in attached mode.** A `waveform` toolbar button in the popover lets you enable/disable meeting auto-detection without opening Settings. A green dot appears on the icon when a meeting is actively detected.
- **Typing ellipsis during transcription.** A small animated ellipsis (3 pt dots) appears below the VU meters and the logo pulses while speech is being processed. Speech detection is driven by the VAD `speechStart` event so it works with all backends (Parakeet, WhisperKit, Apple Speech). Detection uses `.task(id:)` for reliable re-triggering across consecutive speech segments.
- **Attached mode fixed height.** The popover no longer grows taller as transcript content accumulates; it stays at a fixed 480×460 size.
- **Permission explanations in onboarding.** Each permission request in the setup wizard now shows a one-line reason explaining exactly why the permission is needed.
- **Settings → About tab.** A new last tab in Settings shows the app version, fork attribution, and full credits for all bundled models and libraries (FluidAudio, WhisperKit, mlx-swift-lm, Qwen3, Gemma 3, pyannote.audio). The separate About HushScribe panel and menu item have been removed.

## [3.0.0] — 2026-04-11

- **Attached mode (new default).** The app now opens as a compact popover anchored to the status bar icon by default. Click the icon to show or dismiss it. A "Detach" button in the toolbar breaks it out into a regular window; closing the window re-attaches automatically.
- **Menu bar rewritten in AppKit.** The `MenuBarExtra` SwiftUI scene has been replaced with a native `NSStatusItem` managed by `StatusBarController`. In detached mode the icon opens a menu with all recording controls; menu items are rebuilt lazily to always reflect live state.
- **Transcript export.** The Transcript Viewer now has an Export button next to Generate Summary. Transcripts can be exported as SRT (SubRip subtitles, one entry per speaker turn with timestamps) or JSON (structured array of `{speaker, time, text}` objects).

## [2.14.0] — 2026-04-11

- **Fix: mid-session microphone device switch.** `MicCapture` now exposes `stopForSwitch()`, which tears down the tap and stops the engine without calling `engine.reset()`, keeping the AUHAL unit initialised. This makes `AudioUnitSetProperty` reliable during live device switches and prevents the mic stream from silently dropping when swapping input devices mid-session. Thanks to [@acrolyos](https://github.com/acrolyos) for the report ([Gremble-io/tome-app#27](https://github.com/Gremble-io/tome-app/issues/27)).

## [2.13.0] — 2026-04-10

- **Legal Disclaimer onboarding step.** A new step in the first-launch wizard displays the recording consent notice. The user must tick "I understand it's my sole responsibility to comply with local recording laws" before proceeding. Recording is blocked until acknowledged.
- **Crash fix.** Fixed a `SIGSEGV` in `swift_task_isMainExecutorImpl` triggered by tapping a button while the deferred capture reset task was sleeping. Root cause: the task captured `TranscriptionEngine` as its executor context, leaving a dangling reference after AttributeGraph reclaimed the actor's memory. Fixed by using `Task.detached` instead.

## [2.12.0] — 2026-04-10

- **AI Summaries redesign.** Transcript viewer toolbar reorganised: model and prompt dropdowns sit below the Generate Summary button, left-aligned. When Apple NL is selected, an inline warning appears next to the model picker and the custom prompt dropdown is hidden. When an LLM model is selected, the prompt dropdown appears next to the model picker.
- **Custom prompt editor improved.** Slots renamed "Custom Prompt 1/2/3". The "Prompt" label no longer wraps. Name and body placeholders are now italic, distinct per slot, and visually styled as examples.
- **AI Summaries onboarding step.** New step in the first-launch wizard explains the Transcript Viewer and Generate Summary feature.
- **Menu bar icon.** Changed from pencil to quote.bubble.
- **Transcript browser: latest first.** File browser now shows all transcripts in a single date-sorted list (newest first) with type icons (meeting / voice memo), replacing the fixed Meetings / Voice Memos section split.

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

## [2.8.1] — 2026-04-07

- **Build scripts overhaul.** Release and signing scripts fully rewritten for reliability; notarization integrated into the release pipeline.
- **Source tree renamed.** `Tome/` → `HushScribe/`, `Sources/Tome` → `Sources/HushScribe` throughout.
- **Website improvements.** Legal recording-consent disclaimer added; bullet lists compacted; screenshots now loaded from raw GitHub URLs; GitHub Actions static-site deployment added.
- **Gatekeeper notes updated.** README and website updated with clearer first-launch instructions.

## [2.8.0] — 2026-04-07 *(reverted)*

- **Code-signed build.** Initial attempt at a notarized, Developer ID–signed DMG. Reverted in the same day due to signing pipeline issues; superseded by 2.8.1 and later 2.9.0.

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

## [2.2.0] — 2026-04-03

- **Pause / resume recording.** New button next to Stop lets you pause and resume a session without ending it.
- **Status bar menu controls.** Start, stop, pause, and resume are now available directly from the menu bar menu without opening the main window.
- **Status bar icon reflects state.** Icon changes to indicate idle, recording, or paused.
- **First-run model download UI.** On first launch, a prompt explains the model download before recording can begin. Download progress percentage is shown in the top bar.
- **Input device shown in top bar.** Current microphone name is displayed during recording and at idle.
- **Fixed window width.** Window is constrained to 320 pt wide; horizontal resizing disabled.
- **Fix: model download reliability.** Separated disk download from in-memory loading so partially-downloaded models no longer block startup.
- **Fix: mic device switch between sessions.** Switching input devices no longer carries state from a prior session.
- **Fix: button crash.** Fixed an AttributeGraph corruption crash triggered by rapid button taps.

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
