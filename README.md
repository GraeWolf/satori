# Tekne

A systemd-free desktop respin of Devuan Excalibur: herbstluftwm on X11 and a
keyboard-driven installer. See [SPEC.md](SPEC.md) for what's planned and
[DECISIONS.md](DECISIONS.md) for why. Licensed GPL-3.0-or-later; the artwork
in `branding/` is CC-BY-SA-4.0.

**Status:** working towards 0.1. Phases 1–5 are complete: the live ISO boots
to the herbstluftwm desktop on BIOS and UEFI, installs with `sudo
tekne-install` (optionally with LUKS, with hibernation), and CI builds and
tests every change. The development laptop runs Tekne. Phase 6 (docs and the
first release) is in progress.

| Guide | For |
|---|---|
| [docs/customizing.md](docs/customizing.md) | Changing an installed Tekne: desktop, keybindings, theme, firewall, kernel |
| [docs/building.md](docs/building.md) | Building, testing and releasing the ISO, and where to change things |
| [docs/testing.md](docs/testing.md) | The manual checklist for real hardware |
| [docs/desktop-stack.md](docs/desktop-stack.md), [docs/installer.md](docs/installer.md) | How the desktop and the installer are designed |

## Try it

Write the ISO to a USB stick, disable Secure Boot, and boot it: the desktop
starts on its own (live user `user`, password `live`). `sudo tekne-install`
installs it to a whole disk, which it erases. [docs/testing.md](docs/testing.md)
has the steps and a hardware checklist.

## Build

Needs a Linux host with Podman (or Docker) and root. Everything else runs inside
the pinned Devuan build container. On Tekne (or any Devuan/Debian host), this
installs everything needed to build and test it (DEC-033):

```sh
sudo apt install git podman qemu-system-x86 qemu-utils ovmf python3
sudo scripts/build.sh
```

Outputs in `out/`:

| File | Contents |
|---|---|
| `tekne-<version>-amd64.iso` | Hybrid ISO, boots on BIOS and UEFI (Secure Boot off) |
| `tekne-<version>-amd64.iso.sha256` | Checksum |
| `tekne-<version>-amd64.packages` | Package manifest |
| `build-info.txt` | Git commit, build image, live-build version, ISO size |
| `build.log` | Full build log |

`out/packages/` holds Tekne's own `.deb`s. Dev builds are versioned
`<VERSION>-dev<commit count>.<commit>`. A clean checkout of tag `v<VERSION>`
builds as plain `<VERSION>`. Package versions rise with every commit (DEC-032).
The first build downloads about 1.5 GB; later builds reuse the package cache in
`out/cache/`. More in [docs/building.md](docs/building.md).

The build fails if the package manifest breaks the no-systemd rule
(SPEC.md §4, allowlist in `tests/systemd-allowlist.txt`).

## Test

Needs `qemu-system-x86` and `ovmf` on the host. CI (GitHub Actions,
`.github/workflows/build.yml`) builds the ISO and runs `live-boot.py` and
`install.py` on every push to `master` and every pull request; each green run
keeps the ISO as a downloadable artifact for 30 days (DEC-038).

```sh
tests/smoke/live-boot.py                  # live ISO on SeaBIOS and OVMF: sysvinit, desktop, firewall
tests/smoke/install.py                    # unattended installs {BIOS,UEFI} x {plain,LUKS}, each
                                          # booted, checked, hibernated and resumed (~15 min)
scripts/test-in-qemu.sh uefi              # the newest ISO in a QEMU window
scripts/test-in-qemu.sh uefi --disk       # ...with a blank 32 GiB virtual disk: sudo tekne-install
scripts/test-in-qemu.sh uefi --installed  # boot that virtual disk after installing
```

The live user is `user`, password `live`.

## Update an installed Tekne

Devuan packages update through APT as usual. Tekne's own packages come from a
build (DEC-006):

```sh
sudo scripts/build.sh --packages-only     # about a minute
sudo apt install ./out/packages/tekne-{apt-sources,branding,config,desktop}_*.deb
```

`tests/smoke/upgrade.py` checks this path: it upgrades a system installed from
an earlier build and re-runs the installed-system checks. All testing happens in virtual machines;
only files under `out/` are written on the host.
