#!/usr/bin/env bash
# Smoke tests for select.bash with stubbed pass, menu, typing and clipboard
# tools. No display, GPG or password store needed. Run: bash tests/smoke.bash

# shellcheck disable=SC2016 # stub bodies expand when the stubs run
set -o errexit -o nounset -o pipefail

script=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/select.bash
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

# A PATH holding only basic tools plus the stubs that a test enables.
mkdir -p "$tmp/base"
for tool in bash env cat find sort sed head tail pr pgrep mktemp; do
  ln -s "$(command -v "$tool")" "$tmp/base/$tool"
done

stub() { # stub NAME BODY
  printf '#!/usr/bin/env bash\n%s\n' "${2:-$(cat)}" >"$tmp/stubs/$1"
  chmod +x "$tmp/stubs/$1"
}
mkdir -p "$tmp/stubs"
stub pass <<'STUB'
cmd=$1; shift; clip=0
# Without pass-otp, pass runs `pass show otp ...`: the `otp` folder's tree.
if [[ $cmd == otp && -n ${PASS_NO_OTP:-} ]]; then
  printf 'otp\n`-- c\n'; exit 0
fi
[[ $1 == -c ]] && { clip=1; shift; }
f=$PASSWORD_STORE_DIR/$1.gpg
[[ -f $f ]] || exit 1
content=$(<"$f")
case $cmd in
  otp) [[ $content == *otpauth://* ]] || exit 1; out=123456 ;;
  show) out=$content ;;
esac
if (( clip )); then
  [[ -z ${PASS_CLIP_FAILS:-} ]] || exit 1
  printf "pass-clip:%s\n" "${out%%$'\n'*}" >>"$LOG"
else
  if [[ $cmd == show ]]; then cat "$f"; else printf "%s\n" "$out"; fi
fi
STUB
menu='cat >"$MENU_INPUT"; [[ -z ${MENU_PICK:-} ]] || printf "%s\n" "$MENU_PICK"; exit "${MENU_RC:-0}"'
for m in rofi dmenu wofi; do stub "$m" "$menu"; done
stub xdotool '[[ $1 == type ]] && printf "typed:%s\n" "$(cat)" >>"$LOG"; exit 0'
stub wtype '[[ $1 == -s ]] && exit "${WTYPE_FAIL:-0}"; printf "typed:%s\n" "$(cat)" >>"$LOG"'
for c in xclip wl-copy; do stub "$c" 'printf "clip:%s\n" "$(cat)" >>"$LOG"'; done

store=$tmp/store
mkdir -p "$store/web" "$store/otp" "$store/.git"
printf 'nonewline' >"$store/web/a.gpg"
printf 'pw1\nuser: me\n' >"$store/web/b.gpg"
printf 'otpauth://totp/x?secret=ABC\n' >"$store/otp/c.gpg"
printf 'x' >"$store/.git/ignored.gpg"

failures=0
# run NAME EXPECTED_STATUS EXPECTED_LOG TOOLS ENV... -- ARGS...
run() {
  local name=$1 want_status=$2 want_log=$3 tools=$4; shift 4
  local envs=()
  while (( $# )) && [[ $1 != -- ]]; do envs+=("$1"); shift; done
  shift || true
  rm -rf "${tmp:?}/bin" && mkdir "$tmp/bin"
  local t
  for t in $tools; do ln -s "$tmp/stubs/$t" "$tmp/bin/$t"; done
  : >"$tmp/log"
  local status=0
  env -i HOME="$tmp" PATH="$tmp/bin:$tmp/base" PASSWORD_STORE_DIR="$store" \
    LOG="$tmp/log" MENU_INPUT="$tmp/menu_input" "${envs[@]}" \
    bash "$script" "$@" >"$tmp/out" 2>&1 </dev/null || status=$?
  local got_log
  got_log=$(<"$tmp/log")
  if [[ $status == "$want_status" && $got_log == "$want_log" ]]; then
    printf 'ok   %s\n' "$name"
  else
    printf 'FAIL %s: status %s (want %s), log [%s] (want [%s])\n' \
      "$name" "$status" "$want_status" "$got_log" "$want_log"
    sed 's/^/     | /' "$tmp/out"
    failures=$((failures + 1))
  fi
}

x11=(DISPLAY=:0)
way=(WAYLAND_DISPLAY=wayland-0)

run "types password without trailing newline" 0 "typed:nonewline" "pass rofi xdotool" \
  "${x11[@]}" MENU_PICK=web/a
if [[ $(<"$tmp/menu_input") == $'otp/c\nweb/a\nweb/b' ]]; then
  echo "ok   lists sorted entries, skips .git"
else
  echo "FAIL menu input: $(<"$tmp/menu_input")"; failures=$((failures + 1))
fi
run "types first line only" 0 "typed:pw1" "pass rofi xdotool" "${x11[@]}" MENU_PICK=web/b
run "types OTP" 0 "typed:123456" "pass dmenu xdotool" "${x11[@]}" MENU_PICK=otp/c
run "rofi Ctrl+Y copies via pass -c" 0 "pass-clip:pw1" "pass rofi xdotool" \
  "${x11[@]}" MENU_PICK=web/b MENU_RC=10
run "falls back to clipboard tool" 0 "clip:nonewline" "pass rofi xclip" \
  "${x11[@]}" MENU_PICK=web/a MENU_RC=10 PASS_CLIP_FAILS=1
run "--clip needs no typing tool" 0 "pass-clip:123456" "pass dmenu" \
  "${x11[@]}" MENU_PICK=otp/c -- --clip
run "cancel does nothing" 0 "" "pass rofi xdotool" "${x11[@]}" MENU_RC=1
run "rofi other exit code does nothing" 0 "" "pass rofi xdotool" "${x11[@]}" MENU_PICK=web/a MENU_RC=1
run "missing typing tool fails" 1 "" "pass dmenu" "${x11[@]}" MENU_PICK=web/a
run "Wayland types with wtype" 0 "typed:pw1" "pass wofi wtype" "${way[@]}" MENU_PICK=web/b
run "Wayland without usable typing tool fails" 1 "" "pass wofi wtype" \
  "${way[@]}" WTYPE_FAIL=1 MENU_PICK=web/b
run "Wayland clipboard fallback" 0 "clip:pw1" "pass wofi wl-copy" \
  "${way[@]}" PASS_CLIP_FAILS=1 MENU_PICK=web/b -- --clip
run "without pass-otp, a password entry types its password" 0 "typed:pw1" \
  "pass rofi xdotool" "${x11[@]}" PASS_NO_OTP=1 MENU_PICK=web/b
run "without pass-otp, an OTP entry fails instead of typing its URI" 1 "" \
  "pass rofi xdotool" "${x11[@]}" PASS_NO_OTP=1 MENU_PICK=otp/c
run "without pass-otp, copying an OTP entry fails" 1 "" "pass rofi xclip" \
  "${x11[@]}" PASS_NO_OTP=1 MENU_PICK=otp/c -- --clip
run "no display fails" 1 "" "pass rofi xdotool"
run "missing pass fails" 1 "" "rofi xdotool" "${x11[@]}"
run "--help" 0 "" "" -- --help
run "unknown argument fails" 1 "" "pass rofi xdotool" "${x11[@]}" -- --bogus

(( failures == 0 )) || { echo "$failures test(s) failed"; exit 1; }
echo "all tests passed"
