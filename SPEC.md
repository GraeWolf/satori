# satori — Project Specification

> Living document. Decisions and their rationale live in [DECISIONS.md](DECISIONS.md);
> this file describes *what* satori is and *how we'll know each phase is done*.
> Detailed designs: [docs/desktop-stack.md](docs/desktop-stack.md), [docs/installer.md](docs/installer.md).

## 1. Overview

**satori** is a systemd-free, amd64 desktop Linux distribution built as a respin of
**Devuan Excalibur** (Devuan 6, Debian Trixie-based). It ships a preconfigured
**herbstluftwm** tiling desktop on X11 and a keyboard-driven **TUI installer** built
with `gum`.

### Goals
- A hybrid (BIOS + UEFI) ISO that boots to a working live desktop and installs to disk.
- No systemd as init or as a package, as defined precisely in §4.
- Opinionated, keyboard-first defaults that a technical user can adopt or strip down easily.
- The whole build is scripted from this repository. There are no manual or undocumented steps.
- satori-specific configuration ships as `.deb` packages, so it survives `apt upgrade` and stays under dpkg's control.

### Non-goals (v1)
- Custom kernel or kernel patches. We use Devuan's stock kernel.
- A satori-hosted APT repository. satori packages are built in-repo and baked into the ISO (see DEC-006). Third-party repositories are allowed only under DEC-026.
- Wayland. herbstluftwm is X11-only.
- Manual partitioning, dual-boot, or filesystems other than ext4 in the installer.
- Secure Boot (DEC-016) and Plymouth (DEC-015).
- Architectures other than amd64.
- Bit-for-bit reproducible ISOs. v1 targets a *repeatable* build (§5.3).

## 2. Audience

Technical Linux users, starting with the maintainer. They are comfortable with a
tiling window manager, a terminal, and editing dotfiles. They want a systemd-free
daily driver without hand-assembling Devuan plus a window manager each time.

In practice this means:
- Documentation can assume Linux literacy. It still has to be complete for anything satori-specific, such as keybindings, config locations, and how to rebuild.
- Defaults should be discoverable (for example a keybinding cheatsheet), but no GUI settings apps are required.
- A single-user laptop or workstation is the primary target. Server and embedded use are out of scope.

## 3. Architecture

### 3.1 Base system
| Item | Value |
|---|---|
| Base | Devuan Excalibur (`excalibur`, `excalibur-updates`, `excalibur-security`) |
| Mirror | `deb.devuan.org/merged` |
| Archive areas | `main contrib non-free non-free-firmware` (see DEC-013) |
| Init | `sysvinit-core` |
| Session/seat | `elogind` + `libpam-elogind`, `polkitd` |
| Kernel | Devuan/Debian stock `linux-image-amd64` |
| Package manager | APT, unmodified |
| Third-party repos | Brave (`brave-origin`, `brave-keyring`) and XLibre for Devuan (`xlibre*`), each pinned to specific packages (DEC-026) |

### 3.2 Build tooling
- **Debian's live-build** (`1:20250505+deb13u1`, pinned by checksum), configured for Devuan (DEC-003). Devuan's own `live-build` package is a 2016 fork without UEFI support, so it isn't used.
  - All `lb config` flags live in `live-build/auto/config`. Nobody types flags by hand.
  - Mirrors, distribution, and archive areas must be set explicitly to Devuan values. live-build defaults to Debian.
  - BIOS and UEFI both boot through GRUB (`--bootloaders "grub-pc grub-efi"`), so there's one boot menu config.
  - live-build's package cache lives outside the per-build work directory, so rebuilds don't re-download everything.
  - Third-party repositories (DEC-026) are added to the build chroot from the same pinned keys and `.sources` files that `satori-apt-sources` ships. The build fails if a key doesn't match its recorded checksum.
- **Build host:** a privileged Devuan Excalibur container (Podman or Docker) defined in `container/`, with the base image pinned by digest (DEC-031). The host OS doesn't matter. It only needs the container engine and root.
- **In-repo packages:** `packages/*` are built with `debhelper` inside the same container, then placed in `live-build/config/packages.chroot/` before `lb build`.

