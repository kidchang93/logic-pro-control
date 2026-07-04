# Logic Pro Control

Agent-friendly scripts and skill instructions for controlling Apple Logic Pro on macOS.

This repository contains a small control layer for Logic Pro:

- `SKILL.md`: procedural guidance for agents.
- `scripts/logicpro.sh`: launch, focus, transport, recording, track, save, bounce, menu, and key-command automation.
- `references/logic-pro-key-commands.md`: default key-command assumptions and caveats.

## Quick Start

```bash
scripts/logicpro.sh doctor
scripts/logicpro.sh launch
scripts/logicpro.sh play-from-beginning
```

macOS Accessibility permission is required for key and menu automation:
System Settings -> Privacy & Security -> Accessibility.

## Notes

Logic Pro does not expose a broad stable automation API, so this project uses AppleScript, System Events, and keyboard/menu automation. Keep commands small, verify the visible state before destructive operations, and update key-command mappings when your Logic Pro setup differs from the defaults.

This helper repo intentionally does not include Logic Pro project files, audio media, or bounces.

