# Tekne — Project Specification

> Living document. Decisions and their rationale live in [DECISIONS.md](DECISIONS.md);
> this file describes *what* Tekne is and *how we'll know each phase is done*.
> Detailed designs: [docs/desktop-stack.md](docs/desktop-stack.md), [docs/installer.md](docs/installer.md).

## 1. Overview

**Tekne** is a systemd-free, amd64 desktop Linux distribution built as a respin of
**Devuan Excalibur** (Devuan 6, Debian Trixie-based). It ships a preconfigured
**herbstluftwm** tiling desktop on X11 and a keyboard-driven **TUI installer** built
with `gum`.

### Goals
- A hybrid (BIOS + UEFI) ISO that boots to a working live desktop and installs to disk.
- No systemd as init or as a package, as defined precisely in §4.
- Opinionated, keyboard-first defaults that a technical user can adopt or strip down easily.
- The whole build is scripted from this repository. There are no manual or undocumented steps.
- tekne-specific configuration ships as `.deb` packages, so it survives `apt upgrade` and stays under dpkg's control.

### Non-goals (v1)
- Custom kernel or kernel patches. We use Devuan's stock kernel, from `excalibur-backports` (DEC-036).
- Hosting or mirroring Devuan packages. Tekne packages are built in-repo and baked into the ISO (DEC-006). From 0.2, Tekne's own APT repository carries only those packages (DEC-040). Third-party repositories are allowed only under DEC-026.
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
- Documentation can assume Linux literacy. It still has to be complete for anything tekne-specific, such as keybindings, config locations, and how to rebuild.
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
| Kernel | Devuan/Debian stock `linux-image-amd64`, from `excalibur-backports` (DEC-036) |
| Package manager | APT, unmodified |
| Third-party repos | Brave (`brave-origin`, `brave-keyring`) and XLibre for Devuan (`xlibre*`), each pinned to specific packages (DEC-026) |
| Tekne repo | From 0.2: `https://graewolf.github.io/tekne/apt/`, pinned to `tekne-*` packages (DEC-040) |

### 3.2 Build tooling
- **Debian's live-build** (`1:20250505+deb13u1`, pinned by checksum), configured for Devuan (DEC-003). Devuan's own `live-build` package is a 2016 fork without UEFI support, so it isn't used.
  - All `lb config` flags live in `live-build/auto/config`. Nobody types flags by hand.
  - Mirrors, distribution, and archive areas must be set explicitly to Devuan values. live-build defaults to Debian.
  - BIOS and UEFI both boot through GRUB (`--bootloaders "grub-pc grub-efi"`), so there's one boot menu config.
  - live-build's package cache lives outside the per-build work directory, so rebuilds don't re-download everything.
  - Third-party repositories (DEC-026) are added to the build chroot from the same pinned keys and `.sources` files that `tekne-apt-sources` ships. The build fails if a key doesn't match its recorded checksum.
- **Build host:** a privileged Devuan Excalibur container (Podman or Docker) defined in `container/`, with the base image pinned by digest (DEC-031). The host OS doesn't matter. It only needs the container engine and root.
- **In-repo packages:** `packages/*` are built with `debhelper` inside the same container, then placed in `live-build/config/packages.chroot/` before `lb build`.

