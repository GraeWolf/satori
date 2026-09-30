# satori

A systemd-free desktop respin of Devuan Excalibur: herbstluftwm on X11 and a
keyboard-driven installer. See [SPEC.md](SPEC.md) for what's planned and
[DECISIONS.md](DECISIONS.md) for why. Licensed GPL-3.0-or-later.

**Status:** Phases 1–3 and the release candidate gate are complete, and
`0.1-rc1` is installed on the development laptop. The live ISO boots to the
herbstluftwm desktop and installs with `sudo satori-install`. Phase 4
(branding: Tokyo Night, placeholder art) is in progress.

## Build

Needs a Linux host with Podman (or Docker) and root. Everything else runs inside
the pinned Devuan build container. On satori (or any Devuan/Debian host), this
installs everything needed to build and test it (DEC-033):

```sh
sudo apt install git podman qemu-system-x86 qemu-utils ovmf python3
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

`out/packages/` holds satori's own `.deb`s. Dev builds are versioned
`<VERSION>-dev<commit count>.<commit>`. A clean checkout of tag `v<VERSION>`
builds as plain `<VERSION>`. Package versions rise with every commit (DEC-032). The first build downloads about
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

The live user is `user`, password `live`.

## Update an installed satori

Devuan packages update through APT as usual. satori's own packages come from a
build (DEC-006):

```sh
sudo scripts/build.sh --packages-only     # about a minute
sudo apt install ./out/packages/satori-{apt-sources,branding,config,desktop}_*.deb
```

`tests/smoke/upgrade.py` checks this path: it upgrades a system installed from
an earlier build and re-runs the installed-system checks. All testing happens in virtual machines;
only files under `out/` are written on the host.
