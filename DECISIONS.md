# Decision Log

Each decision has a permanent ID (`DEC-nnn`) that never changes. Its current state
is in the **Status** line:

- **Decided**: confirmed by the maintainer.
- **Proposed**: a default that needs confirmation. It's safe to build on until changed.
- **Open**: needs an answer before the phase listed.
- **Superseded**: replaced by another decision (named in the entry).

When a decision changes, edit the entry in place and add a dated line to its
**History**. Don't delete entries or reuse IDs.

---

### DEC-001 Base: Devuan Excalibur
- **Status:** Decided
- **Why:** Excalibur is the current Devuan stable release. Daedalus is oldstable, and starting a new distro on it would shorten the support window for no benefit.
- **History:** 2026-09-28 decided.

### DEC-002 Init: sysvinit
- **Status:** Decided
- **Why:** It's Devuan's default and the best-tested path. runit and OpenRC are out of scope for v1.
- **History:** 2026-09-28 decided.

### DEC-003 Build tool: live-build
- **Status:** Decided, provisional on Phase 0
- **Why:** It's scriptable, well documented, and supports hybrid ISOs, package lists, hooks, and local `.deb` injection.
- **Risk:** live-build is Debian's tool, not Devuan's official tool, and it defaults to Debian mirrors.
- **Fallback:** Devuan live-sdk or refracta tooling, if Phase 0 can't produce a clean systemd-free image.
- **History:** 2026-09-28 decided, pending Phase 0.

### DEC-004 Desktop: herbstluftwm on X11
- **Status:** Decided
- **Why:** Keyboard-driven manual tiling, fully scriptable at runtime through `herbstclient`, with a small footprint and no desktop-environment dependencies to untangle from systemd. It suits the technical audience (DEC-007).
- **Consequence:** Every component a desktop environment would normally provide has to be chosen explicitly (DEC-025). Wayland is out of scope, because herbstluftwm is X11-only.
- **History:** 2026-09-28 decided.

### DEC-005 Installer: gum TUI, guided whole-disk, optional LUKS
- **Status:** Decided
- **Scope (v1):** One target disk, fully wiped. Filesystem per DEC-018. Optional LUKS2. BIOS and UEFI. No manual partitioning or dual-boot.
- **Why:** This is the smallest installer that covers a daily-driver laptop. Every extra layout multiplies the test matrix.
- **History:** 2026-09-28 decided.

### DEC-006 In-repo `.deb` packages, no hosted repository
- **Status:** Decided
- **Why:** Packaged config survives upgrades, can use `dpkg-divert` for files owned by other packages, and can be cleanly removed. Hosting a repo is deferred to keep v1 small.
- **Consequence:** Installed systems don't receive satori package updates automatically. Revisit after v0.1.
- **History:** 2026-09-28 decided.

### DEC-007 Audience: technical users
- **Status:** Decided
- **Consequence:** No GUI settings apps. The docs may assume Linux literacy. Discoverability is handled with a keybinding cheatsheet.
- **History:** 2026-09-28 decided.

### DEC-008 Name: satori
- **Status:** Decided
- **History:** 2026-09-28 decided.

### DEC-009 Architecture: amd64 only
- **Status:** Decided
- **History:** 2026-09-28 decided.

