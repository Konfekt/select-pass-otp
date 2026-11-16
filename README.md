This is a [password-store](https://www.passwordstore.org/) extension script to select and type / copy passwords and OTPs using a menu tool (ideally opened by a system key binding).

# Desktop OTP generator with pass and select.bash

Typically mobile authenticator apps are used to generate one-time passwords (OTP) for two-factor authentication (2FA).
However, the sites requiring 2FA are often accessed on desktop computers, and typing OTPs from a phone is tedious and error-prone.

So a desktop OTP generator is called for.
On Linux, there is [GNOME Authenticator](https://gitlab.gnome.org/World/Authenticator) available via [Flatpak](https://flatpak.org/) or [Snap](https://snapcraft.io/), but some might prefer more minimalist setups built around the command-line manager [pass](https://www.passwordstore.org/) which can generate OTPs as well with its [pass-otp](https://github.com/tadfisher/pass-otp) extension, a simple bash script.

To migrate existing OTP tokens from your mobile app to pass, say from Android [Aegis Authenticator](https://github.com/beemdevelopment/Aegis), first migrate your tokens with [pass-import](https://github.com/roddhjav/pass-import).
(Plenty other imports [are supported](https://github.com/roddhjav/pass-import#description) as well, among them [1Password](https://1password.com/), [Bitwarden](https://bitwarden.com/), [KeePassXC](https://keepassxc.org/), [LastPass](https://www.lastpass.com/), and [Firefox](https://support.mozilla.org/en-US/kb/lockwise-manage-your-saved-logins).)

Then with the accompanying `select.bash` script, browse pass entries through a menu tool (such as [rofi](https://github.com/davatorium/rofi) or [dmenu](https://tools.suckless.org/dmenu/)) to type or copy both passwords and OTPs.

# Install prerequisites

Required:

- `bash`
- `pass` (password-store) with working GPG

One menu frontend (required):

- X11: [`rofi`](https://github.com/davatorium/rofi) or [`dmenu`](https://tools.suckless.org/dmenu/)
- Wayland: Wayland-capable `rofi` (also found as `rofi-wayland`) or [`wofi`](https://hg.sr.ht/~scoopta/wofi)

One typing tool, to type the secret into the focused window (the default action):

- X11: [`xdotool`](https://github.com/jordansissel/xdotool)
- Wayland, tried in this order:
  [`wtype`](https://github.com/atx/wtype) (needs a compositor with the virtual-keyboard protocol, such as Sway or Hyprland, but not GNOME or KDE),
  [`ydotool`](https://github.com/ReimuNotMoe/ydotool) (needs the `ydotoold` daemon running), or `wdotool`

A clipboard tool, to copy instead of type (`--clip` or `Ctrl+Y` in rofi):

- X11: [`xclip`](https://github.com/astrand/xclip) (or `xsel`)
- Wayland: [`wl-clipboard`](https://github.com/bugaevc/wl-clipboard) (`wl-copy`)

Copying goes through `pass -c`, which clears the clipboard after `PASSWORD_STORE_CLIP_TIME` seconds (default 45).
Only if that fails does the script copy with `wl-copy`, `xclip` or `xsel` itself, and then the clipboard is not cleared.

Optional OTP support:

- [`pass-otp`](https://github.com/tadfisher/pass-otp) (adds `pass otp`)

Optional token import:

- [`pass-import`](https://github.com/roddhjav/pass-import)
- If using `uv`: `uv` and Python >= 3.10

Optional notifications:

- `notify-send` (libnotify)

# Install `select.bash` as a `pass` extension

`pass` runs extensions from a system extension directory (such as `/usr/lib/password-store/extensions`) or, only if `PASSWORD_STORE_ENABLE_EXTENSIONS=true` is set, from the user directory `$PASSWORD_STORE_EXTENSIONS_DIR` (default `~/.password-store/.extensions/`).

Install user-local:

```bash
mkdir -p ~/.password-store/.extensions
curl -fsSL -o ~/.password-store/.extensions/select.bash https://github.com/Konfekt/select-pass-otp/raw/refs/heads/main/select.bash
chmod +x ~/.password-store/.extensions/select.bash
```

and enable user extensions in the environment of your session (not only of your shell, if `pass select` is started by a key binding), say in `~/.profile`:

```bash
export PASSWORD_STORE_ENABLE_EXTENSIONS=true
```

If `select.bash` already exists elsewhere, prefer a symlink:

```bash
ln -sf ~/bin/select.bash ~/.password-store/.extensions/select.bash
```

`select.bash` also runs standalone, without being a `pass` extension.

# Usage

Interactive selection:

```bash
pass select
```

Force clipboard mode:

```bash
pass select --clip
```

For the selected entry, the OTP (`pass otp`) is used if the entry has one, otherwise its password (the first line).

- `rofi`: `Enter` types into the focused window (or copies, with `--clip`), and `Ctrl+Y` copies to the clipboard.
- `dmenu`/`wofi`: `Enter` types, or copies with `--clip`.

Set `TRACE=1` to trace the script for debugging.
When started without a terminal, errors are also shown as desktop notifications if `notify-send` is installed.

# Bind `pass select` to `Meta+P`

X11 example with `xbindkeys`:

```text
"pass select"
  Mod4 + p
```

Wayland compositor bindings:

- Sway: `bindsym $mod+p exec pass select`
- Hyprland: `bind = SUPER, P, exec, pass select`
- GNOME: Settings -> Keyboard -> Custom Shortcuts -> command `pass select`

# Import tokens (example: Aegis)

Install `pass-import` via `uv`:

```bash
uv tool install --python 3.13 pass-import --with cryptography
```

Import Aegis export into a subfolder:

```bash
pimport pass /path/to/aegis-export.json -o ~/.password-store/otp
```

Verify:

```bash
pass otp otp/<imported-entry-name>
```

# Development

Lint and run the smoke tests (which stub `pass` and the menu, typing and clipboard tools):

```bash
shellcheck select.bash tests/smoke.bash
bash tests/smoke.bash
```
