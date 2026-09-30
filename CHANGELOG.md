# Changelog

## Unreleased

### Changed
- **Renamed from satori to Tekne** (DEC-008): packages are now `tekne-*`,
  and so are paths, commands, the firewall table and the ISO name. To move an
  installed satori system over, build and run
  `sudo apt install --purge ./out/packages/tekne-{apt-sources,branding,config,desktop}_*.deb`;
  it removes the `satori-*` packages cleanly. The placeholder art is now a
  geometric T instead of an ensō.

### Added
- A styled boot console (DEC-037): Tokyo Night console colours, firmware
  error spam kept off the screen (`loglevel=3`), and a centred "T E K N E"
  banner above a centred LUKS passphrase prompt. New installs name the
  encrypted disk `tekne`. Still text, no Plymouth (DEC-015).
- Kernel from Devuan's `excalibur-backports` (DEC-036): 7.1 instead of
  stable's 6.12. `tekne-apt-sources` adds the suite, pinned to the kernel
  packages only. Fixes ASUS ROG laptop keyboards that `hid-asus` failed to set
  up on 6.12 (dead keyboard, even at the LUKS prompt).
- Branding (Phase 4, DEC-034): the `tekne-branding` package. `os-release`
  says Tekne (Devuan's copy is diverted, so `base-files` upgrades can't bring
  it back), and ships a GRUB theme for the live ISO and installed systems, a
  wallpaper and a logo. The artwork is a placeholder mark, rendered from SVGs in
  `branding/` (CC-BY-SA-4.0).
- Tokyo Night colours for herbstluftwm, polybar, rofi, dunst, alacritty and the
  lock screen; dark Adwaita with Papirus icons for GTK apps.
- `tekne-terminal`: alacritty with Tekne's config unless you have your own.
  It's the `x-terminal-emulator` alternative, which had been xterm's `lxterm`.
- Live ISO boot menu: "Tekne live" and "Tekne live (safe graphics)"
  (`nomodeset`) replace live-build's "Live system" entries and Debian splash.
- The build container installs `librsvg2-bin`, to render the artwork.

### Fixed
- The bar had no battery indicator on laptops whose battery or charger isn't
  named `BAT0`/`ADP1`, polybar's defaults (for example `BAT1` and `ACAD`). The
  herbstluftwm autostart now detects the names from `/sys/class/power_supply`.
- `scripts/build.sh` failed on Tekne itself: the container couldn't resolve
  names, because Tekne's firewall (DEC-023) dropped the forwarded and inbound
  traffic that a container bridge network needs. The build container now uses
  the host's network.
- `service tekne-firewall status` said "NOT loaded" when run without root,
  because nft can't read the ruleset then. It now says it needs root.

### Changed
- Firewall (DEC-023): traffic from local container and VM bridges (podman,
  Docker, libvirt) is accepted, as are ports a container engine publishes.
  Before, containers and VMs on a bridge network had no network at all.
- `tekne-config` now declares the packages its helper scripts call
  (herbstluftwm, rofi, maim, xclip and others), instead of relying on
  `tekne-desktop` to install them.
- The no-systemd allowlist (DEC-010) is empty: `libsystemd0` is no longer in
  the image, because Devuan's `libelogind-compat` replaces it.

## 0.1-rc1 (2026-09-29)

First release candidate: the build system, desktop and installer (Phases 1-3).
Real-hardware checks happen before it's installed on the development laptop
(release candidate gate, SPEC §7).

### Added
- Build system (Phase 1): `scripts/build.sh` builds a hybrid BIOS/UEFI Devuan
  Excalibur live ISO in a pinned build container, using Debian's live-build.
- Package manifest, checksum and `build-info.txt` for every build.
- No-systemd check (SPEC.md §4) that fails the build; `libsystemd0` is the only
  allowlisted package.
- Headless QEMU boot test for BIOS and UEFI (`tests/smoke/live-boot.py`) and an
  interactive launcher (`scripts/test-in-qemu.sh`).
- Desktop (Phase 2): `satori-desktop`, `satori-config` and `satori-apt-sources`
  packages, built from `packages/` into `out/packages/`. The live session logs
  in on tty1 and starts herbstluftwm with polybar, rofi, dunst, picom, CopyQ,
  PipeWire and gnome-keyring.
- Brave Origin (default browser) and XLibre from their own repositories, with
  keys scoped by `Signed-By`, APT pins, and a build-time check that no other
  package came from them. `brave-keyring`'s globally trusted key is diverted.
- Firmware and CPU microcode for common laptop hardware.
- `satori-get-melia`: downloads Melia and installs it only if the signature and
  checksum verify.
- Security and privacy defaults (DEC-023): nftables firewall (`satori-firewall`),
  Firefox ESR and Brave telemetry policies, Wi-Fi scan MAC randomisation.
- Installer (Phase 3): `satori-install`, a gum TUI that installs the live system
  to a whole disk with optional LUKS2, on BIOS or UEFI, with a RAM-sized
  swapfile and resume configured for hibernation. Unattended mode for tests.
- `satori-swap-resize` recreates the swapfile and keeps hibernation working.
- `tests/smoke/install.py`: unattended {BIOS, UEFI} × {plain, LUKS} installs in
  QEMU, each booted and checked. Answers reach the VM through QEMU fw_cfg, so
  automated installs can't run on real hardware.
- Package versions rise with every build (DEC-032), so an installed system
  upgrades with `apt install ./out/packages/...`; `tests/smoke/upgrade.py`
  tests it. `scripts/build.sh --packages-only` builds just the `.deb`s.
- README: one command installs the tools to build satori on satori (DEC-033).

### Fixed
- Installer: the timezone and keyboard steps showed only a few matches,
  because the current value was pre-typed as the search. They now start with
  the full list (418 timezones, including aliases such as Europe/Oslo) and the
  current value first.
- Console logins now unlock the GNOME keyring (no create or unlock prompts).
- Live-session autologin on Excalibur: live-config's sysvinit component never
  ran, so satori ships its own using agetty `--autologin`.
