# Logic Pro Key Commands

This reference records the assumptions used by `scripts/logicpro.sh`.

## Requirements

- Logic Pro must be installed as `Logic Pro.app`, unless `LOGIC_APP_NAME` is set.
- The terminal/OpenClaw host must have macOS Accessibility permission.
- Logic Pro should use default key commands, or the script mappings must be updated.
- Keyboard layout differences can affect `keystroke`; use `keycode` when a physical key is more reliable.

## Script Mappings

| Script command | Logic action | Input sent |
| --- | --- | --- |
| `play-toggle` | Play/stop transport | Space, key code `49` |
| `play-from-beginning` | Move playhead to project start, then play | Return key code `36`, then Space key code `49` |
| `record-toggle` | Record toggle | `R` |
| `open-project` | Open and remember a Logic project | `open -a "Logic Pro" project.logicx` plus local state |
| `current-project` | Show remembered Logic project | Local state file |
| `generate-midi` | Create a MIDI file from a compact prompt | Python MIDI writer |
| `generate-midi-in-project` | Create MIDI beside the remembered Logic project package | Python MIDI writer to `<project-name>.generated-midi/` |
| `generate-and-import-midi` | Generate project-scoped MIDI and import it into the open Logic UI | MIDI writer plus Logic import dialog automation |
| `open-midi` | Open/import a generated MIDI file in Logic Pro | `open -a "Logic Pro" file.mid` |
| `go-to-beginning` | Return to beginning | Return, key code `36` |
| `cycle-toggle` | Cycle mode toggle | `C` |
| `metronome-toggle` | Metronome toggle | `K` |
| `save` | Save project | Command-S |
| `bounce` | Bounce dialog | Command-B |
| `new-audio-track` | New audio track | Option-Command-A |
| `new-software-track` | New software instrument track | Option-Command-S |

## Safer Menu Automation

Use menu automation when a menu item is stable and visible:

```bash
scripts/logicpro.sh menu File Save
scripts/logicpro.sh menu File Bounce "Project or Section..."
```

Menu item names may vary by Logic Pro version and system language. If a menu command fails, inspect the visible menu text and update the command.

## Fragile Operations

Verify the screen before these actions:

- Deleting tracks, regions, takes, or audio files.
- Recording into an unknown armed track.
- Bouncing or exporting when file path and settings are not visible.
- Changing project tempo, sample rate, I/O routing, or plugin settings.
- Any command that depends on the current selected region, track, or cycle range.

## Adding Commands

Add a new command only after choosing the least fragile control surface:

1. Menu path if the action is in the macOS menu bar.
2. Key command if Logic's key command mapping is known.
3. Accessibility UI click only after inspecting current UI state.
