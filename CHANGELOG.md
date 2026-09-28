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
