#!/usr/bin/env bash

# Rofi/dmenu/wofi frontend for password-store with typing or clipboard copy:
# Fuzzy search, select and type/paste passwords managed by password-store.
# Typing: X11 uses xdotool. Wayland uses wtype when `wtype -s 1` succeeds,
# else ydotool while ydotoold is running, else wdotool.
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
notify=""
[[ ! -t 1 && -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && command -v notify-send >/dev/null 2>&1 && notify=1

# Print to stderr and, when started without a terminal (say, by a key
# binding), also show a desktop notification.
report_error() {
  local summary=$1 body=${2:-}
  printf '%s\n' "$summary" ${body:+"$body"} >&2
  [[ -z "$notify" ]] || notify-send --urgency=critical "$summary" "$body" || true
}

# Error handler (with optional desktop notification)
error_handler() {
  trap - ERR
  set +o errexit +o errtrace

  local line="${1:-?}" caller_line="${2:-?}" cmd="${3:-?}" status="${4:-1}"
  local summary="Error: In ${BASH_SOURCE[0]}, Lines ${line} and ${caller_line}, Command ${cmd} exited with Status ${status}"
  local body=""

  if [[ "$line" =~ ^[0-9]+$ ]] && command -v pr >/dev/null 2>&1; then
    local start=$(( line - 3 ))
    (( start < 1 )) && start=1
    local mark=$(( line - start + 1 ))
    body="$(pr -tn "${BASH_SOURCE[0]}" | tail -n +"$start" | head -n 7 | sed "${mark}s/^[[:space:]]*/>> /")"
  fi

  report_error "$summary" "$body"
  exit "$status"
}
trap 'error_handler "$LINENO" "${BASH_LINENO[0]:-}" "$BASH_COMMAND" "$?"' ERR

die() {
  report_error "Error: $*"
  exit 1
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
Usage: pass select [--type|--clip]

Select an entry from password-store and type or copy its OTP, if it has one,
or else its password (first line).
Enter performs the default action (typing unless overridden by --clip).
When using rofi, Ctrl+Y copies to clipboard.

Options:
  --type     Force typing (default).
  --clip     Force clipboard copy.
  -h, --help Show this help.
USAGE
}

action_default="type"
case "${1-}" in
  -h|--help) usage; exit 0 ;;
  --type) action_default="type"; shift ;;
  --clip|--clipboard) action_default="clip"; shift ;;
  '') ;;
  *) usage >&2; die "Unknown argument: $1" ;;
