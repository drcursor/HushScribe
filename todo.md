# TODO items
1 - [DONE] on first run display a link in the middle of the ui allowing the user to download the model
2 - [DONE] Add an option to pause recording on the main stop button on the ui, when clicked the recording should be paused and the button should be replaced by an unpause button
3 - [DONE] Add current input device next to the "ready" text on the ui
4 - [DONE] Add options to the status bar menu to start recording (if no recording is active), stop recording (only if recording is active or paused), pause recording (only if recording is active), unpause recording (only if recording is paused)
5 - [DONE] Display different status bar icon according to current recording status (active, stopped, paused)
6 - [DONE] Make initial UI size smaller on the first run
7 - [DONE] Make model selection generic, allowing user to select a different model on the settings screen. the settings screen should have a dropdown to select a model, with a fetch button to it's right that will refresh the dropbox with possible models, parakeet-tdt-0.6b-v3 should always be the initial model on the list
8 - Make sure status bar action menu items (record, pause, stop) are enabled if the corresponding ui buttons are enabled and disabled if they are disabled
9 - [DONE] From now on, this project will become a fork of the original tome project. Documentation should indicate this. The project should be renamed to HushScribe. All user visibile references to tome, including images should be replaced by this name
10 - [DONE] When starting the application, by default, it should not show the main application window, nor should it have an icon on the dock. Only exception to this is the initial run when the tutorial is shown.
11 - [DONE] Status bar menu should have a "Show Hushscribe" that shows the main application window.
12 - [DONE] On the initial tutorial add a short indication about "Show Hushscribe", with an arrow pointing to the top right of the screen.
13 - [DONE] The tome main window should follow macos style guidelines instead of the current dark theme
14 - [DONE] Make the audio vu meter more blocky, 80's styled
15 - [DONE] Add a status menu item for settings.
16 - [DONE] When a recording is happening show the timeout centered below the vu meter. Once the timeout gets to 30 seconds change the text to red. Allow the default timeout to be changed on the settings window. Allow the timeout to be increased by clicking on the timeout display. Add a small text to the settings window explaining that this is possible.
17 - [DONE] Split the VU meter in two. left side for microphone input, right side for system audio. Label them with a small font bellow each.
18 - [DONE] Add a small icon with a mute icon to both VUs, allowing the user to mute the corresponding audio source.
19 - [DONE] When the output file is create a small summary of the output should be written. It should include topics, highlights and any relevant to-dos. A related project, https://github.com/jlevy-dev/Murmur already does this, please check how its being done and take any information that can be useful.
20 - [DONE] Auto-scroll in transcript view — the transcript doesn't follow new utterances as they come in; user has to scroll manually.
21 - [DONE] Session state on pause — the timer doesn't visually indicate the session is paused. A "(paused)" label or colour change would make it clear.
22 - [DONE] VAD sensitivity setting — the system audio VAD threshold is hardcoded at 0.92 (TranscriptionEngine.swift:183). A slider in Settings would help users with noisy environments. 0.92 should be the default and advised value.
23 - [DONE] /tmp/hushscribe.log should only be created and used on debug versions
24 - [DONE] Website
25 - [DONE] Detect meeting ( see projects that do this https://github.com/fastrepl/char, https://github.com/RecapAI/Recap ) and add a toggle (button and status menu) allowing the user to enable automatic recording start when a meeting is detected (eg MS teams, zoom, slackm, etc). The detection should be generic enough to work with other conference systems.
26 - Next to the 'open in finder' show a 'preview and summarise' button. when clicked a preview window with the final text should be shown, the user should be allowed to ask for the re-generation of the summary component of the text, on a button on the top of the window.
27 - Split the settings window with tabs : Recording, Privacy, Models, Output
28 - The models tab on the settings window should have a list of the supported models, options for the user to download and remove the downloaded model as well as a short description for each one.