<h1 align="center">HushScribe</h1>

<p align="center">
  <strong>Local meeting capture → Obsidian vault → AI agent pipeline. No cloud. No API keys. Your data.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white" alt="Swift 6.2" />
  <img src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white" alt="macOS 26+" />
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT License" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-Required-333333?logo=apple&logoColor=white" alt="Apple Silicon" />
</p>

---

> **HushScribe is a fork of [Tome](https://github.com/Gremble-io/Tome)**, substantially extended with additional features and a new name. See [Credits](#credits) for the original project. All the information found below is sourced from the original Tome Project unless otherwise stated. I'm using this project as a way to test out using AI for modificating OpenSource software for my own use without doing any actual coding, as such most modifications to the original project found under this fork are made using Claude Code.
Together with Gremble [we decided](https://github.com/Gremble-io/Tome/pull/13#issuecomment-4158040508) not to merge these changes to the main project so that he can keep full control over his codebase.

HushScribe is a macOS app that captures meetings and voice memos, transcribes them locally with Parakeet-TDT v3, and drops structured `.md` files straight into your Obsidian vault. Everything runs on-device. Nothing phones home.

<p align="center">
  <img src="assets/main.png" width="240" alt="HushScribe — main" />
  <img src="assets/capturing.png" width="240" alt="HushScribe — capturing" />
  <img src="assets/captured.png" width="240" alt="HushScribe — captured" />
  <img src="assets/speakers.png" width="240" alt="HushScribe — speaker naming" />
</p>

## Installing

**Via Homebrew (recommended):**

```bash
brew tap drcursor/hushscribe https://github.com/drcursor/HushScribe
brew install --cask hushscribe
```

**Manual:** Download the DMG from the [latest release](https://github.com/drcursor/HushScribe/releases/latest) and drag HushScribe to `/Applications`.

The current release is not code-signed. macOS will block it from opening by default. See the [Troubleshooting](#troubleshooting) section for steps to bypass Gatekeeper, or follow the instructions shown after installing via Homebrew.

## Background

I'm a consultant who fell down the Obsidian rabbit hole. I built out a vault as a second brain: structured notes with YAML frontmatter, backlinks, tags, and a Claude agent layer that processes everything. Client files, meeting notes, action items, daily briefs, all flowing through the vault automatically.

The problem was capture. I'm on calls all day and I don't take notes. I needed something that would listen, transcribe, and drop structured markdown into the vault where my agent could pick it up and do the rest. Pull out action items, update client files, connect the dots.

I looked at Otter, Granola, Fireflies. They all lock your data in their cloud, their format, their walled garden. None of them output plain markdown. None of them are built to feed into an agent workflow.

I started from [OpenGranola](https://github.com/yazinsai/OpenGranola), learned Swift along the way, and rebuilt it with a different audio pipeline, local ASR, speaker diarization, and vault-native output. If you're running Obsidian with any kind of AI agent setup, you probably have the same gap.

## Why HushScribe?

- **Plain markdown out.** YAML frontmatter, tags, timestamps. Your vault already knows what to do with it. No proprietary export, no copy-paste, no middleman.
- **Built for the agent pipeline.** HushScribe is just the capture layer. You talk, it transcribes, your agent picks up the `.md` and does whatever you've wired it to do.
- **Runs on your machine.** Parakeet-TDT v3 on Apple Silicon. No API keys, no accounts, no subscriptions, no data leaving the building.

```
speak → capture → vault → agent → knowledge base
```

HushScribe does the first three. Your agent does the rest.

## Features

- **Multilingual transcription** via Parakeet-TDT v3 ([FluidAudio](https://github.com/FluidInference/FluidAudio)) on Apple Silicon. 25 European languages, auto-detected. Nothing hits the network.
- **Call Capture** grabs mic + system audio. Detects which conferencing app you're in (Teams, Zoom, Slack, etc.) and filters audio to just that app. Your Spotify and notification sounds stay out of the transcript.
- **Voice Memo** is mic only. For quick thoughts, verbal notes, stream of consciousness. Saves to a separate folder so it doesn't clutter your meeting transcripts.
- **Speaker diarization** runs after the call ends. pyannote splits the remote audio into Speaker 2, Speaker 3, Speaker 4. Not perfect, but way better than one wall of unattributed text.
- **Vault-native output** writes `.md` with frontmatter: `type`, `created`, `attendees`, `tags`, `source_app`. Lands in your vault ready to process.
- **Privacy.** Hidden from screen sharing by default. No audio saved. Transcripts only.
- **Silence auto-stop.** 120 seconds of dead air and it stops itself.

## Differences Compared to Tome

HushScribe diverges from [Tome](https://github.com/Gremble-io/Tome) in the following ways:

- **Menu bar app.** HushScribe lives in the menu bar with no dock icon by default. The main window is hidden on launch after the first run and can be shown via the "Show HushScribe" menu item. Tome always shows in the dock.
- **Post-session speaker naming.** After diarization completes, HushScribe prompts you to assign real names to each detected speaker. Those names are rewritten into the transcript. (Contributed by [0xLeathery](https://github.com/0xLeathery/Tome/tree/feature/speaker-naming).)
- **Silence timeout display and configuration.** A countdown is shown below the waveform during recording, turns red at ≤30 seconds, and can be reset by clicking it. The default timeout is configurable in Settings.
- **80s-style segmented LED VU meter.** Replaced the smooth spectrum visualizer with a blocky green/yellow/red LED-segment meter.
- **Follows macOS system appearance.** Removed the forced dark theme; the app adapts to Light or Dark mode.
- **No auto-update system.** Sparkle has been removed. Updates are distributed manually via GitHub releases.
- **Feather pen identity.** New app icon and pencil status bar symbol.
- **Pause recording.** Recordings can be paused and resumed mid-session from both the main UI and the menu bar.
- **Current input device display.** The active microphone is shown next to the session timer in the top bar.
- **Alternative model download handling.** The model download is triggered from a dedicated prompt in the main UI on first run, rather than happening silently in the background.

## Planned Functionality

- Auto-detect meetings and start recording automatically
- Support for alternative transcription models
- Better transcript preview at end of session
- Installation via brew

## Output

<p align="center">
  <img src="https://raw.githubusercontent.com/Gremble-io/Tome/main/assets/screenshot-vault-frontmatter.png?v=2" width="600" alt="Vault note with YAML frontmatter" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/Gremble-io/Tome/main/assets/screenshot-vault-transcript.png?v=2" width="600" alt="Vault note transcript view" />
</p>

```markdown
---
type: meeting
created: "2026-03-23"
time: "10:00"
duration: "18:42"
source_app: "Zoom"
attendees: ["You", "Speaker 2"]
tags:
  - log/meeting
  - status/inbox
  - source/hushscribe
---

# Call Recording — 2026-03-23 10:00

**You** (10:00:03)
Morning. Quick sync on the product launch. Where are we at?

**Speaker 2** (10:00:07)
We're in good shape. QA signed off yesterday, marketing assets
are locked, landing page is live in staging.
```

Voice memos use `type: fleeting` with a single speaker. Same structure, same frontmatter.

## Build

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full build instructions and project structure.

## Permissions

| Permission | When | Why |
|---|---|---|
| **Microphone** | All modes | Captures your voice |
| **Screen Recording** | Call Capture only | ScreenCaptureKit needs this for system audio from conferencing apps |

macOS re-prompts for Screen Recording permission roughly monthly. That's an OS thing, not HushScribe.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full architecture overview and source tree.

## Privacy

- Transcription runs entirely on-device. No audio is ever sent anywhere.
- No network calls. No analytics. No telemetry.
- No audio is saved to disk. Only text transcripts.
- The app window is hidden from screen sharing by default.
- Transcripts are saved as plain `.md` files to a folder you choose.

## Known Limitations

- **Apple Silicon only.** Parakeet and FluidAudio need Metal / ANE. No Intel.
- **macOS 26+ only.**
- **Screen Recording re-prompts monthly.** OS limitation.
- **Diarization is imperfect.** Works well with headset mics. Laptop speakers with crosstalk will give you worse speaker separation.
- **No live speaker labels.** Diarization runs after the session ends. During the call, remote audio shows as a single stream.

## Troubleshooting

**"HushScribe is damaged and can't be opened"**

This is macOS Gatekeeper blocking an unsigned app. Until a signed release is available, run the following command on your terminal : 'xattr -d com.apple.quarantine /Applications/HushScribe.app'

You only need to do this once — after that, HushScribe launches normally.

Alternatively, build from source (see [Build](#build) above) to avoid Gatekeeper entirely.

## Credits

HushScribe is a fork of [Tome](https://github.com/Gremble-io/Tome) by [Gremble-io](https://github.com/Gremble-io), which itself started from [OpenGranola](https://github.com/yazinsai/OpenGranola). Substantially rewritten from both.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## License

[MIT](LICENSE)
