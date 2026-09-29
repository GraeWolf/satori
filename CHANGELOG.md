# Changelog

## Unreleased

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

### Fixed
- Live-session autologin on Excalibur: live-config's sysvinit component never
  ran, so satori ships its own using agetty `--autologin`.
