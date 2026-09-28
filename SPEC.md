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
- A hosted APT repository. satori packages are built in-repo and baked into the ISO (see D-006).
- Wayland. herbstluftwm is X11-only.
- Manual partitioning, dual-boot, or filesystems other than ext4 in the installer.
- Secure Boot (P-016), Plymouth (P-015), and hibernation (P-017).
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
| Archive areas | `main contrib non-free non-free-firmware` (see P-013) |
| Init | `sysvinit-core` |
| Session/seat | `elogind` + `libpam-elogind`, `polkitd` |
| Kernel | Devuan/Debian stock `linux-image-amd64` |
| Package manager | APT, unmodified |

### 3.2 Build tooling
- **live-build**, configured for Devuan. This is provisional until Phase 0 proves it works (D-003).
  - All `lb config` flags live in `live-build/auto/config`. Nobody types flags by hand.
  - Mirrors, distribution, and archive areas must be set explicitly to Devuan values. live-build defaults to Debian.
  - The fallback if live-build can't be made to work cleanly is Devuan's own tooling (live-sdk / refracta). Phase 0 decides.
- **Build host:** a privileged Devuan Excalibur container (Podman or Docker) defined in `container/`, with the base image pinned by digest. Host OS doesn't matter.
- **In-repo packages:** `packages/*` are built with `debhelper` inside the same container, then placed in `live-build/config/packages.chroot/` before `lb build`.

### 3.3 satori packages
| Package | Contents |
|---|---|
| `satori-desktop` | Metapackage that depends on the full desktop stack ([docs/desktop-stack.md](docs/desktop-stack.md)). |
| `satori-config` | System-wide defaults: `/etc/skel` dotfiles, herbstluftwm autostart, bar/launcher/notification configs, Firefox ESR policies, firewall ruleset, NetworkManager MAC randomisation. |
| `satori-branding` | `os-release`/`issue` via `dpkg-divert` (these files are owned by `base-files`), wallpapers, GRUB theme, logo assets. |
| `satori-installer` | The gum TUI installer ([docs/installer.md](docs/installer.md)). Installed in the live image only, removed from the target. |
| `gum` | Only if gum isn't packaged in Excalibur: a pinned upstream release, checksum-verified, repackaged. |

Rule: **no loose overlay files for anything a user might need updated.** The
`includes.chroot/` overlay is reserved for live-session-only tweaks.

Because there's no hosted repo in v1 (D-006), installed systems get Devuan updates
through APT but get satori package updates only by manually installing newer `.deb`s.
This limitation should be documented for users.

### 3.4 Desktop stack
herbstluftwm on Xorg, started with `startx` from a tty1 login (P-014). The full
component list, keybindings, and session startup order are in
[docs/desktop-stack.md](docs/desktop-stack.md).

### 3.5 Installer
A gum-based TUI that copies the live filesystem to disk. It supports guided
whole-disk installs, with optional LUKS2 encryption, on BIOS and UEFI. Design:
[docs/installer.md](docs/installer.md).