### 3.3 Tekne packages
| Package | Contents |
|---|---|
| `tekne-desktop` | Metapackage that depends on the full desktop stack ([docs/desktop-stack.md](docs/desktop-stack.md)). Installed during the build by a chroot hook, after `tekne-apt-sources` has configured the third-party repositories (DEC-026). |
| `tekne-config` | System-wide defaults in `/usr/share/tekne/` (used only when the user has no config of their own): the `tekne-session` X session, herbstluftwm autostart and keybindings, polybar and picom configs, startx on tty1, the default browser, browser policies, firewall ruleset, NetworkManager MAC randomisation. Helper scripts: `tekne-run-once`, `tekne-keys`, `tekne-powermenu`, `tekne-screenshot`, `tekne-get-melia` (DEC-029), and later `tekne-swap-resize` (DEC-017). |
| `tekne-apt-sources` | Third-party `.sources` entries, their pinned signing keys, and `/etc/apt/preferences.d/` pins (DEC-026); also Devuan's `excalibur-backports`, pinned to the kernel packages (DEC-036), and from 0.2 Tekne's own repository, pinned to `tekne-*` (DEC-040). |
| `tekne-branding` | `os-release` via `dpkg-divert` (owned by `base-files`; `/etc/issue` is a conffile and can't be diverted, see DEC-035), wallpaper, GRUB theme, logo, rendered from `branding/` (DEC-034). |
| `tekne-installer` | The gum TUI installer ([docs/installer.md](docs/installer.md)) and the QEMU-only `tekne-autoinstall` init script. Installed in the live image only, purged from the target. |

Rule: **no loose overlay files for anything a user might need updated.** The
`includes.chroot/` overlay is reserved for live-session-only tweaks.

In 0.1 there's no hosted repository (DEC-006), so installed systems get Devuan updates
through APT but get Tekne package updates only by manually installing newer `.deb`s.
From 0.2, Tekne's packages are also published in a signed APT repository (DEC-040,
§8), and `apt upgrade` covers both.

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
- nftables firewall enabled: inbound traffic denied except established/related and local container/VM bridges, forwarding only for those bridges and deliberately published ports, all outbound allowed (DEC-023).
- `sudo` for the installer-created user; the root account is locked.
- No `popularity-contest`. Firefox ESR policies turn off telemetry, studies, and sponsored content. Brave Origin's remaining telemetry, if any, is switched off with managed policies.
- NetworkManager uses randomised MAC addresses when scanning Wi-Fi.
- No services listen on the network by default. There's no SSH server.

### 3.7 Branding
- Name "Tekne". `/usr/lib/os-release` diverted to a Tekne version that keeps `ID_LIKE=devuan debian`.
- GRUB theme on both the live ISO and installed systems. Default wallpaper. Text boot (no Plymouth in v1), styled: Tokyo Night console colours and a centred banner above the LUKS prompt (DEC-037).
- Tokyo Night colours throughout, with placeholder artwork (a geometric T) until real art exists; GTK uses dark Adwaita with Papirus icons (DEC-034).
- Devuan and Debian logos and trademarks removed from user-visible branding. Attribution to Devuan kept in `os-release`, the docs, and `/usr/share/doc`.

## 4. The "no systemd" rule

An image **passes** only if all of these hold:
1. PID 1 is sysvinit's `init`, and `/run/systemd/system` doesn't exist.
2. None of these packages are installed: `systemd`, `systemd-sysv`, `systemd-timesyncd`, `systemd-resolved`, `systemd-boot`, `libpam-systemd`.
3. Every installed package whose name contains `systemd` is on an explicit allowlist in `tests/systemd-allowlist.txt`. It's empty: Phase 0 allowed `libsystemd0`, which the desktop image no longer has (DEC-010). Each entry needs a comment explaining why. The base package list must include `opensysusers` so that nothing pulls in `systemd-standalone-sysusers`.

Rules 2 and 3 are checked by `scripts/check-no-systemd.sh` against every build's
package manifest. Rule 1 is checked at runtime by the QEMU smoke test. A failure
fails the build.

## 5. Build, test and release

### 5.1 Build
```
sudo scripts/build.sh       # builds container → builds packages/ → lb config/build → no-systemd check
```
The version comes from the `VERSION` file. A clean checkout of tag `v<VERSION>` builds as `<VERSION>`; anything else builds as `<VERSION>-dev<commit count>.<short commit>` (§5.4).
Output goes to `out/` (git-ignored):
- `tekne-<version>-amd64.iso` and `.sha256`
- `tekne-<version>-amd64.packages`: the package manifest
- `build-info.txt`: git SHA, dirty flag, build date, base image digest, build image ID, live-build version, ISO size and checksum, package count, and each Tekne `.deb`'s SHA-256 (DEC-040)
- `build.log`: the full live-build log
- `packages/`: Tekne's `.deb`s
- `test-repo/`: a test copy of Tekne's APT repository, signed with a throwaway key made for this build, for `tests/smoke/repo.py` (DEC-040)
- `cache/`: live-build's downloaded-package cache, reused between builds (root-owned)