### DEC-010 Definition of "systemd-free"
- **Status:** Decided. The allowlist gets finalised in Phase 0.
- See [SPEC.md §4](SPEC.md#4-the-no-systemd-rule). `libsystemd0` (and anything else that turns out to be unavoidable) is allowed only through a commented allowlist entry.
- **History:** 2026-09-28 decided.

### DEC-011 Networking: NetworkManager (nmcli/nmtui)
- **Status:** Decided
- **Why:** Best Wi-Fi/VPN coverage and works under Devuan with elogind. `nmcli`/`nmtui` suit the audience. connman and ifupdown are weaker on laptops.
- **UI:** No tray applet. Wi-Fi is managed with `nmtui`/`nmcli`, and clicking polybar's network module opens `nmtui`.
- **History:** 2026-09-28 proposed and confirmed. Same day, the maintainer dropped `nm-applet` in favour of `nmtui` only.

### DEC-012 Audio: PipeWire (pipewire-pulse, WirePlumber)
- **Status:** Decided, to be verified in Phase 2
- **Why:** It's the Trixie-era default. Without systemd user units, the X session starts it from autostart ([docs/desktop-stack.md](docs/desktop-stack.md) §2).
- **Risk:** This is the component most likely to misbehave without systemd. Phase 2 has to confirm it works on real hardware.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-013 Include non-free firmware
- **Status:** Decided
- **Why:** A laptop daily driver without Wi-Fi or GPU firmware isn't usable. This means enabling the `non-free-firmware` area plus `firmware-linux`, `firmware-iwlwifi`, `firmware-realtek`, `firmware-amd-graphics`, and so on.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-014 Login: console login on tty1 + `startx`, no display manager
- **Status:** Decided
- **Why:** It's the simplest setup and has the fewest moving parts. elogind still registers the session through PAM. The live session autologins on tty1.
- **Alternative:** LightDM, if a graphical greeter is wanted later.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-015 No Plymouth in v1
- **Status:** Decided
- **Why:** It's cosmetic, and it complicates the LUKS prompt and debugging. We'll have a GRUB theme and a text boot instead.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-016 Secure Boot not supported in v1
- **Status:** Decided
- **Why:** It needs Devuan's shim and signed GRUB chain checked for the ISO and for installed systems. Documented as "disable Secure Boot" for v1. Revisit once Phase 3 is stable.
- **Note:** Secure Boot's kernel lockdown also blocks hibernation (DEC-017), so adding Secure Boot later means solving that too.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-017 Swap: swapfile sized for hibernation, hibernation supported
- **Status:** Decided
- **Design:**
  - A swapfile at `/swapfile` on the root filesystem, so it sits inside LUKS when encryption is chosen. That avoids a second encrypted partition or LVM.
  - Size: equal to installed RAM, rounded up to the next GiB, so a hibernation image always fits. The installer's minimum disk size grows accordingly ([docs/installer.md](docs/installer.md) §2).
  - Resume: the installer writes `RESUME=UUID=<root fs UUID>` and `RESUME_OFFSET=<swapfile physical offset>` (from `filefrag -v`) to `/etc/initramfs-tools/conf.d/resume`. The initramfs unlocks LUKS before it tries to resume, so one passphrase prompt covers both.
  - Trigger: `loginctl hibernate` (elogind), bound in the rofi power menu. The lid close action stays suspend.
- **Constraints:** The swapfile must not be recreated or moved without updating `RESUME_OFFSET`. `satori-config` ships a helper (`satori-swap-resize`) that does both. Hibernation is incompatible with Secure Boot lockdown (DEC-016).
- **Acceptance:** Phase 3 adds a hibernate/resume round trip to the manual hardware checklist, both with and without LUKS.
- **History:** 2026-09-28 proposed as "swapfile, no hibernation". Changed the same day by the maintainer to support hibernation.

### DEC-018 Filesystem: ext4
- **Status:** Decided
- **Why:** Simple and robust, and it supports swapfile hibernation with a fixed offset (DEC-017). btrfs snapshots are a possible v2 feature.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-019 Repository license: GPL-3.0-or-later
- **Status:** Decided
- **Why:** The repo is mostly scripts and configuration in a GPL-heavy ecosystem. Copyleft keeps derivative respins open.
- **Scope:** Everything in the repo except `branding/`, which carries its own license in `branding/LICENSE` (to be chosen in Phase 4).
- **History:** 2026-09-28 decided.

### DEC-020 Release hosting: GitHub Releases
- **Status:** Decided, "for now"
- **Why:** Free, integrates with CI (Phase 5), and supports checksums and release notes.
- **Constraint:** Each release asset must be under 2 GiB. The ISO size should be tracked from Phase 2 on.
- **History:** 2026-09-28 decided.

### DEC-021 Source of the `gum` binary
- **Status:** Decided, with the outcome recorded in Phase 0
- **Policy:** Use the Excalibur package if one exists. Otherwise vendor a pinned upstream release, verify its checksum, and repackage it as an in-repo `gum` `.deb`.
- **History:** 2026-09-28 decided. Phase 0 records which path applies.

### DEC-022 Accounts: sudo user, root locked
- **Status:** Decided
- **Why:** This is the norm for single-user workstations. The installer creates one sudo-capable user and locks the root password.
- **History:** 2026-09-28 recorded (previously only in SPEC.md §3.6 and installer.md).

### DEC-023 Security and privacy defaults
- **Status:** Decided
- **Defaults:**
  - nftables firewall: inbound denied except established/related, all outbound allowed.
  - No services listen on the network by default, and there's no SSH server.
  - No `popularity-contest`.
  - Firefox ESR policies turn off telemetry, studies, and sponsored content.
  - Brave Origin already strips most telemetry. Phase 2 checks what remains and switches it off with Chromium managed policies in `/etc/brave/policies/managed/`, if any is needed.
  - NetworkManager uses randomised MAC addresses when scanning Wi-Fi.
- **History:** 2026-09-28 recorded (previously only in SPEC.md §3.6). Same day, added the Brave Origin policy check (DEC-028).

### DEC-024 Time sync: chrony
- **Status:** Decided
- **Why:** It works without systemd and handles laptops that suspend and roam well. It replaces `systemd-timesyncd`, which the no-systemd rule forbids.
- **History:** 2026-09-28 recorded (previously only in docs/desktop-stack.md).

### DEC-025 Desktop component selection
- **Status:** Decided. Each package still has to be verified in Phase 2 (it must exist in Excalibur and pass the no-systemd rule).
- The component table and keybindings in [docs/desktop-stack.md](docs/desktop-stack.md) are the source of truth. This entry covers the choices not recorded elsewhere, such as the bar, launcher, notifications, compositor, lock screen, terminal, file manager, editor, and keybindings.
- **History:** 2026-09-28 recorded as Proposed. Same day, the maintainer revised it (XLibre, nautilus, neovim, no nm-applet, new keybindings) and it was marked Decided. Same day, the file manager was reverted from nautilus to thunar, to avoid nautilus's large GNOME dependency tree and its file indexer.

### DEC-026 Third-party APT repositories
- **Status:** Decided
- **Policy:** An outside repository (anything other than Devuan's) is allowed only if all of these hold:
  1. Its signing key is stored in this repo, and the build checks it against a recorded SHA-256 checksum.
  2. Its `.sources` entry uses `Signed-By:` for that key alone and ships in the `satori-apt-sources` package, not as a loose file. It stays enabled on installed systems, so they receive updates.
  3. An `/etc/apt/preferences.d/` pin restricts it to the packages we want from it. Everything else from it gets priority -1, so it can't replace Devuan packages.
  4. Its packages pass the no-systemd rule (SPEC §4), like any other package.
- **Current repositories:**
  - Brave (for `brave-origin*`, DEC-028)
  - XLibre for Devuan (for `xlibre*`/`xserver-xlibre*`, DEC-027)
  - Devuan `excalibur-backports`. It's a Devuan repository, but it's pinned to the packages XLibre needs.
- **Why:** Some chosen components aren't in Devuan stable. This doesn't conflict with DEC-006, which is about satori hosting its *own* repository.
- **History:** 2026-09-28 decided.

### DEC-027 X server: XLibre
- **Status:** Decided, to be verified in Phase 2
- **Why:** This is the maintainer's choice. XLibre is an actively developed fork of the Xorg server. It has dropped its libsystemd dependency, and the Devuan project publicly supports it.
- **Source:** The XLibre Devuan repository (`xlibre-debian.github.io/devuan`), which needs Excalibur backports. Its packages are signed by an individual volunteer's key (DEC-026 applies). Devuan maintainers are working on first-party packages. Switch to those when they reach Devuan stable.
- **Risks:**
  - It depends on a volunteer-run repository.
  - Compatibility with the proprietary NVIDIA driver is undocumented.
  - The fallback is Devuan's `xserver-xorg`, a package-list change only.
- **History:** 2026-09-28 decided (maintainer edit to desktop-stack.md).

### DEC-028 Browsers: Brave Origin (default) + Firefox ESR (fallback)
- **Status:** Decided
- **Why:**
  - Brave Origin is Brave without AI, crypto, VPN, Rewards, Tor and most telemetry, and it's free on Linux.
  - Firefox ESR comes from Devuan's own repositories. It stays as a fallback that doesn't depend on an outside repository.
- **Source:** `brave-origin` from Brave's official APT repository (DEC-026). Brave's stable channel only, never beta or nightly.
- **Default:** Set through the `x-www-browser` alternative and `mimeapps.list` in `/etc/skel` (shipped by satori-config).
- **History:** 2026-09-28 decided.

### DEC-029 Melia: install on demand, not bundled
- **Status:** Decided
- **Why:**
  - Melia is proprietary, closed-source, maintained by one person, and paid beyond one account.
  - Its redistribution terms don't clearly allow bundling it in an ISO.
  - It updates itself from inside the app, bypassing dpkg.
- **Design:**
  - `satori-config` ships `satori-get-melia`. It downloads the current `.deb` and signed `SHA256SUMS` from the project's GitHub releases.
  - It checks the signature against a key fingerprint stored in the package, then checks the checksum, then installs the `.deb` with `apt`.
  - A first-run notice or the keybinding cheatsheet mentions it.
- **Revisit if:** the author grants redistribution permission in writing, or publishes an APT repository.
- **History:** 2026-09-28 decided.

### DEC-030 Secret Service: gnome-keyring
- **Status:** Decided
- **Why:** Brave, Melia, Firefox and NetworkManager all store credentials through the Secret Service API. herbstluftwm provides none.
- **Design:** `gnome-keyring` plus `libpam-gnome-keyring` unlocks the keyring with the login password at tty1. `.xinitrc` starts the secrets component inside the session's D-Bus. It must be verified in Phase 2 that this works with elogind and `startx`.
- **History:** 2026-09-28 decided.
