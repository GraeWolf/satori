# Phase 0 spike

Throwaway proof that a pinned Debian live-build can produce a bootable,
systemd-free, hybrid BIOS + UEFI Devuan Excalibur ISO (SPEC.md §7, Phase 0).
Phase 1 replaces this with the real build system under `live-build/` and
`container/`. Findings are recorded in DECISIONS.md.

## Run

```sh
sudo apt install debootstrap               # host needs Devuan's debootstrap (has the excalibur script)
sudo spike/phase0/build.sh                 # ~10–20 min; output in out/phase0/
spike/phase0/check-no-systemd.sh out/phase0/satori-phase0-amd64.packages
spike/phase0/test-in-qemu.py bios
spike/phase0/test-in-qemu.py uefi
```

## What's here

| File | Purpose |
|---|---|
| `fetch-live-build.sh` | Downloads Debian's live-build source (pinned version + SHA-256) into `.cache/`. Run automatically by `build.sh`. |
| `auto/config` | Every `lb config` flag: Devuan mirrors and keyring, sysvinit, GRUB for BIOS and UEFI, Secure Boot off. |
| `config/bootloaders/grub-pc/config.cfg` | Text GRUB menu on screen and serial, 5 s timeout. |
| `config/hooks/live/0100-serial-getty.hook.chroot` | Serial login prompt, so tests can run headless. |
| `build.sh` | Runs live-build in `out/phase0/work/` and copies the ISO and package manifest to `out/phase0/`. |
| `check-no-systemd.sh` | SPEC §4 rules 2–3 against the manifest, using `tests/systemd-allowlist.txt`. |
| `test-in-qemu.py` | Boots the ISO headless (SeaBIOS or OVMF), logs in over serial, checks SPEC §4 rule 1. |

## Why not Devuan's live-build?

Devuan's `live-build` package (`4.0.3-1+devuan2`) is a 2016 fork of Debian's
jessie-era live-build. It has no `grub-efi` stage, so it can't build a UEFI-bootable ISO.