### 5.2 Test
- `scripts/test-in-qemu.sh`: boots the ISO under SeaBIOS or OVMF in a QEMU window, for hands-on testing.
- `tests/smoke/` automated tests, driven over the serial console. The live ISO's GRUB menu has a "serial console" entry (hotkey `s`) that sends kernel output to `ttyS0` and starts a serial login prompt. Tests press `s` at the menu; the default entry is unaffected.
  - `tests/smoke/live-boot.py`: the live image boots on BIOS and UEFI, a login prompt appears, and the no-systemd runtime check passes.
  - `tests/smoke/repo.py`: in the live image, apt accepts the build's test repository only with its key, refuses a tampered `.deb`, and the shipped pin keeps everything but `tekne-*` at -1 (DEC-040).
  - `tests/smoke/upgrade.py`: installs the previous release from its published ISO (pinned in `tests/smoke/previous-release`), upgrades it to the current build with `apt upgrade` from the build's test repository, reboots and re-runs `install.py`'s checks, hibernate/resume included (DEC-040). It can also start from a kept `install.py` case.
  - `tests/smoke/install.py`: install matrix, {BIOS, UEFI} × {plain, LUKS} = 4 unattended installs (answers file via QEMU fw_cfg, [docs/installer.md](docs/installer.md) §6). Each installed system must boot to a login prompt and pass `tests/smoke/installed-checks.sh`. `tests/smoke/qemu_serial.py` holds the shared QEMU and serial-console code.
- `tests/key-rotation.sh`: the signing-subkey rotation in `docs/building.md`, with throwaway keys and APT, in the build container on every build (DEC-040).
- Manual QA checklist in `docs/testing.md`, for things that are hard to automate on real hardware: Wi-Fi, audio, suspend/resume, hibernate/resume, backlight, external monitors.

### 5.3 Reproducibility
v1 promises a **repeatable** build. The same git SHA and the same container digest
produce an ISO with the same package set, apart from newer versions from Devuan
mirrors. The package manifest records exactly what went in. Bit-for-bit
reproducibility is a possible later goal.

### 5.4 Versioning and release
- Versions follow `<major>.<minor>`, with the Devuan base in the release notes, for example "Tekne 0.1 (Excalibur)".
- Git tags `v0.1` etc. Release artifacts are the ISO, its checksum, the manifest, and build-info.
- `VERSION` holds the next release (`0.1`, `0.1-rc1`, ...). A clean checkout of tag `v<VERSION>` builds as that version. Anything else builds as `<VERSION>-dev<commit count>.<short commit>`. Tekne's `.deb`s get the Debian form of the same version, which always increases (DEC-032). After tagging a release, bump `VERSION` to the next one: after a release candidate, the next candidate, because `0.1~dev…` sorts below `0.1~rc2` (DEC-032).
- Releases are published on GitHub Releases (DEC-020). Each asset must be under 2 GiB, so the ISO size is tracked in build-info from Phase 2 on.
- `CHANGELOG.md` is maintained from Phase 1 onward.

### 5.5 Licensing
- Everything in the repo except `branding/`: GPL-3.0-or-later (DEC-019), full text in `LICENSE`.
- Branding assets in `branding/`: CC-BY-SA-4.0 (DEC-019, DEC-034), full text in `branding/LICENSE`.

## 6. Repository layout

