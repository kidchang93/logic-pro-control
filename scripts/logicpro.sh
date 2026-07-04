#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${LOGIC_APP_NAME:-Logic Pro}"
KEY_DELAY="${LOGIC_KEY_DELAY:-0.15}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="${LOGIC_CONTROL_STATE_FILE:-$PROJECT_ROOT/.logicpro-control-state}"

usage() {
  cat <<'EOF'
Usage:
  scripts/logicpro.sh status
  scripts/logicpro.sh doctor
  scripts/logicpro.sh launch
  scripts/logicpro.sh focus
  scripts/logicpro.sh open-project <project.logicx>
  scripts/logicpro.sh current-project
  scripts/logicpro.sh check-accessibility
  scripts/logicpro.sh play-toggle
  scripts/logicpro.sh play-from-beginning
  scripts/logicpro.sh record-toggle
  scripts/logicpro.sh generate-midi <prompt> [output.mid]
  scripts/logicpro.sh generate-midi-in-project <prompt> [filename.mid]
  scripts/logicpro.sh open-midi <file.mid>
  scripts/logicpro.sh import-midi <file.mid>
  scripts/logicpro.sh generate-and-import-midi <prompt> [filename.mid]
  scripts/logicpro.sh go-to-beginning
  scripts/logicpro.sh cycle-toggle
  scripts/logicpro.sh metronome-toggle
  scripts/logicpro.sh save
  scripts/logicpro.sh bounce
  scripts/logicpro.sh new-audio-track
  scripts/logicpro.sh new-software-track
  scripts/logicpro.sh key <character> [modifiers]
  scripts/logicpro.sh keycode <mac-key-code> [modifiers]
  scripts/logicpro.sh menu <menu-name> <menu-item> [submenu-item ...]

Modifiers are comma-separated: command,shift,option,control

Examples:
  scripts/logicpro.sh key b command
  scripts/logicpro.sh keycode 49
  scripts/logicpro.sh menu File Save
EOF
}

escape_applescript_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

absolute_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).expanduser().resolve())
PY
}

modifier_expr() {
  local spec="${1:-}"
  local result=""
  local item

  if [[ -z "$spec" ]]; then
    printf ''
    return
  fi

  IFS=',' read -ra parts <<<"$spec"
  for item in "${parts[@]}"; do
    case "$item" in
      command|cmd) result="${result}command down, " ;;
      shift) result="${result}shift down, " ;;
      option|opt|alt) result="${result}option down, " ;;
      control|ctrl) result="${result}control down, " ;;
      "")
        ;;
      *)
        printf 'Unknown modifier: %s\n' "$item" >&2
        exit 64
        ;;
    esac
  done

  result="${result%, }"
  printf '{%s}' "$result"
}

activate_logic() {
  open -a "$APP_NAME"
  osascript - "$APP_NAME" "$KEY_DELAY" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set keyDelay to (item 2 of argv) as real
  tell application appName to activate
  delay keyDelay
end run
APPLESCRIPT
}

status() {
  osascript - "$APP_NAME" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  tell application "System Events"
    set isRunning to exists process appName
    if isRunning then
      set isFrontmost to frontmost of process appName
    else
      set isFrontmost to false
    end if
  end tell

  return "app=" & appName & linefeed & "running=" & isRunning & linefeed & "frontmost=" & isFrontmost
end run
APPLESCRIPT
}

check_accessibility() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  if UI elements enabled then
    return "accessibility=true"
  else
    return "accessibility=false"
  end if
end tell
APPLESCRIPT
}

accessibility_enabled() {
  [[ "$(check_accessibility)" == "accessibility=true" ]]
}

require_accessibility() {
  if ! accessibility_enabled; then
    printf '%s\n' 'error=accessibility permission is required for Logic Pro key/menu control' >&2
    printf '%s\n' 'hint=Enable Accessibility for the terminal or OpenClaw host in System Settings -> Privacy & Security -> Accessibility.' >&2
    exit 77
  fi
}

doctor() {
  status
  check_accessibility
  printf 'note=%s\n' 'If accessibility=false, grant Accessibility permission to the terminal or OpenClaw host before using key/menu commands.'
}

