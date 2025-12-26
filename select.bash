#!/usr/bin/env bash

# Rofi/dmenu/wofi frontend for password-store with typing or clipboard copy:
# Fuzzy search, select and type/paste passwords managed by password-store.
# Based on https://github.com/petrmanek/passmenu-otp, which is
# based on https://git.zx2c4.com/password-store/tree/contrib/dmenu/passmenu

# trace exit on error of program or pipe (or use of undeclared variable)
set -o errtrace -o errexit -o pipefail # -o nounset
# optionally debug output by supplying TRACE=1
[[ "${TRACE:-0}" == "1" ]] && set -o xtrace
if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
  shopt -s inherit_errexit
fi

PS4='+\t '
[[ ! -t 1 && -n "$DBUS_SESSION_BUS_ADDRESS" ]] && command -v notify-send >/dev/null 2>&1 && notify=1

# Error handler (with optional desktop notification)
error_handler() {
  trap - ERR
  set +o errexit +o errtrace

  local line="${1:-?}" caller_line="${2:-?}" cmd="${3:-?}" status="${4:-1}"
  local summary="Error: In ${BASH_SOURCE[0]}, Lines ${line} and ${caller_line}, Command ${cmd} exited with Status ${status}"
  local body=""

  if [[ "$line" =~ ^[0-9]+$ ]] && command -v pr >/dev/null 2>&1 && command -v sed >/dev/null 2>&1; then
    local start=$(( line - 3 ))
    (( start < 1 )) && start=1
    local mark=$(( line - start + 1 ))
    body="$(pr -tn "${BASH_SOURCE[0]}" | tail -n +"$start" | head -n 7 | sed "${mark}s/^[[:space:]]*/>> /")"
  fi

  if [[ -n "$body" ]]; then
    printf '%s\n%s\n' "$summary" "$body" >&2
  else
    printf '%s\n' "$summary" >&2
  fi
  [[ -z "${notify:+x}" ]] || notify-send --urgency=critical "$summary" "$body"
  exit "$status"
}
trap 'error_handler "$LINENO" "${BASH_LINENO[0]:-}" "$BASH_COMMAND" "$?"' ERR

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  cat <<'EOF'
Usage: select [--type|--clip]

Select an entry from password-store.
Enter performs the default action (typing unless overridden by --clip).
When using rofi, Ctrl+Y copies to clipboard.

Options:
  --type     Force typing (default on non-rofi menus).
  --clip     Force clipboard copy.
EOF
  exit 0
fi

have_cmd pass || die "pass (password-store) is required"

PROMPT='❯ '

action_default="type"
case "${1-}" in
  --type) action_default="type"; shift ;;
  --clip|--clipboard) action_default="clip"; shift ;;
  *) ;;
esac

menu_tool=""
menu_args=()

type_tool=""
type_args=()

clipboard_tool=""
clipboard_args=()

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  if have_cmd rofi-wayland; then
    menu_tool="rofi-wayland"
    menu_args=(-dmenu -i -sort -p "$PROMPT" -kb-accept-entry "Return,KP_Enter" -kb-custom-1 "Control+y")
  elif have_cmd rofi; then
    menu_tool="rofi"
    menu_args=(-dmenu -i -sort -p "$PROMPT" -kb-accept-entry "Return,KP_Enter" -kb-custom-1 "Control+y")
  elif have_cmd wofi; then
    menu_tool="wofi"
    menu_args=(--dmenu --prompt "$PROMPT")
  else
    die "No suitable menu engine found (rofi/rofi-wayland or wofi)"
  fi

  if have_cmd wtype; then
    type_tool="wtype"
    type_args=(-)
  elif have_cmd ydotool; then
    type_tool="ydotool"
    type_args=(type --file -)
  else
    die "No suitable typing tool found on Wayland (ydotool)"
  fi

  if have_cmd wl-copy; then
    clipboard_tool="wl-copy"
    clipboard_args=()
  fi
