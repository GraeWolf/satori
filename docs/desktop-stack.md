# Desktop Stack

herbstluftwm on Xorg. Everything a desktop environment would normally provide is
chosen explicitly here. All of it is pulled in by the `satori-desktop` metapackage
and configured by `satori-config`.

> Package names are **proposed**. Phase 2 has to check each one exists in
> Excalibur and passes the no-systemd check. Record substitutions in the
> table's Notes column.

## 1. Components

| Role | Choice | Notes |
|---|---|---|
| Display server | `xlibre` (metapackage), `xinit` | X11 only (DEC-004). XLibre from its third-party repo plus Excalibur backports (DEC-027). Check NVIDIA proprietary driver compatibility |
| Login | tty1 login → `startx` (DEC-014) | Live session: autologin on tty1 |
| Seat/session | `elogind`, `libpam-elogind`, `polkitd` | Rootless X, device access, lid/power keys |
| Window manager | `herbstluftwm` | |
| Bar | `polybar` | Tags, window title, network, volume, battery, clock, tray |
| Launcher | `rofi` | App launcher, window switcher, power menu |
| Notifications | `dunst` | |
| Compositor | `picom` | Tear-free, minimal effects |
| Polkit agent | `lxpolkit` | Needed for GUI privilege prompts |
| Screen lock | `xss-lock` + `i3lock` | Locks on suspend and idle |
| Network UI | `network-manager` (`nmcli`, `nmtui`) | DEC-011. No tray applet. Clicking polybar's network module opens `nmtui` in a terminal |
| Audio | `pipewire`, `pipewire-pulse`, `wireplumber`, `pavucontrol`, `pamixer` | DEC-012 |
| Bluetooth | `bluez`, `blueman` | |
| Power/laptop | elogind (lid/suspend/hibernate, DEC-017), `brightnessctl`, `tlp` | Check that tlp has no systemd dependency |
| Terminal | `alacritty` | `x-terminal-emulator` alternative |
| File manager | `thunar` + `gvfs`, `tumbler` | Removable media and trash. `tumbler` provides Thunar's thumbnails |
| Editor | `neovim` (CLI) + `mousepad` (GUI) | |
| Browser | `brave-origin` (default), `firefox-esr` (fallback) | DEC-028. Brave Origin from Brave's APT repo (DEC-026). Default set through `x-www-browser` and `mimeapps.list` in `/etc/skel`. Firefox policies in satori-config |
| Keyring | `gnome-keyring`, `libpam-gnome-keyring` | DEC-030. Secret Service for Brave, Melia, Firefox and NetworkManager. Unlocked by PAM at tty1 login |
| Email | Melia, not preinstalled | DEC-029. `satori-get-melia` downloads and verifies the signed `.deb` on demand |
| Screenshots | `maim` + `xclip` | Bound to Print |
| Clipboard | `xclip`, `clipmenu` | |
| Images/PDF | `feh` (also sets wallpaper), `zathura` | |
| Fonts | `fonts-noto`, `fonts-noto-color-emoji`, `fonts-jetbrains-mono` | |
| Theming | GTK theme and icon theme TBD in Phase 4, `lxappearance` | |
| Firewall | `nftables` + satori ruleset | DEC-023 |
| Time sync | `chrony` | DEC-024. Must not use systemd-timesyncd |

Optional `developer.list.chroot`: `git`, `build-essential`, `curl`, `jq`, `ripgrep`, `fd-find`, `tmux`, `shellcheck`.

## 2. Session startup

With no systemd user services, `~/.xinitrc` (from `/etc/skel`) is the session's
supervisor. Order matters:

1. `~/.profile` on tty1: if `$DISPLAY` is unset and the tty is tty1, `exec startx`.
2. `~/.xinitrc`:
   - `dbus-launch --exit-with-session` wraps the session, so it has its own D-Bus session bus.
   - `gnome-keyring-daemon --start --components=secrets` runs inside that bus and exports its environment. PAM already unlocked the keyring at login, so no password prompt appears.
   - `exec herbstluftwm`
3. herbstluftwm's `autostart` (system default at `/etc/xdg/herbstluftwm/autostart`, user override at `~/.config/herbstluftwm/autostart`) sets keybindings, tags, and rules, then starts, once each:
   - `pipewire` (which starts `wireplumber` and `pipewire-pulse` through its own config), unless it's already running
   - `lxpolkit`, `picom`, `dunst`, `blueman-applet`
   - `xss-lock -- i3lock ...`
   - `feh --bg-fill` wallpaper
   - `polybar`

Autostart scripts must be safe to re-run, because herbstluftwm re-runs autostart on
reload. Use `pgrep`-guards or a small `satori-run-once` helper.

## 3. Keybindings (defaults)

`Mod` = Super. The full list ships as `/usr/share/doc/satori-config/keybindings.md`
and in a rofi cheatsheet on `Mod+F1`.

| Keys | Action |
|---|---|
| `Mod+Return` | Terminal |
| `Mod+Space` | rofi launcher |
| `Mod+Shift+Space` | Cycle frame layout (herbstluftwm's default was `Mod+Space`) |
| `Mod+Tab` | rofi window switcher |
| `Mod+1..9` / `Mod+Shift+1..9` | Switch to / move window to tag |
| `Mod+h/j/k/l` | Focus left/down/up/right |
| `Mod+Shift+h/j/k/l` | Move window |
| `Mod+u` / `Mod+o` | Split vertical / horizontal |
| `Mod+r` | Remove frame |
| `Mod+f` / `Mod+s` | Fullscreen / toggle floating |
| `Mod+w` | Close window |
| `Mod+Shift+r` | Reload herbstluftwm |
| `Mod+Escape` | Lock screen |
| `Mod+Shift+e` | rofi power menu (logout, suspend, hibernate, reboot, poweroff) |
| `Mod+F1` | Keybinding cheatsheet |
| `Mod+p` / `Mod+Shift+p` | Screenshot full / selection (replaces herbstluftwm's default `Mod+p` pseudotile, which is left unbound) |
| Media / brightness keys | pamixer / brightnessctl |

## 4. Configuration ownership

- System defaults live under `/etc/xdg/...` and `/etc/skel/`, shipped by `satori-config`.
- User config under `~/.config` always wins. satori never writes to an existing home directory after install.
- `satori-config` upgrades never touch user files. Changes to `/etc/skel` only affect newly created users.
