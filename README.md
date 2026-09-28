# satori

A systemd-free desktop respin of Devuan Excalibur: herbstluftwm on X11 and a
keyboard-driven installer. See [SPEC.md](SPEC.md) for what's planned and
[DECISIONS.md](DECISIONS.md) for why. Licensed GPL-3.0-or-later.

**Status:** Phase 1 (build system) is complete. The ISO is currently a
console-only live system; the desktop arrives in Phase 2.

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
tests/smoke/live-boot.py          # headless boot on SeaBIOS and OVMF, checks PID 1 is sysvinit
scripts/test-in-qemu.sh uefi      # boot the newest ISO in a QEMU window
```

The live user is `user`, password `live`.