```
tekne/
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
│       ├── apt/apt.conf           # build only: keeps the build away from Tekne's own repository (DEC-040)
│       ├── package-lists/
│       │   ├── base.list.chroot
│       │   ├── live.list.chroot   # live-only: live-boot, live-config, tekne-installer
│       ├── packages.chroot/       # generated: tekne-*.deb (git-ignored)
│       ├── bootloaders/grub-pc/   # GRUB menu for BIOS and UEFI, incl. the serial test entry
│       ├── includes.chroot/       # live-session-only overlays
│       └── hooks/{normal,live}/
├── packages/
│   ├── tekne-desktop/debian/
│   ├── tekne-config/{debian/,files/}
│   ├── tekne-branding/{debian/,files/}
│   ├── tekne-apt-sources/{debian/,keys/,sources/,preferences/}
│   └── tekne-installer/{debian/,files/}
├── branding/                      # source SVGs (CC-BY-SA-4.0) → rendered into tekne-branding
├── scripts/
│   ├── build.sh                   # host side: container build + run (needs root)
│   ├── build-in-container.sh      # container side: live-build, checks, outputs
│   ├── build-packages.sh
│   ├── build-repo.sh              # Tekne's signed APT repository from .debs (DEC-040)
│   ├── check-no-systemd.sh
│   ├── ci-publish-repo.sh         # CI: publish the repository from published releases (DEC-040)
│   ├── ci-release.sh              # CI: draft GitHub release from a tested tag (DEC-039)
│   └── test-in-qemu.sh
├── tests/
│   ├── key-rotation.sh            # the signing-subkey rotation, with throwaway keys (DEC-040)
│   ├── systemd-allowlist.txt
│   └── smoke/                     # serial-console tests: live-boot.py, repo.py, install.py,
│                                  # upgrade.py, installed-checks.sh, qemu_serial.py
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

**Phase 2: Desktop stack**. ✔ Complete (2026-09-29). Smoke tests pass on BIOS and UEFI, and the maintainer checked the launcher, audio, network and browser by hand in QEMU. The real-laptop checks passed on the development laptop after the `v0.1-rc1` install (2026-09-29), apart from a missing battery indicator, fixed for rc2.
- `tekne-desktop` and `tekne-config` packages. The live session autologs in and starts herbstluftwm.
- ✅ The live session reaches herbstluftwm with the bar, launcher, notifications, the bar's network module (DEC-011), and working audio. `tests/smoke/live-boot.py` checks that every session process is running. Launcher, audio and network are checked by hand in QEMU and on at least one real laptop.
- ✅ Every added package passes the no-systemd check, including those from third-party repositories. Any substitutions are documented in docs/desktop-stack.md.
- ✅ Third-party repositories are restricted by their pins: `apt-cache policy` shows no Devuan package replaced by a Brave or XLibre package.
- ✅ Brave Origin is the default browser.
- ✅ The DEC-023 security defaults are in place: `tests/smoke/live-boot.py` checks that Tekne's firewall is loaded and that nothing listens beyond loopback; the browser and NetworkManager policy files are installed.
- ✅ `tekne-get-melia` installs Melia, and it refuses a download whose signature or checksum is wrong.

**Phase 3: Installer**. ✔ Complete (2026-09-29). All four unattended installs pass with hibernate/resume in QEMU, and the maintainer completed an interactive install and the keyring test in QEMU. On real hardware (2026-09-29): the maintainer installed `v0.1-rc1` interactively with LUKS on the development laptop, and it passed the manual checklist, the Phase 2 laptop checks and hibernate/resume. Hibernate/resume without LUKS is checked in QEMU only: the only laptop is encrypted.
- `tekne-installer` (using Excalibur's `gum` package, DEC-021).
- ✅ All four unattended install-matrix runs pass (§5.2).
- ✅ An interactive install in QEMU (`scripts/test-in-qemu.sh --disk`) completes and the installed system boots to the desktop.
- ✅ An interactive install on real hardware, with LUKS, boots and passes the manual checklist. This includes the Phase 2 desktop checks deferred from QEMU: Wi-Fi, audio, brightness keys, suspend and the lock screen.
- ✅ Hibernate and resume work in QEMU for all four install cases: `tests/smoke/install.py` hibernates each installed system and checks that the same session resumes. On real hardware too, with and without LUKS (DEC-017).
- ✅ On an installed system, Brave Origin saves and recalls a password through gnome-keyring without an extra unlock prompt (DEC-030). Moved from Phase 2: the live session autologins, so PAM has no password to unlock the keyring with.

**Release candidate gate (`v0.1-rc1`): before installing on the development laptop**. ✔ Passed (2026-09-29). `v0.1-rc1` (`c77c411`) built clean; the upgrade test moved an installed system from `0.1~dev20` to `0.1~rc1`; live-boot and all four install cases pass. The maintainer pushed the repository, backed up the laptop, disabled Secure Boot, and passed the live-USB hardware check, including the hybrid NVIDIA GPU with `nouveau` loaded (so Tekne doesn't blacklist it). Tekne `0.1-rc1` is installed on the development laptop, and Phases 4–6 continue there.
- The only laptop is also the development machine, and the installer erases the whole disk. So these must pass before Tekne is installed there. Phases 4–6 then continue on the installed system.
- ✅ Package versions increase with every build (DEC-032), and `tests/smoke/upgrade.py` upgrades an installed system from one build's packages to the next and re-runs the installed-system checks. That's how changes reach the laptop while dogfooding (DEC-006).
- ✅ One documented command installs everything needed to build and test Tekne on Tekne (DEC-033).
- ✅ `v0.1-rc1` is tagged and built from a clean tree, and its ISO passes `live-boot.py` and `install.py`.
- ✅ (maintainer) The repository is pushed and the laptop is backed up.
- ✅ (maintainer) A live-USB hardware check on the laptop passes: Wi-Fi, the AMD GPU on the internal display and an external monitor, audio, brightness keys, suspend/resume, and the hybrid NVIDIA GPU with `nouveau` loaded (boots, suspends, battery drain). If `nouveau` misbehaves, decide whether Tekne blacklists it.
- ✅ (maintainer) Secure Boot is disabled in the laptop's firmware (DEC-016).

**Phase 4: Branding**. ✔ Complete (2026-09-30). `tekne-branding`, the Tokyo Night theme and placeholder art (DEC-034). The build checks that os-release survives reinstalling `base-files`; the live ISO's GRUB menu shows only Tekne's theme and entries; `live-boot.py` and all four `install.py` cases pass on `0.1-rc2-dev34`. The console login greeting keeps Devuan's text (DEC-035).
- `tekne-branding`, the GRUB theme, wallpaper, and os-release diversion.
- ✅ `os-release` still shows Tekne after `apt install --reinstall base-files`.
- ✅ No Devuan or Debian logos appear on the boot menu, GRUB, or desktop.

**Phase 5: CI and QA**. ✔ Complete (2026-10-01). `.github/workflows/build.yml` (DEC-038, Decided): the first run on `master` ([36802153183](https://github.com/GraeWolf/tekne/actions/runs/36802153183), `b6b69e3`) built the ISO, passed `live-boot.py` and all four `install.py` cases, and kept the ISO as the `tekne-iso` artifact, in 38 minutes.
- A CI pipeline builds on push and runs the automated tests. `docs/testing.md` has the manual checklist.
- ✅ A green CI run on `master` (the default branch) produces downloadable ISO artifacts.

**Phase 6: Docs and first release**. ✔ Complete (2026-10-01). `docs/building.md`, `docs/customizing.md`, the README and the CHANGELOG are written. [Tekne 0.1](https://github.com/GraeWolf/tekne/releases/tag/v0.1) is released with its ISO, checksum, manifest and build-info, created by CI from a green build of the `v0.1` tag (`f302523`, DEC-039) after the [`v0.1-rc2` pre-release](https://github.com/GraeWolf/tekne/releases/tag/v0.1-rc2) passed a live-USB check on the development laptop.
- `docs/building.md`, `docs/customizing.md`, README, and CHANGELOG.
- ✅ The `v0.1` tag is released with its ISO, checksum, manifest, and build-info.

## 8. Tekne 0.2

> **Status:** agreed by the maintainer (2026-10-01) and recorded as DEC-040, which
> amends DEC-006. Phase 7 is complete; Phases 8–10 are built and in progress
> (2026-10-02). The repository goes live with the first published release,
> 0.2-rc1.

### 8.1 Theme: updates through APT

0.1's largest gap is updates. Devuan's packages update with `apt upgrade`, but
Tekne's own `tekne-*` packages reach an installed system only when someone builds
them from this repository and installs the `.deb`s by hand (DEC-006, §3.3). That
works for the maintainer and nobody else, and a fix to a firewall rule or a kernel
pin waits until each user rebuilds. DEC-006 said to revisit this after v0.1.

0.2 makes an installed Tekne updatable with apt alone: Tekne's packages are
published in a signed APT repository, held to the same rules as any outside
repository (DEC-026), and CI tests the upgrade from the last release on every build.
0.2 does little else, so that the new update path gets the release's full attention.

### 8.2 Goals
1. **A signed Tekne APT repository.** Installed systems get `tekne-*` updates with `apt update && apt upgrade`. The repository is held to DEC-026's rules like any third-party repository: its key is pinned by checksum in `tekne-apt-sources`, its `.sources` entry uses `Signed-By` with that key alone, and an APT pin limits it to `tekne-*` packages.
2. **Publishing behind the existing human gate.** The repository changes only when a person publishes a GitHub release (DEC-039), and it's built from that release's tested `.deb`s. Neither a push nor a tag reaches users' APT on its own.
3. **Tested upgrades.** On every build, CI installs the previous release from its published ISO and upgrades it to the current build through apt. This closes the `upgrade.py` gap in DEC-038's "Not covered".
4. **A defined path from 0.1.** A 0.1 system joins the repository with one documented step. After that, plain apt upgrades are enough.

### 8.3 Not in 0.2
§1's non-goals still apply. In particular:
- **Secure Boot (DEC-016).** Its kernel lockdown blocks hibernation (DEC-017), so it needs a design decision of its own, not packaging work. It's a candidate for a later spike.
- **Installer changes:** no manual partitioning, dual-boot or btrfs (DEC-005, DEC-018).
- **Dev builds in the repository.** Only tested pre-releases and releases are published. Dogfooding between candidates still uses `scripts/build.sh --packages-only`.
- **Devuan packages in the repository.** The repository carries Tekne's own packages only, and `tekne-installer` isn't published, since it belongs only in the live image.

### 8.4 Design
A summary; DEC-040 is the full decision.
- **Hosting:** GitHub Pages for this repository, next to the releases (DEC-020). Tekne's published `.deb`s total about 350 KB per release, well inside Pages' limits. Installed systems contact GitHub on `apt update`, as they already do for XLibre's repository. The URL, `https://graewolf.github.io/tekne/apt/`, is written into every installed system.
- **Suites:** `excalibur` carries releases. `excalibur-rc` carries pre-releases as well as releases, so a system that follows it also receives finals. Both have a `main` component and are generated with `apt-ftparchive` in the build container. `tekne-apt-sources` points at `excalibur`. A tester switches to `excalibur-rc` by editing one line of its `.sources` file.
- **Signing key:** a dedicated repository key, not anyone's personal key. Custody: the primary key stays offline with the maintainer. A signing subkey with a one-year expiry is a GitHub Actions secret in a `repo-publish` environment that needs the maintainer's approval to run, and only the publishing job can read it. That's the same split DEC-039 makes for the write token. Rotation ships the new public key in a `tekne-apt-sources` update before the old subkey expires.
- **Publishing:** the `release` job (DEC-039) also attaches the `tekne-*` `.deb`s, minus `tekne-installer`, to the draft release, so they're tested files too. A new `publish-repo` job runs when a person publishes that release (`release: published`). It checks each `.deb` against checksums recorded in the build's `build-info.txt`, regenerates the suites, signs them and deploys Pages.
- **Build isolation:** hook `0500` runs `apt-get update` with `tekne-apt-sources`'s files in place, so the Tekne source would be active inside the build chroot. The build disables it there, so an ISO only ever contains the packages built from its own commit.