### 3.3 satori packages
| Package | Contents |
|---|---|
| `satori-desktop` | Metapackage that depends on the full desktop stack ([docs/desktop-stack.md](docs/desktop-stack.md)). Installed during the build by a chroot hook, after `satori-apt-sources` has configured the third-party repositories (DEC-026). |
| `satori-config` | System-wide defaults in `/usr/share/satori/` (used only when the user has no config of their own): the `satori-session` X session, herbstluftwm autostart and keybindings, polybar and picom configs, startx on tty1, the default browser, browser policies, firewall ruleset, NetworkManager MAC randomisation. Helper scripts: `satori-run-once`, `satori-keys`, `satori-powermenu`, `satori-screenshot`, `satori-get-melia` (DEC-029), and later `satori-swap-resize` (DEC-017). |
| `satori-apt-sources` | Third-party `.sources` entries, their pinned signing keys, and `/etc/apt/preferences.d/` pins (DEC-026). |
| `satori-branding` | `os-release`/`issue` via `dpkg-divert` (these files are owned by `base-files`), wallpapers, GRUB theme, logo assets. |
| `satori-installer` | The gum TUI installer ([docs/installer.md](docs/installer.md)) and the QEMU-only `satori-autoinstall` init script. Installed in the live image only, purged from the target. |

Rule: **no loose overlay files for anything a user might need updated.** The
`includes.chroot/` overlay is reserved for live-session-only tweaks.

Because there's no hosted repo in v1 (DEC-006), installed systems get Devuan updates
through APT but get satori package updates only by manually installing newer `.deb`s.
This limitation should be documented for users.

### 3.4 Desktop stack
herbstluftwm on Xorg, started with `startx` from a tty1 login (DEC-014). The full
component list, keybindings, and session startup order are in
[docs/desktop-stack.md](docs/desktop-stack.md).

### 3.5 Installer
A gum-based TUI that copies the live filesystem to disk. It supports guided
whole-disk installs, with optional LUKS2 encryption, on BIOS and UEFI. It creates
a RAM-sized swapfile and configures resume, so hibernation works out of the box
(DEC-017). Design: [docs/installer.md](docs/installer.md).

### 3.6 Security and privacy defaults
Recorded as DEC-022 (accounts) and DEC-023 (everything else).

