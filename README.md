This is a [password-store](https://www.passwordstore.org/) extension script to select and type / copy passwords and OTPs using a menu tool (ideally opened by a system key binding).

# Desktop OTP generator with pass and select.bash

Typically mobile authenticator apps are used to generate one-time passwords (OTP) for two-factor authentication (2FA).
However, the sites requiring 2FA are often accessed on desktop computers, and typing OTPs from a phone is tedious and error-prone.

So a desktop OTP generator is called for.
On Linux, there is [GNOME Authenticator](https://gitlab.gnome.org/World/Authenticator) available via [Flatpak](https://flatpak.org/) or [Snap](https://snapcraft.io/), but some might prefer more minimalist setups built around the command-line manager [pass](https://www.passwordstore.org/) which can generate OTPs as well with its [pass-otp](https://github.com/tadfisher/pass-otp) extension, a simple bash script.

To migrate existing OTP tokens from your mobile app to pass, say from Android [Aegis Authenticator](https://github.com/beemdevelopment/Aegis), first migrate your tokens with [pass-import](https://github.com/roddhjav/pass-import).
(Plenty other imports [are supported](https://github.com/roddhjav/pass-import#description) as well, among them [1Password](https://1password.com/), [Bitwarden](https://bitwarden.com/), [KeePassXC](https://keepassxc.org/), [LastPass](https://www.lastpass.com/), and [Firefox](https://support.mozilla.org/en-US/kb/lockwise-manage-your-saved-logins).)

Then with the accompanying `select.bash` script, browse pass entries through a menu tool (such as [rofi](https://github.com/davatorium/rofi) or [dmenu](https://tools.suckless.org/dmenu/)) to paste or copy both passwords and OTPs.

For basic password copying you need only:  

- [pass](https://www.passwordstore.org/) (password-store) with a working GPG setup,
- a menu frontend ([rofi](https://github.com/davatorium/rofi) or [dmenu](https://tools.suckless.org/dmenu/)), and
- a clipboard tool such as [xclip](https://github.com/astrand/xclip) on X11 or [wl-clipboard](https://github.com/bugaevc/wl-clipboard)/ on Wayland (most desktop environments already include these tools).

For typing passwords instead of copying them to clipboard, you need a typing tool such as [xdotool](https://github.com/jordansissel/xdotool) (X11) or [wtype](https://github.com/atx/wtype) / [ydotool](https://github.com/ReimuNotMoe/ydotool) (Wayland).

For OTP support and token import, you need [pass-otp](https://github.com/tadfisher/pass-otp) respectively [pass-import](https://github.com/roddhjav/pass-import). 

# Install prerequisites

Install core:

- `bash`
- `pass` (password-store) with working GPG

Install one menu frontend:

- X11: `rofi` or `dmenu`
- Wayland: `wofi` or Wayland-capable `rofi` (often packaged as `rofi-wayland`, invoked as `rofi`)

Install one clipboard tool:

- X11: `xclip` or `xsel`
- Wayland: `wl-clipboard` (`wl-copy`, `wl-paste`)

Note: `pass -c` is guaranteed to work with `xclip`/`xsel`; some `pass` builds also support `wl-copy`.

Optionally install one typing tool (to type secret into focused window):

- X11: `xdotool`
- Wayland: `wtype` (simpler) or `ydotool` (often requires extra permissions/daemon)

Optional OTP support:

- `pass-otp` (adds `pass otp`)

Optional token import:

- `pass-import`
- If using `uv`: `uv` and Python >= 3.10

Optional notifications:

- `notify-send` (libnotify)

# Install `select.bash` as a `pass` extension

`pass` discovers extensions in `$PASSWORD_STORE_EXTENSIONS_DIR`, `~/.password-store/.extensions/` (user) or a system extension directory.

Install user-local:

```bash
mkdir -p ~/.password-store/.extensions
curl -fsSL -o ~/.password-store/.extensions/select.bash https://github.com/Konfekt/select-pass-otp/raw/refs/heads/main/select.bash
chmod +x ~/.password-store/.extensions/select.bash
```

If `select.bash` already exists elsewhere, prefer a symlink:

```bash
ln -sf ~/bin/select.bash ~/.password-store/.extensions/select.bash
```

If `select.bash` detects OTP fields, selection can call `pass otp` automatically (script behavior).

# Usage

Interactive selection:

```bash
pass select
```

Force clipboard mode:

```bash
pass select --clip
```

Typical behavior (script-dependent):

- `rofi`: Enter types into focused window, and a custom keybinding copies to clipboard.
- `dmenu`/`wofi`: typing is default unless `--clip` is used.

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
