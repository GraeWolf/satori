# Changelog

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