store_current_project() {
  local project_path="$1"
  printf 'project=%s\n' "$project_path" > "$STATE_FILE"
}

read_current_project() {
  if [[ -n "${LOGIC_PROJECT_PATH:-}" ]]; then
    absolute_path "$LOGIC_PROJECT_PATH"
    return
  fi

  if [[ -f "$STATE_FILE" ]]; then
    sed -n 's/^project=//p' "$STATE_FILE" | tail -n 1
  fi
}

require_current_project() {
  local project_path
  project_path="$(read_current_project)"

  if [[ -z "$project_path" || ! -d "$project_path" ]]; then
    printf '%s\n' 'error=current Logic project is unknown' >&2
    printf '%s\n' 'hint=Run scripts/logicpro.sh open-project /path/to/project.logicx first, or set LOGIC_PROJECT_PATH.' >&2
    exit 78
  fi

  printf '%s\n' "$project_path"
}

open_project() {
  if (( $# != 1 )); then
    usage >&2
    exit 64
  fi

  local project_path
  project_path="$(absolute_path "$1")"
  if [[ ! -d "$project_path" || "$project_path" != *.logicx ]]; then
    printf 'Logic project not found: %s\n' "$project_path" >&2
    exit 66
  fi

  open -a "$APP_NAME" "$project_path"
  store_current_project "$project_path"
  sleep "$KEY_DELAY"
  status
  printf 'project=%s\n' "$project_path"
}

project_generated_dir() {
  local project_path="$1"
  python3 - "$project_path" <<'PY'
from pathlib import Path
import sys

project = Path(sys.argv[1])
name = project.name[:-7] if project.name.endswith(".logicx") else project.stem
print(project.parent / f"{name}.generated-midi")
PY
}

current_project() {
  local project_path
  project_path="$(read_current_project)"
  if [[ -z "$project_path" ]]; then
    printf 'project=\n'
    return
  fi

  printf 'project=%s\n' "$project_path"
  if [[ -d "$project_path" ]]; then
    printf 'exists=true\n'
  else
    printf 'exists=false\n'
  fi
}

send_key() {
  local key="$1"
  local modifiers="${2:-}"
  local mods
  local escaped_key

  mods="$(modifier_expr "$modifiers")"
  escaped_key="$(escape_applescript_string "$key")"
  require_accessibility
  activate_logic

  if [[ -z "$mods" ]]; then
    osascript - "$escaped_key" <<'APPLESCRIPT'
on run argv
  set keyValue to item 1 of argv
  tell application "System Events" to keystroke keyValue
end run
APPLESCRIPT
  else
    osascript <<APPLESCRIPT
tell application "System Events" to keystroke "$escaped_key" using $mods
APPLESCRIPT
  fi
}

send_keycode() {
  local code="$1"
  local modifiers="${2:-}"
  local mods

  if ! [[ "$code" =~ ^[0-9]+$ ]]; then
    printf 'Key code must be numeric: %s\n' "$code" >&2
    exit 64
  fi

  mods="$(modifier_expr "$modifiers")"
  require_accessibility
  activate_logic

  if [[ -z "$mods" ]]; then
    osascript <<APPLESCRIPT
tell application "System Events" to key code $code
APPLESCRIPT
  else
    osascript <<APPLESCRIPT
tell application "System Events" to key code $code using $mods
APPLESCRIPT
  fi
}

play_from_beginning() {
  activate_logic
  send_keycode 36
  sleep "$KEY_DELAY"
  send_keycode 49
}

generate_midi() {
  if (( $# < 1 || $# > 2 )); then
    usage >&2
    exit 64
  fi

  if (( $# == 2 )); then
    python3 "$SCRIPT_DIR/generate_midi.py" "$1" --output "$2"
  else
    python3 "$SCRIPT_DIR/generate_midi.py" "$1"
  fi
}

generate_midi_in_project() {
  if (( $# < 1 || $# > 2 )); then
    usage >&2
    exit 64
  fi

  local project_path output_dir output_path filename
  project_path="$(require_current_project)"
  output_dir="$(project_generated_dir "$project_path")"
  mkdir -p "$output_dir"

  if (( $# == 2 )); then
    filename="$2"
    [[ "$filename" == *.mid ]] || filename="${filename}.mid"
    output_path="$output_dir/$filename"
  else
    output_path="$(python3 "$SCRIPT_DIR/generate_midi.py" "$1" --print-default-path 2>/dev/null || true)"
    output_path="$output_dir/$(basename "${output_path:-generated.mid}")"
  fi

  python3 "$SCRIPT_DIR/generate_midi.py" "$1" --output "$output_path"
  printf 'project=%s\n' "$project_path"
}

open_midi() {
  if (( $# != 1 )); then
    usage >&2
    exit 64
  fi

  local midi_path="$1"
  if [[ ! -f "$midi_path" ]]; then
    printf 'MIDI file not found: %s\n' "$midi_path" >&2
    exit 66
  fi

  open -a "$APP_NAME" "$midi_path"
}

click_menu_path() {
  if (( $# < 2 )); then
    printf 'menu requires at least <menu-name> <menu-item>\n' >&2
    exit 64
  fi

  require_accessibility
  activate_logic

  osascript - "$APP_NAME" "$@" <<'APPLESCRIPT'
on run argv
  set appName to item 1 of argv
  set menuName to item 2 of argv
  set itemNames to items 3 thru -1 of argv

  tell application "System Events"
    tell process appName
      set currentMenu to menu menuName of menu bar 1
      repeat with i from 1 to count of itemNames
        set itemName to item i of itemNames
        if i is (count of itemNames) then
          click menu item itemName of currentMenu
        else
          set currentMenu to menu 1 of menu item itemName of currentMenu
        end if
      end repeat
    end tell
  end tell
end run
APPLESCRIPT
}

click_first_existing_menu_path() {
  local encoded_paths="$1"
  activate_logic

  osascript - "$APP_NAME" "$encoded_paths" <<'APPLESCRIPT' >/dev/null
on splitText(theText, delimiter)
  set oldDelimiters to AppleScript's text item delimiters
  set AppleScript's text item delimiters to delimiter
  set theItems to text items of theText
  set AppleScript's text item delimiters to oldDelimiters
  return theItems
end splitText

on run argv
  set appName to item 1 of argv
  set encodedPaths to item 2 of argv
  set pathsToTry to my splitText(encodedPaths, linefeed)

  tell application "System Events"
    tell process appName
      repeat with encodedPath in pathsToTry
        if encodedPath is not "" then
          set parts to my splitText(encodedPath as text, " > ")
          try
            set currentMenu to menu (item 1 of parts) of menu bar 1
            repeat with i from 2 to count of parts
              set partName to item i of parts
              if i is (count of parts) then
                click menu item partName of currentMenu
                return encodedPath
              else
                set currentMenu to menu 1 of menu item partName of currentMenu
              end if
            end repeat
          end try
        end if
      end repeat
    end tell
  end tell

  error "No matching menu path found"
end run
APPLESCRIPT
}

choose_file_in_dialog() {
  local file_path="$1"
  osascript - "$file_path" <<'APPLESCRIPT'
on run argv
  set filePath to item 1 of argv
  set oldClipboard to the clipboard
  tell application "System Events"
    keystroke "g" using {command down, shift down}
    delay 0.4
    keystroke "a" using {command down}
    delay 0.1
    set the clipboard to filePath
    keystroke "v" using {command down}
    delay 0.2
    key code 36
    delay 0.8
    key code 36
  end tell
  delay 0.2
  set the clipboard to oldClipboard
end run
APPLESCRIPT
}

select_file_with_peekaboo() {
  local file_path="$1"
  local base_name
  base_name="$(basename "$file_path")"

  command -v peekaboo >/dev/null 2>&1 || return 1

  local components
  components="$(python3 - "$file_path" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1]).resolve()
root = Path.home() / "Music" / "Logic"
try:
    rel = path.parent.relative_to(root)
except ValueError:
    raise SystemExit(1)
for part in rel.parts:
    print(part)
PY
)" || return 1

  peekaboo app switch com.apple.logic10 >/dev/null 2>&1 || true
  sleep 0.3

  peekaboo click --app com.apple.logic10 --coords 374,289 --global-coords --foreground >/dev/null 2>&1 || \
    peekaboo click "Logic" --app com.apple.logic10 --foreground --wait-for 3000 >/dev/null 2>&1 || return 1
  sleep 0.2

  local part
  while IFS= read -r part; do
    [[ -n "$part" ]] || continue
    peekaboo click "$part" --app com.apple.logic10 --double --foreground --wait-for 3000 >/dev/null 2>&1 || \
      peekaboo click --app com.apple.logic10 --coords 570,267 --global-coords --double --foreground >/dev/null 2>&1 || return 1
    sleep 0.3
  done <<< "$components"

  peekaboo click "$base_name" --app com.apple.logic10 --foreground --wait-for 3000 >/dev/null 2>&1 || \
    peekaboo click --app com.apple.logic10 --coords 610,267 --global-coords --foreground >/dev/null 2>&1 || return 1
  sleep 0.2
  osascript <<'APPLESCRIPT'
tell application "System Events" to key code 36
APPLESCRIPT
}

import_midi() {
  if (( $# != 1 )); then
    usage >&2
    exit 64
  fi

  local midi_path
  midi_path="$(absolute_path "$1")"
  if [[ ! -f "$midi_path" ]]; then
    printf 'MIDI file not found: %s\n' "$midi_path" >&2
    exit 66
  fi

  require_accessibility
  click_first_existing_menu_path $'파일 > 가져오기 > MIDI 파일…\nFile > Import > MIDI File...'
  sleep 0.8
  if ! select_file_with_peekaboo "$midi_path"; then
    choose_file_in_dialog "$midi_path"
  fi
  printf 'imported=%s\n' "$midi_path"
}

generate_and_import_midi() {
  if (( $# < 1 || $# > 2 )); then
    usage >&2
    exit 64
  fi

  local project_path output_dir output_path filename
  project_path="$(require_current_project)"
  output_dir="$(project_generated_dir "$project_path")"
  mkdir -p "$output_dir"

  if (( $# == 2 )); then
    filename="$2"
    [[ "$filename" == *.mid ]] || filename="${filename}.mid"
    output_path="$output_dir/$filename"
  else
    output_path="$output_dir/$(basename "$(python3 "$SCRIPT_DIR/generate_midi.py" "$1" --print-default-path)")"
  fi

  python3 "$SCRIPT_DIR/generate_midi.py" "$1" --output "$output_path"
  import_midi "$output_path"
  printf 'project=%s\n' "$project_path"
}

command="${1:-}"
shift || true

case "$command" in
  status)
    status
    ;;
  doctor)
    doctor
    ;;
  open-project)
    open_project "$@"
    ;;
  current-project)
    current_project
    ;;
  launch|focus)
    activate_logic
    status
    ;;
  check-accessibility)
    check_accessibility
    ;;
  play-toggle)
    send_keycode 49
    ;;
  play-from-beginning)
    play_from_beginning
    ;;
  record-toggle)
    send_key r
    ;;
  generate-midi)
    generate_midi "$@"
    ;;
  generate-midi-in-project)
    generate_midi_in_project "$@"
    ;;
  open-midi)
    open_midi "$@"
    ;;
  import-midi)
    import_midi "$@"
    ;;
  generate-and-import-midi)
    generate_and_import_midi "$@"
    ;;
  go-to-beginning)
    send_keycode 36
    ;;
  cycle-toggle)
    send_key c
    ;;
  metronome-toggle)
    send_key k
    ;;
  save)
    send_key s command
    ;;
  bounce)
    send_key b command
    ;;
  new-audio-track)
    send_key a option,command
    ;;
  new-software-track)
    send_key s option,command
    ;;
  key)
    if (( $# < 1 || $# > 2 )); then
      usage >&2
      exit 64
    fi
    send_key "$1" "${2:-}"
    ;;
  keycode)
    if (( $# < 1 || $# > 2 )); then
      usage >&2
      exit 64
    fi
    send_keycode "$1" "${2:-}"
    ;;
  menu)
    click_menu_path "$@"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    printf 'Unknown command: %s\n\n' "$command" >&2
    usage >&2
    exit 64
    ;;
esac