### 3.6 Security and privacy defaults
- Installer offers LUKS2 full-disk encryption (the root filesystem and swapfile are encrypted; `/boot` isn't).
- nftables firewall enabled: inbound traffic denied except established/related, all outbound allowed.
- `sudo` for the installer-created user; the root account is locked.
- No `popularity-contest`. Firefox ESR policies turn off telemetry, studies, and sponsored content.
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
3. Every installed package whose name contains `systemd` is on an explicit allowlist in `tests/systemd-allowlist.txt`. We expect `libsystemd0` to be on it. Phase 0 settles the final list, and each entry needs a comment explaining why.

Rules 2 and 3 are checked by `scripts/check-no-systemd.sh` against every build's
package manifest. Rule 1 is checked at runtime by the QEMU smoke test. A failure
fails the build.

## 5. Build, test and release

### 5.1 Build
```
scripts/build.sh            # builds container → builds packages/ → lb clean/config/build
```
Output goes to `out/` (git-ignored):
- `satori-<version>-amd64.iso` and `.sha256`
- `satori-<version>-amd64.packages`: the package manifest
- `build-info.txt`: git SHA, dirty flag, build date, container image digest, live-build version

### 5.2 Test
- `scripts/test-in-qemu.sh`: boots the ISO under SeaBIOS or OVMF, either interactively or headless over the serial console.
- `tests/` automated smoke tests, driven over the serial console:
  - The live image boots on BIOS and UEFI, a login prompt appears, and the no-systemd runtime check passes.
  - Install matrix: {BIOS, UEFI} × {plain, LUKS} = 4 unattended installs (answers file, [docs/installer.md](docs/installer.md) §6). Each installed system must reboot to a login prompt and pass the checks.
- Manual QA checklist in `docs/testing.md`, for things that are hard to automate on real hardware: Wi-Fi, audio, suspend/resume, backlight, external monitors.

### 5.3 Reproducibility
v1 promises a **repeatable** build. The same git SHA and the same container digest
produce an ISO with the same package set, apart from newer versions from Devuan
mirrors. The package manifest records exactly what went in. Bit-for-bit
reproducibility is a possible later goal.

### 5.4 Versioning and release
- Versions follow `<major>.<minor>`, with the Devuan base in the release notes, for example "satori 0.1 (Excalibur)".
- Git tags `v0.1` etc. Release artifacts are the ISO, its checksum, the manifest, and build-info. Where releases are hosted is still open.
- `CHANGELOG.md` is maintained from Phase 1 onward.

### 5.5 Licensing
- Scripts and configs: to be decided (open question, see DECISIONS.md).
- Branding assets: licensed separately, noted in `branding/LICENSE`.

## 6. Repository layout

```
satori/
├── README.md
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
│       ├── includes.chroot/       # live-session-only overlays
│       ├── includes.binary/
│       └── hooks/{normal,live}/
├── packages/
│   ├── satori-desktop/debian/
│   ├── satori-config/{debian/,files/}
│   ├── satori-branding/{debian/,files/}
│   └── satori-installer/{debian/,src/}
├── branding/                      # source assets (SVG etc.) → rendered into satori-branding
├── scripts/
│   ├── build.sh
│   ├── build-packages.sh
│   ├── check-no-systemd.sh
│   └── test-in-qemu.sh
├── tests/
│   ├── systemd-allowlist.txt
│   ├── answers/                   # installer answer files for the test matrix
│   └── smoke/                     # serial-console test scripts
└── docs/
    ├── building.md
    ├── customizing.md
    ├── desktop-stack.md
    ├── installer.md
    └── testing.md
```

## 7. Phases and acceptance criteria

Each phase is one or more small commits and ends only when every one of its criteria passes.

**Phase 0: Feasibility spike**
- A throwaway live-build config for Excalibur produces a console-only hybrid ISO.
- ✅ The ISO boots to a login prompt in QEMU on SeaBIOS and OVMF.
- ✅ The manifest is inspected, the allowlist in §4 is drafted, and no forbidden packages are present.
- ✅ Findings are recorded in DECISIONS.md: whether live-build is confirmed or replaced (D-003), whether gum is packaged in Excalibur, and which `lb config` flags were needed.

**Phase 1: Build system**
- Scaffold the layout in §6: the container, `build.sh`, `check-no-systemd.sh`, and the manifest and build-info outputs.
- ✅ `scripts/build.sh` on a clean checkout produces an ISO without manual steps.
- ✅ An automated live boot test (BIOS and UEFI) plus the systemd runtime check pass.

**Phase 2: Desktop stack**
- `satori-desktop` and `satori-config` packages. The live session autologs in and starts herbstluftwm.
- ✅ The live session reaches herbstluftwm with the bar, launcher, notifications, network applet, and working audio (manual check in QEMU, plus on at least one real laptop).
- ✅ Every added package passes the no-systemd check. Any substitutions are documented in docs/desktop-stack.md.

**Phase 3: Installer**
- `satori-installer` (and `gum` if it has to be vendored).
- ✅ All four unattended install-matrix runs pass (§5.2).
- ✅ An interactive install on real hardware, with LUKS, boots and passes the manual checklist.

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
- Keep SPEC.md and DECISIONS.md current. When a proposed decision (P-xxx) is confirmed or changed, update both files in the same commit.
- Before adding any package, check that it exists in Excalibur and run the no-systemd check. Package names and systemd-free substitutes change between releases.
- Never download build inputs without pinning them (a checksum or container digest).