### 8.5 Maintainer's answers (2026-10-01)
- **Q1, key custody:** a signing subkey held by CI behind an approval gate, with the primary key offline. Signing locally with the offline key was the alternative.
- **Q2, URL:** the plain `graewolf.github.io` address, not a domain of the maintainer's own.
- **Q3, pre-release suite:** yes, `excalibur-rc`.
- **Q4, anything else in 0.2:** no. Real artwork, a second-machine hardware check, DEC-035's option 3 and a Secure Boot spike all stay out.

### 8.6 Phases and acceptance criteria
Phase numbers continue from §7.

**Phase 7: Repository decisions**. ✔ Complete (2026-10-02). DEC-040 is Decided. The key exists, with its primary half on an offline USB stick. The `repo-publish` environment holds the signing subkey and its passphrase, and Pages deploys from GitHub Actions.
- DEC-040 for the repository (hosting, suites, key custody, publishing). DEC-006 gets a History line pointing to it, and §1, §3.1 and §3.3 change to match. Done 2026-10-01.
- (maintainer) Generate the key. Then create the `repo-publish` environment with the maintainer as required reviewer, store the signing subkey (`TEKNE_REPO_SIGNING_KEY`) and its passphrase (`TEKNE_REPO_SIGNING_PASSPHRASE`) as its secrets, and set Pages to deploy from GitHub Actions. Done 2026-10-02.
- ✅ The maintainer has marked the repository decision Decided, and Q1 to Q4 are answered. Passed 2026-10-01 (DEC-040, §8.5).
- ✅ The repository key exists. Its public half is in `packages/tekne-apt-sources/keys/` with a line in `SHA256SUMS`, and its fingerprint is in DECISIONS.md. The primary private key isn't on any machine or service CI can reach. Passed 2026-10-02: `tekne.gpg`, primary `2401BB77…D11D7B37` (DEC-040). Only the signing subkey goes to CI.