elif [[ -n "${DISPLAY:-}" ]]; then
  if have_cmd rofi; then
    menu_tool="rofi"
    menu_args=(-dmenu -i -sort -p "$PROMPT" -kb-accept-entry "Return,KP_Enter" -kb-custom-1 "Control+y")
  elif have_cmd dmenu; then
    menu_tool="dmenu"
    menu_args=(-p "$PROMPT")
  else
    die "No suitable menu engine found (rofi or dmenu)"
  fi

  if have_cmd xdotool; then
    type_tool="xdotool"
    type_args=(type --clearmodifiers --delay 50 --file -)
  else
    die "No suitable typing tool found on X11 (xdotool)"
  fi

  if have_cmd xclip; then
    clipboard_tool="xclip"
    clipboard_args=(-selection clipboard -in)
  elif have_cmd xsel; then
    clipboard_tool="xsel"
    clipboard_args=(--clipboard --input)
  fi
else
  die "No Wayland or X11 display detected"
fi

dir="${PASSWORD_STORE_DIR:-"$HOME/.password-store"}"
[[ -d "$dir" ]] || die "Password store directory not found: $dir"
dir=$(
  cd -P -- "$dir" 2>/dev/null && pwd -P
) || die "Password store directory invalid: $dir"

password_files=()
while IFS= read -r -d '' f; do
  rel=${f#"$dir"/}
  rel=${rel%.gpg}
  password_files+=("$rel")
done < <(
  find "$dir" -type f -name '*.gpg' -not -path '*/.git/*' -print0
)

if [[ "${#password_files[@]}" -eq 0 ]]; then
  die "No .gpg entries found under: $dir"
fi

mapfile -t password_files < <(printf '%s\n' "${password_files[@]}" | LC_ALL=C sort)

first_line_from_stream() {
  local line first='' have_first=0
  while IFS= read -r line; do
    if (( !have_first )); then
      first=$line
      have_first=1
    fi
  done
  printf '%s' "$first"
}

copy_to_clipboard() {
  local text=$1

  if [[ -n "$clipboard_tool" ]]; then
    case "$clipboard_tool" in
      wl-copy|pbcopy)
        printf '%s' "$text" | "$clipboard_tool" "${clipboard_args[@]}"
        ;;
      xclip|xsel)
        { printf '%s' "$text"; } | "$clipboard_tool" "${clipboard_args[@]}" >/dev/null 2>&1 &
        ;;
      *)
        return 1
        ;;
    esac
    return 0
  fi

  return 1
}

errtrace_was_set=0
errexit_was_set=0
[[ "$-" == *E* ]] && errtrace_was_set=1
[[ "$-" == *e* ]] && errexit_was_set=1
old_err_trap="$(trap -p ERR)"
set +eE
trap ':' ERR

# entry selection
password="$(printf '%s\n' "${password_files[@]}" | "${menu_tool}" "${menu_args[@]}")"
rc=$?

(( errtrace_was_set )) && set -E
(( errexit_was_set )) && set -e
eval "$old_err_trap"

[[ -n "${password:-}" ]] || exit 0

action="$action_default"
if [[ "$menu_tool" == "rofi" || "$menu_tool" == "rofi-wayland" ]]; then
  case "$rc" in
    0) action="$action_default" ;; # Enter.
    10) action="clip" ;;           # Ctrl+Y (custom-1).
    *) exit 0 ;;
  esac
fi

if [[ "$action" == "clip" ]]; then
  pass otp -c "$password" >/dev/null 2>&1 || pass show -c "$password" >/dev/null 2>&1 || {
    secret=""
    if secret="$(pass otp "$password" 2>/dev/null)"; then
      :
    else
      secret="$(pass show "$password" | first_line_from_stream)"
    fi
    copy_to_clipboard "$secret" || die "Clipboard copy failed (install wl-copy on Wayland, or xclip/xsel on X11)"
  }
  exit 0
fi

secret=""
if secret="$(pass otp "$password" 2>/dev/null)"; then
  :
else
  secret="$(pass show "$password" | first_line_from_stream)"
fi

printf '%s' "$secret" | "$type_tool" "${type_args[@]}"

# Release modifier keys to avoid them getting stuck
# See https://github.com/jordansissel/xdotool/issues/43
if [[ "$type_tool" == "xdotool" ]]; then
  xdotool sleep 0.4 keyup Meta_L Meta_R Alt_L Alt_R Super_L Super_R Control_L Control_R Shift_L Shift_R
fi