- Installer offers LUKS2 full-disk encryption (the root filesystem and swapfile are encrypted; `/boot` isn't).
- nftables firewall enabled: inbound traffic denied except established/related, all outbound allowed.
- `sudo` for the installer-created user; the root account is locked.
- No `popularity-contest`. Firefox ESR policies turn off telemetry, studies, and sponsored content. Brave Origin's remaining telemetry, if any, is switched off with managed policies.
- NetworkManager uses randomised MAC addresses when scanning Wi-Fi.
- No services listen on the network by default. There's no SSH server.

### 3.7 Branding
- Name "satori". `/usr/lib/os-release` diverted to a satori version that keeps `ID_LIKE=devuan debian`.
- GRUB theme on both the live ISO and installed systems. Default wallpaper. Text boot (no Plymouth in v1).
- Devuan and Debian logos and trademarks removed from user-visible branding. Attribution to Devuan kept in `os-release`, the docs, and `/usr/share/doc`.

## 4. The "no systemd" rule

An image **passes** only if all of these hold:
1. PID 1 is sysvinit's `init`, and `/run/systemd/system` doesn't exist.
2. None of these packages are installed: `systemd`, `systemd-sysv`, `systemd-timesyncd`, `systemd-resolved`, `systemd-boot`, `libpam-systemd`.
3. Every installed package whose name contains `systemd` is on an explicit allowlist in `tests/systemd-allowlist.txt`. After Phase 0 it contains only `libsystemd0` (DEC-010). Each entry needs a comment explaining why. The base package list must include `opensysusers` so that nothing pulls in `systemd-standalone-sysusers`.

Rules 2 and 3 are checked by `scripts/check-no-systemd.sh` against every build's
package manifest. Rule 1 is checked at runtime by the QEMU smoke test. A failure
fails the build.

## 5. Build, test and release

### 5.1 Build
```
sudo scripts/build.sh       # builds container → builds packages/ → lb config/build → no-systemd check
```
The version comes from the `VERSION` file. A clean checkout of tag `v<VERSION>` builds as `<VERSION>`; anything else builds as `<VERSION>-dev.<short commit>`.
Output goes to `out/` (git-ignored):
- `satori-<version>-amd64.iso` and `.sha256`
- `satori-<version>-amd64.packages`: the package manifest
- `build-info.txt`: git SHA, dirty flag, build date, base image digest, build image ID, live-build version, ISO size and checksum, package count
- `build.log`: the full live-build log
- `cache/`: live-build's downloaded-package cache, reused between builds (root-owned)

### 5.2 Test
- `scripts/test-in-qemu.sh`: boots the ISO under SeaBIOS or OVMF in a QEMU window, for hands-on testing.
- `tests/smoke/` automated tests, driven over the serial console. The live ISO's GRUB menu has a "serial console" entry (hotkey `s`) that sends kernel output to `ttyS0` and starts a serial login prompt. Tests press `s` at the menu; the default entry is unaffected.
  - `tests/smoke/live-boot.py`: the live image boots on BIOS and UEFI, a login prompt appears, and the no-systemd runtime check passes.
  - `tests/smoke/install.py`: install matrix, {BIOS, UEFI} × {plain, LUKS} = 4 unattended installs (answers file via QEMU fw_cfg, [docs/installer.md](docs/installer.md) §6). Each installed system must boot to a login prompt and pass `tests/smoke/installed-checks.sh`. `tests/smoke/qemu_serial.py` holds the shared QEMU and serial-console code.
- Manual QA checklist in `docs/testing.md`, for things that are hard to automate on real hardware: Wi-Fi, audio, suspend/resume, hibernate/resume, backlight, external monitors.

### 5.3 Reproducibility
v1 promises a **repeatable** build. The same git SHA and the same container digest
produce an ISO with the same package set, apart from newer versions from Devuan
mirrors. The package manifest records exactly what went in. Bit-for-bit
reproducibility is a possible later goal.

### 5.4 Versioning and release
- Versions follow `<major>.<minor>`, with the Devuan base in the release notes, for example "satori 0.1 (Excalibur)".
- Git tags `v0.1` etc. Release artifacts are the ISO, its checksum, the manifest, and build-info.
- Releases are published on GitHub Releases (DEC-020). Each asset must be under 2 GiB, so the ISO size is tracked in build-info from Phase 2 on.
- `CHANGELOG.md` is maintained from Phase 1 onward.

### 5.5 Licensing
- Everything in the repo except `branding/`: GPL-3.0-or-later (DEC-019), full text in `LICENSE`.
- Branding assets: licensed separately, noted in `branding/LICENSE`.

## 6. Repository layout

```
satori/
├── README.md
├── VERSION                        # base version, e.g. 0.1
├── LICENSE                        # GPL-3.0-or-later
├── SPEC.md
├── DECISIONS.md
├── CHANGELOG.md
├── container/
│   └── Containerfile              # pinned Devuan Excalibur build env
├── live-build/
│   ├── auto/{config,build,clean}
│   └── config/
│       ├── package-lists/
│       │   ├── base.list.chroot
│       │   ├── live.list.chroot   # live-only: live-boot, live-config, satori-installer
│       │   └── developer.list.chroot
│       ├── packages.chroot/       # generated: satori-*.deb (git-ignored)
│       ├── bootloaders/grub-pc/   # GRUB menu for BIOS and UEFI, incl. the serial test entry
│       ├── includes.chroot/       # live-session-only overlays
│       ├── includes.binary/
│       └── hooks/{normal,live}/
├── packages/
│   ├── satori-desktop/debian/
│   ├── satori-config/{debian/,files/}
│   ├── satori-branding/{debian/,files/}
│   ├── satori-apt-sources/{debian/,keys/,sources/,preferences/}
│   └── satori-installer/{debian/,src/}
├── branding/                      # source assets (SVG etc.) → rendered into satori-branding
├── scripts/
│   ├── build.sh                   # host side: container build + run (needs root)
│   ├── build-in-container.sh      # container side: live-build, checks, outputs
│   ├── build-packages.sh
│   ├── check-no-systemd.sh
│   └── test-in-qemu.sh
├── tests/
│   ├── systemd-allowlist.txt
│   └── smoke/                     # serial-console tests: live-boot.py, install.py,
│                                  # installed-checks.sh, qemu_serial.py
└── docs/
    ├── building.md
    ├── customizing.md
    ├── desktop-stack.md
    ├── installer.md
    └── testing.md
```

## 7. Phases and acceptance criteria

Each phase is one or more small commits and ends only when every one of its criteria passes.

**Phase 0: Feasibility spike**. ✔ Complete (2026-09-28). See DEC-003, DEC-010 and DEC-021.
- A throwaway live-build config for Excalibur produces a console-only hybrid ISO.
- ✅ The ISO boots to a login prompt in QEMU on SeaBIOS and OVMF.
- ✅ The manifest is inspected, the allowlist in §4 is drafted, and no forbidden packages are present.
- ✅ Findings are recorded in DECISIONS.md: whether live-build is confirmed or replaced (DEC-003), which `gum` path applies (DEC-021), and which `lb config` flags were needed.

**Phase 1: Build system**. ✔ Complete (2026-09-28). A clean clone of `1b35a66` built in about 7 minutes, and both boot tests passed. See DEC-031.
- Scaffold the layout in §6: the container, `build.sh`, `check-no-systemd.sh`, and the manifest and build-info outputs.
- ✅ `scripts/build.sh` on a clean checkout produces an ISO without manual steps.
- ✅ An automated live boot test (BIOS and UEFI) plus the systemd runtime check pass.

**Phase 2: Desktop stack**. ✔ Complete (2026-09-29). Smoke tests pass on BIOS and UEFI, and the maintainer checked the launcher, audio, network and browser by hand in QEMU. The real-laptop check is deferred to Phase 3's first install on real hardware: the only laptop is the development machine, which gets satori once there's a stable release candidate.
- `satori-desktop` and `satori-config` packages. The live session autologs in and starts herbstluftwm.
- ✅ The live session reaches herbstluftwm with the bar, launcher, notifications, the bar's network module (DEC-011), and working audio. `tests/smoke/live-boot.py` checks that every session process is running. Launcher, audio and network are checked by hand in QEMU and on at least one real laptop.
- ✅ Every added package passes the no-systemd check, including those from third-party repositories. Any substitutions are documented in docs/desktop-stack.md.
- ✅ Third-party repositories are restricted by their pins: `apt-cache policy` shows no Devuan package replaced by a Brave or XLibre package.
- ✅ Brave Origin is the default browser.
- ✅ The DEC-023 security defaults are in place: `tests/smoke/live-boot.py` checks that satori's firewall is loaded and that nothing listens beyond loopback; the browser and NetworkManager policy files are installed.
- ✅ `satori-get-melia` installs Melia, and it refuses a download whose signature or checksum is wrong.

**Phase 3: Installer**
- `satori-installer` (using Excalibur's `gum` package, DEC-021).
- ✅ All four unattended install-matrix runs pass (§5.2).
- ✅ An interactive install in QEMU (`scripts/test-in-qemu.sh --disk`) completes and the installed system boots to the desktop.
- ✅ An interactive install on real hardware, with LUKS, boots and passes the manual checklist. This includes the Phase 2 desktop checks deferred from QEMU: Wi-Fi, audio, brightness keys, suspend and the lock screen.
- ✅ Hibernate and resume work in QEMU for all four install cases: `tests/smoke/install.py` hibernates each installed system and checks that the same session resumes. On real hardware too, with and without LUKS (DEC-017).
- ✅ On an installed system, Brave Origin saves and recalls a password through gnome-keyring without an extra unlock prompt (DEC-030). Moved from Phase 2: the live session autologins, so PAM has no password to unlock the keyring with.

**Phase 4: Branding**
- `satori-branding`, the GRUB theme, wallpaper, and os-release diversion.
- ✅ `os-release` still shows satori after `apt install --reinstall base-files`.
- ✅ No Devuan or Debian logos appear on the boot menu, GRUB, or desktop.

**Phase 5: CI and QA**
- A CI pipeline builds on push and runs the automated tests. `docs/testing.md` has the manual checklist.
- ✅ A green CI run on `main` produces downloadable ISO artifacts.

**Phase 6: Docs and first release**
- `docs/building.md`, `docs/customizing.md`, README, and CHANGELOG.
- ✅ The `v0.1` tag is released with its ISO, checksum, manifest, and build-info.

## 8. Notes for Claude Code sessions
- Keep SPEC.md and DECISIONS.md current. When a decision's status or content changes, update DECISIONS.md (with a dated History line) and every doc that references its `DEC-nnn` ID in the same commit.
- Before adding any package, check that it exists in Excalibur and run the no-systemd check. Package names and systemd-free substitutes change between releases.
- Never download build inputs without pinning them (a checksum or container digest).
