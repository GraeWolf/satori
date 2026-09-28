# Decision Log

Status values: **Decided** (confirmed by the maintainer), **Proposed** (a default
that needs confirmation, safe to build on until changed), **Open** (needs an answer
before the phase listed).

When a decision changes, edit the entry in place and add a dated line to its
*History*. Don't delete entries.

---

## Decided

### D-001 Base: Devuan Excalibur
- **Status:** Decided (2026-09-28)
- **Why:** Excalibur is the current Devuan stable release. Daedalus is oldstable, and starting a new distro on it would shorten the support window for no benefit.

### D-002 Init: sysvinit
- **Status:** Decided
- **Why:** It's Devuan's default and the best-tested path. runit and OpenRC are out of scope for v1.

### D-003 Build tool: live-build (provisional)
- **Status:** Decided, subject to Phase 0 validation
- **Why:** It's scriptable, well documented, and supports hybrid ISOs, package lists, hooks, and local `.deb` injection.
- **Risk:** live-build is Debian's tool, not Devuan's official tool, and it defaults to Debian mirrors.
- **Fallback:** Devuan live-sdk or refracta tooling, if Phase 0 can't produce a clean systemd-free image.

### D-004 Desktop: herbstluftwm on X11
- **Status:** Decided
- **Why:** The maintainer prefers it, and the target audience is technical users (D-007).
- **Consequence:** The spec has to choose every component a desktop environment would otherwise provide (see [docs/desktop-stack.md](docs/desktop-stack.md)). Wayland is out of scope.

### D-005 Installer: gum TUI, guided whole-disk, optional LUKS
- **Status:** Decided (2026-09-28)
- **Scope (v1):** One target disk, fully wiped. ext4. Optional LUKS2. BIOS and UEFI. No manual partitioning or dual-boot.
- **Why:** This is the smallest installer that covers a daily-driver laptop. Every extra layout multiplies the test matrix.

### D-006 In-repo `.deb` packages, no hosted repository
- **Status:** Decided (2026-09-28)
- **Why:** Packaged config survives upgrades, can use `dpkg-divert` for files owned by other packages, and can be cleanly removed. Hosting a repo is deferred to keep v1 small.
- **Consequence:** Installed systems don't receive satori package updates automatically. Revisit after v0.1.

### D-007 Audience: technical users
- **Status:** Decided (2026-09-28)
- **Consequence:** No GUI settings apps. The docs may assume Linux literacy. Discoverability is handled with a keybinding cheatsheet.

### D-008 Name: satori
- **Status:** Decided

### D-009 Architecture: amd64 only
- **Status:** Decided

### D-010 Definition of "systemd-free"
- **Status:** Decided. The allowlist gets finalised in Phase 0.
- See [SPEC.md §4](SPEC.md#4-the-no-systemd-rule). `libsystemd0` (and anything else that turns out to be unavoidable) is allowed only through a commented allowlist entry.

---

## Proposed (confirm or override)

### P-011 Networking: NetworkManager + nm-applet
- **Why:** Best Wi-Fi/VPN coverage and works under Devuan with elogind. `nmcli`/`nmtui` suit the audience. connman and ifupdown are weaker on laptops.

### P-012 Audio: PipeWire (pipewire-pulse, WirePlumber)
- **Why:** It's the Trixie-era default. Without systemd user units, the X session starts it from autostart (see desktop-stack.md). Verify in Phase 2.

### P-013 Include non-free firmware
- **Why:** A laptop daily driver without Wi-Fi or GPU firmware isn't usable. This means enabling the `non-free-firmware` area plus `firmware-linux`, `firmware-iwlwifi`, `firmware-realtek`, `firmware-amd-graphics`, and so on.

### P-014 Login: console login on tty1 + `startx`, no display manager
- **Why:** It's the simplest setup and has the fewest moving parts. elogind still registers the session through PAM. The live session autologins on tty1.
- **Alternative:** LightDM, if a graphical greeter is wanted later.

### P-015 No Plymouth in v1
- **Why:** It's cosmetic, and it complicates the LUKS prompt and debugging. We'll have a GRUB theme and a text boot instead.

### P-016 Secure Boot not supported in v1
- **Why:** It needs Devuan's shim and signed GRUB chain checked for the ISO and for installed systems. Documented as "disable Secure Boot" for v1. Revisit once Phase 3 is stable.

### P-017 Swap: swapfile, no hibernation
- **Why:** A swapfile inside the (optionally encrypted) root avoids a separate encrypted swap partition. Hibernation to an encrypted swapfile adds a lot of complexity.

### P-018 Filesystem: ext4
- **Why:** Simple and robust. btrfs snapshots are a possible v2 feature.

---

## Open

### O-019 Repository license
- Needed before the first public push. The candidates are GPL-3.0-or-later (matches most of the ecosystem) or MIT/Apache-2.0 (permissive). Branding assets are licensed separately.

### O-020 Where release ISOs are hosted
- Needed before Phase 6. Options include GitHub Releases, a self-hosted server, or SourceForge.

### O-021 Is gum packaged in Excalibur?
- Answered in Phase 0. If it isn't, we vendor a pinned upstream release (checksum-verified) as an in-repo `gum` package.
