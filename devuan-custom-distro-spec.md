# Project Spec: Custom Devuan-Based Desktop Distribution

## 1. Project Overview

**Project name:** satori
**Base distro:** Devuan (currently: Devuan Daedalus, tracking Debian Bookworm; confirm current stable release before starting)
**Purpose:** A desktop/workstation daily-driver Linux distribution, built as a respin of Devuan, with curated defaults, branding, and package selection — no systemd anywhere in the base system or dependency chain.
**Init system:** sysvinit (Devuan default)
**Build tool:** `live-build` (Debian/Devuan's official live-image build system)

### Goals
- Produce a bootable, installable ISO that installs a fully configured desktop environment out of the box.
- Avoid systemd and any packages that hard-depend on it.
- Provide sane, opinionated defaults (WM, theming, core apps) while remaining easy to rebuild/respin via scripted config.
- Keep the entire build reproducible from a git repo — no manual, undocumented steps.

### Non-goals (for v1)
- Custom kernel patches (use Devuan's stock kernel package initially).
- Custom package repository/mirror infrastructure (use upstream Devuan + Debian repos for v1).

---

## 2. Target Audience & Use Case
- Primary: privacy-conscious desktop users who want a systemd-free daily driver without doing a manual Devuan + WM install themselves.
- Assumes a single-user workstation/laptop use case, not server or embedded.

---

## 3. Technical Architecture

### 3.1 Base System
- **Base:** Devuan stable release (pin the exact release/codename as of build time — verify current version).
- **Package manager:** APT (standard `.deb`), no changes to package management.
- **Init:** sysvinit + standard Devuan `sysvinit-core` stack. No optional init alternatives (runit/OpenRC) in v1.

### 3.2 Build Tooling — live-build
- Use `live-build` to define:
  - `config/package-lists/` — curated package sets (base, desktop, apps, dev tools as optional list)
  - `config/includes.chroot/` — filesystem overlays (branding, configs, wallpapers, `/etc` tweaks)
  - `config/hooks/` — postinstall/live/chroot hooks for anything not doable via package lists alone
  - `auto/config` and `auto/build` — scripted, versioned build invocation (no manually-typed `lb config` flags)
- Output target: hybrid ISO (BIOS + UEFI boot), both live-boot and calamares/preseed-based installer paths considered (see §3.5).

### 3.3 Desktop Environment
_Decision needed — flag as an open question for the spec's first revision. Options to weigh:_
- **Xfce** — lightweight, mature, no systemd dependency issues, easiest to theme/brand.
- **MATE** — heavier but more full-featured, also systemd-independent.
- **LXQt** — lightest footprint.
> Recommendation to validate with you: start with **Xfce** for v1 — it's the path of least resistance for a Devuan-based respin and is what Devuan's own desktop-live images already use.

### 3.4 Package Selection
- **Core:** Xfce session, NetworkManager (or connman as systemd-free alternative — confirm), PulseAudio/PipeWire (verify systemd-free build), Firefox/ESR, file manager, terminal, text editor.
- **System tools:** GParted, htop, basic dev tools (git, build-essential) as an optional "developer" package list.
- **Explicitly excluded:** anything in Debian that pulls systemd as a hard dependency (Devuan's `libpam-elogind` / `elogind` substitution path should be used automatically via Devuan repos, but every added package needs an exclusion check).

### 3.5 Installer
- Options: **Calamares** (graphical, used by many independent distros, has known Devuan compatibility) vs. Debian-installer/preseed.
- Recommendation: Calamares for a friendlier desktop installer experience — confirm current Devuan/Calamares compatibility before committing.

### 3.6 Branding
- Custom distro name, wallpaper(s), Plymouth boot splash (systemd-free compatible), GRUB theme, `/etc/os-release` and `/etc/issue` overrides, custom app menu/logo assets.

---

## 4. Repository Structure (for Claude Code to scaffold)

```
project-root/
├── README.md
├── SPEC.md                      # this document
├── live-build/
│   ├── auto/
│   │   ├── config
│   │   └── build
│   ├── config/
│   │   ├── package-lists/
│   │   │   ├── base.list.chroot
│   │   │   ├── desktop.list.chroot
│   │   │   └── developer.list.chroot   # optional
│   │   ├── includes.chroot/
│   │   │   ├── etc/
│   │   │   └── usr/share/backgrounds/
│   │   └── hooks/
│   │       ├── normal/
│   │       └── live/
├── branding/
│   ├── wallpapers/
│   ├── plymouth-theme/
│   └── grub-theme/
├── scripts/
│   ├── build.sh                 # wraps lb clean/config/build
│   └── test-in-qemu.sh          # boots the resulting ISO in QEMU for smoke testing
├── docs/
│   ├── building.md
│   └── customizing.md
└── .github/ (or CI config)      # optional automated build/test pipeline
```

---

## 5. Build & Test Workflow
1. `scripts/build.sh` runs `lb clean`, `lb config` (reading from `auto/config`), then `lb build`.
2. Output ISO lands in a `build/` or `out/` directory (git-ignored).
3. `scripts/test-in-qemu.sh` boots the ISO in QEMU headless/GUI for a smoke test (does it boot, does the DE load, does networking come up).
4. Manual test checklist (documented in `docs/building.md`): boot BIOS + UEFI, run installer, verify no systemd present (`ps aux`, `dpkg -l | grep systemd` sanity check), verify audio/network/graphics.

---

## 6. Open Decisions to Resolve Before/During Build
These should be nailed down early since they affect package lists and hooks:
1. Window Manager: Herbstluftwm.
2. Network manager: NetworkManager vs connman vs ifupdown+wicd.
3. Sound server: PipeWire vs PulseAudio (verify systemd-free packaging status in current Devuan release).
4. Installer: TUI installer using GUM to make it look good.
5. Distro name/branding identity.
6. Whether to include non-free firmware (`firmware-linux-nonfree` etc.) for broader hardware support, or stay fully free-software.

---

## 7. Project Phases (suggested milestones for Claude Code to work through)

**Phase 1 — Bootstrap the build system**
- Scaffold repo structure above.
- Get a minimal, unbranded live-build config producing a bootable Devuan+Xfce ISO with no customization.

**Phase 2 — Package curation**
- Build out package lists (base/desktop/developer).
- Confirm systemd-free status of every added package; document substitutions used.

**Phase 3 — Branding & UX**
- Apply wallpapers, Plymouth/GRUB themes, os-release/issue overrides, default DE settings (panel layout, theme, default apps).

**Phase 4 — Installer integration**
- Wire up Calamares (or chosen installer) so the live image installs cleanly to disk.

**Phase 5 — Testing & CI**
- QEMU smoke tests, checklist-based manual QA, optional CI pipeline to build ISOs on tag/push.

**Phase 6 — Documentation & release**
- `docs/building.md`, `docs/customizing.md`, changelog, versioned ISO releases.

---

## 8. Notes for Claude Code Sessions
- This spec should be treated as a living document — update it as decisions in §6 are resolved.
- Before generating package lists or hooks, verify current package names/availability against the actual Devuan release in use (package sets and systemd-free substitutes change between Devuan releases).
- Prefer small, testable commits per phase (e.g., "Phase 1: minimal bootable ISO" as one PR/commit before adding branding).
