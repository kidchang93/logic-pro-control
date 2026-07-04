#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${LOGIC_APP_NAME:-Logic Pro}"
KEY_DELAY="${LOGIC_KEY_DELAY:-0.15}"

usage() {
  cat <<'EOF'
Usage:
  scripts/logicpro.sh status
  scripts/logicpro.sh doctor
  scripts/logicpro.sh launch
  scripts/logicpro.sh focus
  scripts/logicpro.sh check-accessibility
  scripts/logicpro.sh play-toggle
  scripts/logicpro.sh play-from-beginning
  scripts/logicpro.sh record-toggle
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

command="${1:-}"
shift || true

case "$command" in
  status)
    status
    ;;
  doctor)
    doctor
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
