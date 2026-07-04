---
name: logic-pro-control
description: Control Apple Logic Pro on macOS with launch, focus, transport, recording, track, save, bounce, and menu automation scripts. Use when an agent must operate Logic Pro through AppleScript, Accessibility UI scripting, or keyboard commands.
---

# Logic Pro Control

Use this skill when the user asks the agent to control Logic Pro, automate repetitive DAW operations, or build higher-level Logic workflows from scripts.

## Operating Model

Logic Pro does not expose a broad, stable automation API. Prefer this order:

1. Use `scripts/logicpro.sh` for supported commands.
2. Use `scripts/logicpro.sh menu ...` for menu-bar actions that are safer than raw shortcuts.
3. Use `scripts/logicpro.sh key ...` or `scripts/logicpro.sh keycode ...` for custom key commands.
4. If a workflow depends on the visible UI, inspect the current screen first and make the smallest UI action possible.

Require macOS Accessibility permission for the terminal/OpenClaw host that runs the script:
System Settings -> Privacy & Security -> Accessibility.
If `scripts/logicpro.sh doctor` reports `accessibility=false`, key/menu commands will refuse to run until this permission is enabled.

## Quick Commands

Run from this workspace:

```bash
scripts/logicpro.sh status
scripts/logicpro.sh doctor
scripts/logicpro.sh launch
scripts/logicpro.sh focus
scripts/logicpro.sh open-project /Users/kidchang/Music/Logic/beatrobatic.logicx
scripts/logicpro.sh current-project
scripts/logicpro.sh play-toggle
scripts/logicpro.sh play-from-beginning
scripts/logicpro.sh record-toggle
scripts/logicpro.sh generate-midi "neo-soul jazz piano, 4 bars, lush gospel voicings"
scripts/logicpro.sh generate-midi-in-project "neo-soul jazz piano, 4 bars, lush gospel voicings"
scripts/logicpro.sh generate-and-import-midi "neo-soul jazz piano, 4 bars, lush gospel voicings"
scripts/logicpro.sh open-midi generated/example.mid
scripts/logicpro.sh save
scripts/logicpro.sh bounce
```

Use `LOGIC_APP_NAME` when the app process name differs:

```bash
LOGIC_APP_NAME="Logic Pro" scripts/logicpro.sh status
```

## Workflow

Before operating Logic Pro:

1. Run `scripts/logicpro.sh status`.
2. If Logic is not running, run `scripts/logicpro.sh launch`.
3. Run `scripts/logicpro.sh focus` before transport, track, key, or menu commands.
4. Execute one small command at a time.
5. Verify visible state when recording, bouncing, deleting, overwriting, or changing project structure.

Ask for clarification before destructive or expensive actions when the target is ambiguous, including deleting tracks or regions, overwriting a project, bouncing/exporting with unknown settings, or starting recording when the input/track is not specified.

## Common Actions

- `play-toggle`: press Space.
- `play-from-beginning`: press Return, then Space.
- `record-toggle`: press `R`.
- `open-project <project.logicx>`: open a Logic project and remember it as the current project for project-scoped generation.
- `current-project`: print the remembered Logic project path.
- `generate-midi "<prompt>" [output.mid]`: generate a short piano MIDI idea from a compact natural-language prompt.
- `generate-midi-in-project "<prompt>" [filename.mid]`: generate MIDI in a visible project-adjacent folder such as `beatrobatic.generated-midi/`.
- `generate-and-import-midi "<prompt>" [filename.mid]`: generate project-scoped MIDI, then import it into the open Logic project UI.
- `open-midi <file.mid>`: ask Logic Pro to open/import a generated MIDI file.
- `go-to-beginning`: press Return.
- `cycle-toggle`: press `C`.
- `metronome-toggle`: press `K`.
- `save`: press Command-S.
- `bounce`: press Command-B.
- `new-audio-track`: press Option-Command-A.
- `new-software-track`: press Option-Command-S.

For key command details and caveats, read `references/logic-pro-key-commands.md`.

## Natural-Language MIDI Ideas

Use `scripts/generate_midi.py` through `scripts/logicpro.sh generate-midi` for requests such as "make a 4-bar neo-soul piano MIDI idea". Avoid claiming to clone a living artist's exact style; translate artist references into musical traits such as neo-soul harmony, gospel voicings, extended chords, swung timing, or laid-back velocity.

Use `open-project` before project-scoped generation so the script knows which open project owns the result. `generate-midi-in-project` writes files next to the project package, for example `beatrobatic.generated-midi/`, because macOS file dialogs do not reliably navigate inside `.logicx` packages.

Use `scripts/logicpro.sh generate-and-import-midi "<prompt>"` when the user expects the result to appear as a Logic track/region. Exact insertion at the current playhead depends on Logic Pro's import UI state; verify the result before editing the project further.

## Extending

When adding a new Logic action:

1. Prefer a menu path if the operation is exposed in the menu bar.
2. Prefer a named key command only if the user's Logic key commands are known or default.
3. Add the action to `scripts/logicpro.sh`.
4. Add the key/menu mapping to `references/logic-pro-key-commands.md`.
5. Test `scripts/logicpro.sh status` and the new command manually with Logic Pro open.