esac
(( $# == 0 )) || { usage >&2; die "Unexpected argument: $1"; }

have_cmd pass || die "pass (password-store) is required"

PROMPT='❯ '
rofi_args=(-dmenu -i -sort -p "$PROMPT" -kb-accept-entry "Return,KP_Enter" -kb-custom-1 "Control+y")

menu_tool=""
menu_args=()

clipboard_tool=""
clipboard_args=()

if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  session="Wayland"
  if have_cmd rofi-wayland; then
    menu_tool="rofi-wayland"
    menu_args=("${rofi_args[@]}")
  elif have_cmd rofi; then
    menu_tool="rofi"
    menu_args=("${rofi_args[@]}")
  elif have_cmd wofi; then
    menu_tool="wofi"
    menu_args=(--dmenu --prompt "$PROMPT")
  else
    die "No suitable menu engine found (rofi/rofi-wayland or wofi)"
  fi

  if have_cmd wl-copy; then
    clipboard_tool="wl-copy"
  fi
elif [[ -n "${DISPLAY:-}" ]]; then
  session="X11"
  if have_cmd rofi; then
    menu_tool="rofi"
    menu_args=("${rofi_args[@]}")
  elif have_cmd dmenu; then
    menu_tool="dmenu"
    menu_args=(-p "$PROMPT")
  else
    die "No suitable menu engine found (rofi or dmenu)"
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

# `-s 1` connects and sleeps 1ms. It types nothing. Failure means this
# compositor has no virtual-keyboard protocol (Mutter, KWin).
wtype_protocol() {
  have_cmd wtype || return 1
  wtype -s 1 >/dev/null 2>&1
}

# ydotoold holds /dev/uinput. Without that daemon, ydotool cannot inject.
ydotool_ready() {
  have_cmd ydotool || return 1
  pgrep -x ydotoold >/dev/null 2>&1
}

# Sets type_tool and type_args. Only needed (and checked) when typing.
find_type_tool() {
  if [[ "$session" == "Wayland" ]]; then
    if wtype_protocol; then
      type_tool="wtype"
      type_args=(-)
    elif ydotool_ready; then
      type_tool="ydotool"
      type_args=(type --file -)
    elif have_cmd wdotool; then
      type_tool="wdotool"
      type_args=(type --delay 0 --clearmodifiers --file -)
    else
      die "No suitable typing tool found on Wayland (wtype, ydotool with ydotoold, or wdotool); use --clip to copy instead"
    fi
  elif have_cmd xdotool; then
    type_tool="xdotool"
    type_args=(type --clearmodifiers --delay 50 --file -)
  else
    die "No suitable typing tool found on X11 (xdotool); use --clip to copy instead"
  fi
}

dir="${PASSWORD_STORE_DIR:-"$HOME/.password-store"}"
[[ -d "$dir" ]] || die "Password store directory not found: $dir"
dir=$(
  cd -P -- "$dir" 2>/dev/null && pwd -P
) || die "Password store directory invalid: $dir"

password_files=()
while IFS= read -r -d '' f; do
  rel=${f#"$dir"/}
  password_files+=("${rel%.gpg}")
done < <(
  find "$dir" -type f -name '*.gpg' -not -path '*/.git/*' -print0 | LC_ALL=C sort -z
)

(( ${#password_files[@]} )) || die "No .gpg entries found under: $dir"

# The OTP if the entry has one, else its first line (the password).
# `sed -n 1p` reads all input (no SIGPIPE for `pass` under pipefail) and,
# unlike `read`, keeps a last line that lacks a trailing newline.
read_secret() {
  pass otp "$1" 2>/dev/null || pass show "$1" | sed -n 1p
}

copy_to_clipboard() {
  [[ -n "$clipboard_tool" ]] || return 1
  # xclip and xsel keep running in the background to serve the selection.
  printf '%s' "$1" | "$clipboard_tool" "${clipboard_args[@]}" >/dev/null 2>&1
}

# entry selection; a non-zero status means cancelled or (rofi) a custom key
rc=0
password="$(printf '%s\n' "${password_files[@]}" | "$menu_tool" "${menu_args[@]}")" || rc=$?

[[ -n "${password:-}" ]] || exit 0

action="$action_default"
if [[ "$menu_tool" == "rofi" || "$menu_tool" == "rofi-wayland" ]]; then
  case "$rc" in
    0) ;;                # Enter.
    10) action="clip" ;; # Ctrl+Y (custom-1).
    *) exit 0 ;;
  esac
fi

if [[ "$action" == "clip" ]]; then
  # Prefer `pass -c`, which clears the clipboard after a while.
  pass otp -c "$password" >/dev/null 2>&1 || pass show -c "$password" >/dev/null 2>&1 || {
    secret="$(read_secret "$password")" || die "Could not decrypt: $password"
    copy_to_clipboard "$secret" || die "Clipboard copy failed (install wl-copy on Wayland, or xclip/xsel on X11)"
  }
  exit 0
fi

find_type_tool
secret="$(read_secret "$password")" || die "Could not decrypt: $password"
printf '%s' "$secret" | "$type_tool" "${type_args[@]}"

# Release modifier keys to avoid them getting stuck
# See https://github.com/jordansissel/xdotool/issues/43
if [[ "$type_tool" == "xdotool" ]]; then
  xdotool sleep 0.4 keyup Meta_L Meta_R Alt_L Alt_R Super_L Super_R Control_L Control_R Shift_L Shift_R
fi
