# Desktop Stack

herbstluftwm on Xorg. Everything a desktop environment would normally provide is
chosen explicitly here. All of it is pulled in by the `satori-desktop` metapackage
and configured by `satori-config`.

> Phase 2 checked every package: all exist in Excalibur (or in the Brave and
> XLibre repositories, DEC-026), and resolving the whole stack from an empty
> system pulls in no systemd package. Substitutions are in the Notes column.
> `packages/satori-desktop/debian/control` is the authoritative list.

## 1. Components

| Role | Choice | Notes |
|---|---|---|
| Display server | `xlibre` (metapackage), `xinit` | X11 only (DEC-004). XLibre from its third-party repo plus Excalibur backports (DEC-027). Check NVIDIA proprietary driver compatibility |
| Login | tty1 login → `startx` (DEC-014) | Live session: autologin on tty1 |
| Seat/session | `elogind`, `libpam-elogind`, `polkitd` | Rootless X, device access, lid/power keys. Devuan's `libelogind-compat` replaces `libsystemd0` in the desktop image, and `udev` is Devuan's transitional package for `eudev` |
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
| Browser | `brave-origin` (default), `firefox-esr` (fallback) | DEC-028. Brave Origin from Brave's APT repo (DEC-026). Default set by `/etc/xdg/mimeapps.list` (satori-config) and by pointing the `x-www-browser` alternative at `brave-origin-stable` on first install (satori-desktop postinst). Firefox policies in satori-config |
| Keyring | `gnome-keyring`, `libpam-gnome-keyring` | DEC-030. Secret Service for Brave, Melia, Firefox and NetworkManager. Unlocked by PAM at tty1 login |
| Email | Melia, not preinstalled | DEC-029. `satori-get-melia` downloads and verifies the signed `.deb` on demand |
| Screenshots | `maim` + `xclip` | `satori-screenshot`, bound to `Mod+p` / `Mod+Shift+p` |
| Clipboard | `xclip`, `copyq` | `clipmenu` isn't packaged in Excalibur; CopyQ replaces it (`Mod+v`). `cliphist` and `clipman` are Wayland-only |
| Images/PDF | `feh` (also sets wallpaper), `zathura` | |
| Fonts | `fonts-noto`, `fonts-noto-color-emoji`, `fonts-jetbrains-mono` | |
| Theming | GTK theme and icon theme TBD in Phase 4, `lxappearance` | |
| Firewall | `nftables` + satori ruleset | DEC-023 |
| Time sync | `chrony` | DEC-024. Must not use systemd-timesyncd |

Optional `developer.list.chroot`: `git`, `build-essential`, `curl`, `jq`, `ripgrep`, `fd-find`, `tmux`, `shellcheck`.

## 2. Session startup

With no systemd user services, the X session itself starts everything. It uses
Debian's standard `startx` → `Xsession` path, so a user's own `~/.xinitrc` or
`~/.xsession` still takes precedence. Order matters:

1. **tty1 login.** `/etc/profile.d/satori-startx.sh` runs `exec startx` on tty1 if
   `$DISPLAY` is unset. To opt out, a user creates `~/.config/satori/no-startx`. In the
   live session, satori's live-config component `0161-satori-autologin` adds agetty's
   `--autologin` to the tty1–6 gettys. live-config's own `0160-sysvinit` component never
   works on Excalibur: it checks for a package named `sysvinit`, which no longer exists,
   and its `sh -c "/bin/login -f"` inittab line leaves `login` stopped by job control.
2. **`/etc/X11/Xsession`** (from `x11-common`). Its `75dbus_dbus-launch` step starts the
   D-Bus session bus (`dbus-x11`), then it runs the `x-session-manager` alternative.
3. **`satori-session`**, registered as `x-session-manager` by `satori-config`:
   - `gnome-keyring-daemon --start --components=secrets` attaches to the keyring that
     PAM started and unlocked at login (DEC-030), and exports its environment.
   - It runs `exec herbstluftwm --autostart /usr/share/satori/herbstluftwm/autostart`,
     or plain `herbstluftwm` if the user has `~/.config/herbstluftwm/autostart`.
4. **The herbstluftwm autostart** sets keybindings, tags, theme and rules, then starts
   each of these once via `satori-run-once` (herbstluftwm re-runs autostart on reload):
   - `pipewire`, `wireplumber` and `pipewire-pulse` as three processes, because Debian's
     PipeWire config doesn't start the other two
   - `lxpolkit`, `picom` (with `/usr/share/satori/picom.conf`), `dunst`,
     `copyq --start-server`, `blueman-applet`
   - `xss-lock --transfer-sleep-lock -- i3lock`
   - `xsetroot -solid` as a background colour until Phase 4 adds a wallpaper
   - `polybar` with `/usr/share/satori/polybar/config.ini`

`herbstluftwm`, `polybar`, `dunst` and `nftables` each own their default config file as a
conffile. satori never overwrites or diverts those files; it passes its own files from
`/usr/share/satori/` with each program's config option instead.

## 3. Keybindings (defaults)

`Mod` = Super. The full list ships as `/usr/share/satori/keybindings.txt` and is
shown by `satori-keys` on `Mod+F1`. The bindings themselves are in
`/usr/share/satori/herbstluftwm/autostart`.

| Keys | Action |
|---|---|
| `Mod+Return` | Terminal |
| `Mod+Space` | rofi launcher |
| `Mod+Shift+Space` | Cycle frame layout (herbstluftwm's default was `Mod+Space`) |
| `Mod+Tab` | rofi window switcher |
| `Mod+v` | Clipboard history (`copyq toggle`) |
| `Mod+1..9` / `Mod+Shift+1..9` | Switch to / move window to tag |
| `Mod+h/j/k/l` | Focus left/down/up/right |
| `Mod+Shift+h/j/k/l` | Move window |
| `Mod+Ctrl+h/j/k/l` | Resize frame |
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

- System defaults live under `/usr/share/satori/`, shipped by `satori-config`, and are used only when the user has no config of their own.
- User config under `~/.config` always wins. satori never writes to an existing home directory after install.
- `satori-config` upgrades never touch user files. Changes to `/etc/skel` only affect newly created users.
