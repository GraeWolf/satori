# satori

A systemd-free desktop respin of Devuan Excalibur: herbstluftwm on X11 and a
keyboard-driven installer. See [SPEC.md](SPEC.md) for what's planned and
[DECISIONS.md](DECISIONS.md) for why. Licensed GPL-3.0-or-later.

**Status:** Phase 2 (desktop) is complete. The live ISO boots to the
herbstluftwm desktop; the installer arrives in Phase 3.

## Build

Needs a Linux host with Podman (or Docker) and root. Everything else runs inside
the pinned Devuan build container.

```sh
sudo apt install podman
sudo scripts/build.sh
```

Outputs in `out/`:

| File | Contents |
|---|---|
| `satori-<version>-amd64.iso` | Hybrid ISO, boots on BIOS and UEFI (Secure Boot off) |
| `satori-<version>-amd64.iso.sha256` | Checksum |
| `satori-<version>-amd64.packages` | Package manifest |
| `build-info.txt` | Git commit, build image, live-build version, ISO size |
| `build.log` | Full build log |

Dev builds are versioned `<VERSION>-dev.<commit>`. A clean checkout of tag
`v<VERSION>` builds as plain `<VERSION>`. The first build downloads about
500 MB; later builds reuse the package cache in `out/cache/`.

The build fails if the package manifest breaks the no-systemd rule
(SPEC.md §4, allowlist in `tests/systemd-allowlist.txt`).

## Test

Needs `qemu-system-x86` and `ovmf` on the host.

```sh
tests/smoke/live-boot.py                  # live ISO on SeaBIOS and OVMF: sysvinit, desktop, firewall
tests/smoke/install.py                    # unattended installs {BIOS,UEFI} x {plain,LUKS}, each
                                          # booted, checked, hibernated and resumed (~15 min)
scripts/test-in-qemu.sh uefi              # the newest ISO in a QEMU window
scripts/test-in-qemu.sh uefi --disk       # ...with a blank 32 GiB virtual disk: sudo satori-install
scripts/test-in-qemu.sh uefi --installed  # boot that virtual disk after installing
```

The live user is `user`, password `live`. All testing happens in virtual machines;
only files under `out/` are written on the host.