**Phase 8: Building and publishing the repository**. ✔ Complete (2026-10-03). `repo.py`, `live-boot.py` and all four `install.py` cases pass in CI. `v0.2-rc1` was built and tested by CI ([37076283810](https://github.com/GraeWolf/tekne/actions/runs/37076283810)); publishing it ran `publish-repo` ([37079968254](https://github.com/GraeWolf/tekne/actions/runs/37079968254)) after the maintainer's approval. Both suites verify against `keys/tekne.gpg` (signing subkey `82C3…F9F4`); `excalibur-rc` has the four packages at `0.2~rc1` and `excalibur` is empty. From this laptop (0.1), apt with the shipped source and pin offers `0.2~rc1` at 500, and the `.deb` it downloads matches the release's `build-info.txt`. GitHub renamed the `.deb` assets (`~` became `.`), which `ci-publish-repo.sh` handles by reading each package's contents. `repo.py` checks the shipped files in the live image; Phase 9's upgrade test checks them on an installed system.
- A script builds a signed repository from a directory of `.deb`s with a given key. `tekne-apt-sources` ships the source, key and pin. The `release` job attaches the `.deb`s, and the `publish-repo` job publishes them.
- ✅ The same script, run locally with a throwaway test key, produces the same layout as CI, so the repository can be tested without the real key.
- ✅ On an installed system, `apt-cache policy` shows the Tekne repository offering only `tekne-*` packages. Everything else from it is at priority -1 (DEC-026 rule 3). The build's global-key check still passes, because the Tekne key is trusted only through `Signed-By`.
- ✅ The build never fetches from the published repository. Every `tekne-*` package in the manifest is the one built from this commit, and `0510-check-apt-origins` fails the build otherwise.
- ✅ apt refuses the repository when its index is signed by another key, or when a `.deb` doesn't match its `Packages` checksum. This is tested in QEMU against a local copy, not the live site.
- ✅ Publishing a pre-release updates `excalibur-rc` only, and publishing a release updates both suites. A push, a tag or an unpublished draft changes nothing, and `publish-repo` is the only job that can read the signing key.
- ✅ `publish-repo` refuses any `.deb` whose checksum differs from the one in that build's `build-info.txt`.

**Phase 9: Upgrade testing in CI**. ✔ Complete (2026-10-02). `tests/smoke/upgrade.py` installs v0.1 from its released ISO (pinned in `tests/smoke/previous-release`) with UEFI and LUKS, runs the one-time step, upgrades with `apt upgrade` from the build's test repository, reboots, and passes every installed-system check, hibernate/resume included. CI's first run with it ([37067604103](https://github.com/GraeWolf/tekne/actions/runs/37067604103), `acbcf50`) was green in 39 minutes, moving all four packages from `0.1` to `0.2~rc1~dev57`.
- `tests/smoke/upgrade.py` can start from a release ISO and upgrade through apt from a repository served to the VM. That repository is built by Phase 8's script with the test key. Only the URL and the key differ from what installed systems use. The pin and the rest of the `.sources` entry are the shipped ones.
- ✅ The previous release's ISO is a pinned input: its checksum is committed in this repository and updated at each release, and CI checks the download against it.
- ✅ On every CI build, a UEFI+LUKS system installed from the previous release's ISO upgrades to the current build with `apt update && apt upgrade`, then passes `installed-checks.sh` and hibernate/resume. Until 0.2 is out, the previous release is 0.1, so this test also runs Goal 4's one-time step.

**Phase 10: Migration, docs, and the 0.2 release.** In progress (2026-10-02). The docs are written (README, `docs/customizing.md`, `docs/building.md`'s repository, key and rotation sections, CHANGELOG), and `tests/key-rotation.sh` passes on the host and in CI's build container, with Devuan's APT ([37071566366](https://github.com/GraeWolf/tekne/actions/runs/37071566366)). `v0.2-rc1` was published on 2026-10-03, and the development laptop, on 0.1, joined `excalibur-rc` with the one-time step and upgraded to `0.2~rc1` with `apt upgrade` the same day. Left: dogfooding rc1 on the laptop, then `v0.2`, which must reach the laptop with a plain `apt update && apt upgrade`. There's no rc2 (maintainer's decision, 2026-10-03); `VERSION` stays `0.2-rc2` meanwhile, so dev builds sort between rc1 and 0.2, and becomes `0.2` only in the release commit (DEC-032).
- README ("Update an installed Tekne"), `docs/customizing.md`, `docs/building.md` (publishing and key rotation), and CHANGELOG with 0.1's one-time step. DEC-039 is updated for the extra assets and the `publish-repo` job.
- ✅ (maintainer) The development laptop, running 0.1, joins `excalibur-rc` with the documented one-time step and installs `0.2-rc1` from it with `apt upgrade`. The next release then arrives with plain `apt update && apt upgrade`: a candidate or 0.2 itself, since `excalibur-rc` carries both. (Until 2026-10-03 this said "the next candidate"; the maintainer chose to dogfood rc1 and release 0.2 directly, without an rc2.)
- ✅ The key-rotation steps work against test keys: a system that trusts the old subkey accepts a `tekne-apt-sources` update carrying the new one, then verifies a repository signed with it.
- ✅ `v0.2` is released through CI (DEC-039), and publishing it updates `excalibur`. On a system freshly installed from the 0.2 ISO, `apt list --upgradable` shows no `tekne-*` packages.

## 9. Notes for Claude Code sessions
- Keep SPEC.md and DECISIONS.md current. When a decision's status or content changes, update DECISIONS.md (with a dated History line) and every doc that references its `DEC-nnn` ID in the same commit.
- Before adding any package, check that it exists in Excalibur and run the no-systemd check. Package names and systemd-free substitutes change between releases.
- Never download build inputs without pinning them (a checksum or container digest).
