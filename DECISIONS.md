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

### DEC-003 Build tool: Debian's live-build, pinned
- **Status:** Decided, confirmed by Phase 0
- **What:** Debian trixie's `live-build` `1:20250505+deb13u1`, pinned by SHA-256, pointed at Devuan's mirrors and keyring. **Not** Devuan's own `live-build` package.
- **Why:** It's scriptable, well documented, and supports hybrid ISOs, package lists, hooks, and local `.deb` injection. Devuan's package (`4.0.3-1+devuan2`) is a 2016 fork of jessie-era live-build that was never updated. It has no `grub-efi` stage, so it can't build a UEFI-bootable ISO.
- **Phase 0 result:** The spike (`spike/phase0/`, removed in Phase 1 but kept in git history at `f96d08e`) built a 317 MB console-only hybrid ISO. It booted to a login prompt in about 16 s on both SeaBIOS and OVMF, with sysvinit as PID 1.
- **Required `lb config` settings** (full list in `live-build/auto/config`):
  - `--mode debian --distribution excalibur --parent-distribution excalibur`
  - Every `--mirror-*` and `--parent-mirror-*` option set to `http://deb.devuan.org/merged/`. Security then resolves to `excalibur-security` correctly.
  - `--keyring-packages devuan-keyring`
  - `--initsystem sysvinit`. live-build then adds `live-config-sysvinit` and `sysvinit-core`.
  - `--bootloaders "grub-pc grub-efi"`: GRUB for both firmware types, so one menu config and later one GRUB theme. The default BIOS loader (isolinux) has no menu timeout.
  - `--uefi-secure-boot disable` (DEC-016)
- **Carry into Phase 1:**
  - The build container needs Devuan's `debootstrap` (it has the `excalibur` script).
  - Install Debian's live-build `.deb` in the container, checksum-verified. The spike runs it from source, which needs a `dpkg-parsechangelog` shim.
  - Keep live-build's package cache outside the per-build work directory. The spike deletes it on every run, so rebuilds re-download everything.
  - The spike turned live-build's firmware autodetection off (`--firmware-chroot false`). Phase 2 must list DEC-013's firmware packages explicitly or prove that autodetection works against Devuan's mirrors.
- **Fallback (not needed):** Devuan live-sdk or refracta tooling.
- **History:** 2026-09-28 decided, pending Phase 0. Same day, Phase 0 confirmed it, and the choice was narrowed to Debian's current live-build after Devuan's fork was found to lack UEFI support.

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
- **Status:** Decided
- See [SPEC.md §4](SPEC.md#4-the-no-systemd-rule). A package whose name contains `systemd` is allowed only through a commented entry in `tests/systemd-allowlist.txt`.
- **Allowlist:** empty. Phase 0 allowlisted `libsystemd0`, a shared library with no daemon that `libpam-modules` depends on. The desktop image doesn't have it: Devuan's `libelogind-compat` replaces it (docs/desktop-stack.md), and the `0.1-rc1` manifest has no package whose name contains `systemd`.
- **Required substitutions:**
  - `opensysusers` (Devuan's systemd-free implementation) for the virtual package `systemd-sysusers`. Without it, apt satisfies dependencies like `cron-daemon-common`'s `systemd | systemd-standalone-sysusers | systemd-sysusers` with Debian's `systemd-standalone-sysusers`, which is built from systemd's source. `opensysusers` must be in the base package list.
  - Devuan provides `eudev` (and `libudev1` from it) in place of systemd's udev. This needs no action.
- **History:** 2026-09-28 decided. Same day, Phase 0 finalised the allowlist and recorded the `opensysusers` substitution. 2026-09-29: the maintainer emptied the allowlist, since `libsystemd0` no longer appears in the image.

### DEC-011 Networking: NetworkManager (nmcli/nmtui)
- **Status:** Decided
- **Why:** Best Wi-Fi/VPN coverage and works under Devuan with elogind. `nmcli`/`nmtui` suit the audience. connman and ifupdown are weaker on laptops.
- **UI:** No tray applet. Wi-Fi is managed with `nmtui`/`nmcli`, and clicking polybar's network module opens `nmtui`.
- **History:** 2026-09-28 proposed and confirmed. Same day, the maintainer dropped `nm-applet` in favour of `nmtui` only.

### DEC-012 Audio: PipeWire (pipewire-pulse, WirePlumber)
- **Status:** Decided, verified on real hardware
- **Why:** It's the Trixie-era default. Without systemd user units, the X session starts it from autostart ([docs/desktop-stack.md](docs/desktop-stack.md) §2).
- **Risk:** This is the component most likely to misbehave without systemd. Phase 2 has to confirm it works on real hardware.
- **History:** 2026-09-28 proposed and confirmed. 2026-09-29: verified in QEMU (Phase 2) and on the development laptop (speakers, headphones, microphone, volume keys).

### DEC-013 Include non-free firmware
- **Status:** Decided
- **Why:** A laptop daily driver without Wi-Fi or GPU firmware isn't usable. This means enabling the `non-free-firmware` area plus `firmware-linux`, `firmware-iwlwifi`, `firmware-realtek`, `firmware-amd-graphics`, and so on.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-014 Login: console login on tty1 + `startx`, no display manager
- **Status:** Decided
- **Why:** It's the simplest setup and has the fewest moving parts. elogind still registers the session through PAM. The live session autologins on tty1.
- **Alternative:** LightDM, if a graphical greeter is wanted later.
- **Live session:** autologin on tty1–6 comes from satori's own live-config component (`live-build/config/includes.chroot/usr/lib/live/config/0161-satori-autologin`), using agetty's `--autologin`. live-config's `0160-sysvinit` is broken on Excalibur (see docs/desktop-stack.md §2).
- **History:** 2026-09-28 proposed and confirmed. Same day (Phase 2), added the live-session autologin component.

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
  - Resume: the installer puts `resume=UUID=<root fs UUID> resume_offset=<swapfile physical offset>` (offset from `filefrag -v`) on the kernel command line via `GRUB_CMDLINE_LINUX`. initramfs-tools reads `resume_offset` only from the kernel command line. `/etc/initramfs-tools/conf.d/resume` gets `RESUME=UUID=…` so the resume hook is included. The initramfs unlocks LUKS before it tries to resume, so one passphrase prompt covers both.
  - Trigger: `loginctl hibernate` (elogind), bound in the rofi power menu. The lid close action stays suspend.
- **Constraints:** The swapfile must not be recreated or moved without updating `resume_offset`. `satori-config` ships `satori-swap-resize SIZE_GIB`, which recreates the swapfile, updates `/etc/default/grub` and runs `update-grub`, and writes `/sys/power/resume_offset` so hibernation works before the next reboot. Hibernation is incompatible with Secure Boot lockdown (DEC-016).
- **Acceptance:** `tests/smoke/install.py` hibernates and resumes all four install cases in QEMU. On real hardware it passed with LUKS on the development laptop (2026-09-29); without LUKS it's untested on real hardware.
- **History:** 2026-09-28 proposed as "swapfile, no hibernation". Changed the same day by the maintainer to support hibernation. 2026-09-29 (Phase 3): corrected the resume mechanism. `RESUME_OFFSET` in `conf.d` is not read by initramfs-tools; the offset goes on the kernel command line. Same day, hibernate/resume passed on real hardware with LUKS.

### DEC-018 Filesystem: ext4
- **Status:** Decided
- **Why:** Simple and robust, and it supports swapfile hibernation with a fixed offset (DEC-017). btrfs snapshots are a possible v2 feature.
- **History:** 2026-09-28 proposed and confirmed.

### DEC-019 Repository license: GPL-3.0-or-later
- **Status:** Decided
- **Why:** The repo is mostly scripts and configuration in a GPL-heavy ecosystem. Copyleft keeps derivative respins open.
- **Scope:** Everything in the repo except `branding/`, which carries its own license in `branding/LICENSE`: CC-BY-SA-4.0 (DEC-034).
- **History:** 2026-09-28 decided. 2026-09-29 (Phase 4): the maintainer chose CC-BY-SA-4.0 for `branding/`.

### DEC-020 Release hosting: GitHub Releases
- **Status:** Decided, "for now"
- **Why:** Free, integrates with CI (Phase 5), and supports checksums and release notes.
- **Constraint:** Each release asset must be under 2 GiB. The ISO size should be tracked from Phase 2 on.
- **History:** 2026-09-28 decided.

### DEC-021 Source of the `gum` binary
- **Status:** Decided
- **Policy:** Use the Excalibur package if one exists. Otherwise vendor a pinned upstream release, verify its checksum, and repackage it as an in-repo `gum` `.deb`.
- **Outcome (Phase 0):** Excalibur `main` packages `gum` `0.14.4-1+b6`, so we use the distro package and there's no vendored `gum` package.
- **History:** 2026-09-28 decided. Same day, Phase 0 found gum packaged in Excalibur.

### DEC-022 Accounts: sudo user, root locked
- **Status:** Decided
- **Why:** This is the norm for single-user workstations. The installer creates one sudo-capable user and locks the root password.
- **History:** 2026-09-28 recorded (previously only in SPEC.md §3.6 and installer.md).

### DEC-023 Security and privacy defaults
- **Status:** Decided
- **Defaults** (all shipped by `satori-config`):
  - **Firewall:** `/etc/satori/nftables.conf`, loaded at boot by the `satori-firewall` init script. Inbound traffic is dropped except loopback, established/related replies, the ICMPv6 and DHCPv6 traffic IPv6 needs, and traffic from local container and VM bridges. Forwarding is allowed only from those bridges, for replies, and for ports a container engine publishes (DNAT); everything else forwarded is dropped. All outbound traffic is allowed.
    - Devuan's `nftables` package ships only a systemd unit, so nothing else would load a ruleset at boot.
    - The ruleset replaces only its own `inet satori` table and never runs `flush ruleset`, so rules from other software (libvirt, Docker) survive.
    - Other software's accept rules can't override satori's drops (a drop in any nftables table is final), so the bridges are accepted in satori's own table: `podman*`, `cni-podman*`, `docker0`, `br-*` (Docker's user networks) and `virbr*` (libvirt). Without this, containers and VMs on a bridge network get no DNS and no network at all, which broke building satori on satori (DEC-033). Traffic from outside reaches a bridge only through a port someone publishes deliberately (`podman run -p`).
    - `satori-firewall` starts after `nftables`, in case `orphan-sysvinit-scripts` is installed later: that script's default config flushes everything.
  - **Nothing listens on the network.** The only listener is `chronyd` on loopback, and there's no SSH server. The smoke test fails if anything else listens beyond loopback.
  - **No `popularity-contest`.**
  - **Firefox ESR:** `/usr/share/firefox-esr/distribution/policies.json` turns off telemetry, studies, Pocket, and sponsored tiles and suggestions.
  - **Brave Origin:** Origin already removes most telemetry. The binary still honours `BraveP3AEnabled`, `BraveStatsPingEnabled`, `BraveWebDiscoveryEnabled` and `MetricsReportingEnabled`, so `/etc/brave/policies/managed/satori.json` sets all four to false as a backstop.
  - **NetworkManager:** `/etc/NetworkManager/conf.d/satori-privacy.conf` sets `wifi.scan-rand-mac-address=yes` explicitly. It's NetworkManager's default, pinned so a default change can't undo it.
- **History:** 2026-09-28 recorded (previously only in SPEC.md §3.6). Same day, added the Brave Origin policy check (DEC-028). 2026-09-29 (Phase 2): implemented, with the firewall and listener checks added to the smoke test. 2026-09-29: the maintainer approved accepting local container and VM bridges and published ports, after the firewall stopped `scripts/build.sh` resolving names on satori.

### DEC-024 Time sync: chrony
- **Status:** Decided
- **Why:** It works without systemd and handles laptops that suspend and roam well. It replaces `systemd-timesyncd`, which the no-systemd rule forbids.
- **History:** 2026-09-28 recorded (previously only in docs/desktop-stack.md).

### DEC-025 Desktop component selection
- **Status:** Decided. Phase 2 verified every package: each exists in Excalibur (or a DEC-026 repository) and passes the no-systemd rule.
- The component table and keybindings in [docs/desktop-stack.md](docs/desktop-stack.md) are the source of truth. This entry covers the choices not recorded elsewhere, such as the bar, launcher, notifications, compositor, lock screen, terminal, file manager, editor, and keybindings.
- **History:** 2026-09-28 recorded as Proposed. Same day, the maintainer revised it (XLibre, nautilus, neovim, no nm-applet, new keybindings) and it was marked Decided. Same day, the file manager was reverted from nautilus to thunar, to avoid nautilus's large GNOME dependency tree and its file indexer. Same day (Phase 2), the maintainer chose CopyQ to replace `clipmenu`, which isn't packaged in Excalibur. 2026-09-29: the Phase 2 package check is complete (see docs/desktop-stack.md).

### DEC-026 Third-party APT repositories
- **Status:** Decided
- **Policy:** An outside repository (anything other than Devuan's) is allowed only if all of these hold:
  1. Its signing key is stored in this repo, and the build checks it against a recorded SHA-256 checksum.
  2. Its `.sources` entry uses `Signed-By:` for that key alone and ships in the `satori-apt-sources` package, not as a loose file. It stays enabled on installed systems, so they receive updates.
  3. An `/etc/apt/preferences.d/` pin restricts it to the packages we want from it. Everything else from it gets priority -1, so it can't replace Devuan packages.
  4. Its packages pass the no-systemd rule (SPEC §4), like any other package.
  5. No package from that repository may leave its key somewhere APT trusts for every repository (such as `/etc/apt/trusted.gpg.d/`). Keeping each key scoped is the whole point of rule 2. Brave's `brave-keyring` links its key there from its postinst, unless it finds Brave's own sources file (`brave-browser-release.sources` with `Signed-By: /usr/share/keyrings/brave-browser-archive-keyring.gpg`). So `satori-apt-sources` ships exactly that file, puts satori's checksum-pinned key at that path, and diverts `brave-keyring`'s copy of the key aside. The build fails if any globally trusted key isn't owned by `devuan-keyring` or `debian-archive-keyring`.
- **In the build:** live-build's own mechanism for extra repositories (`config/archives/*.key.chroot`) trusts keys globally, so it isn't used. The package lists install `satori-apt-sources`, then the chroot hook `0500-satori-desktop` runs `apt-get update` and installs `satori-desktop`. The build therefore uses exactly the keys, sources and pins that installed systems use. The hook `0510-check-apt-origins` then fails the build if any installed package came from a third-party repository outside its pin.
- **Current repositories:**
  - Brave (for `brave-origin*`, DEC-028)
  - XLibre for Devuan (for `xlibre*`/`xserver-xlibre*`, DEC-027)
  - Devuan `excalibur-backports` was expected to be needed for XLibre, but isn't: every Phase 2 build resolved XLibre 25.2 from Excalibur stable alone. It isn't enabled.
- **Why:** Some chosen components aren't in Devuan stable. This doesn't conflict with DEC-006, which is about satori hosting its *own* repository.
- **History:** 2026-09-28 decided. Same day (Phase 2), added rule 5 after finding that `brave-keyring` installs a globally trusted key, and recorded how the build applies the policy.

### DEC-027 X server: XLibre
- **Status:** Decided, verified on real hardware
- **Why:** This is the maintainer's choice. XLibre is an actively developed fork of the Xorg server. It has dropped its libsystemd dependency, and the Devuan project publicly supports it.
- **Source:** The XLibre Devuan repository (`xlibre-debian.github.io/devuan`). XLibre's docs say Excalibur needs backports, but Phase 2 builds resolve without them. Its packages are signed by an individual volunteer's key (DEC-026 applies). Devuan maintainers are working on first-party packages. Switch to those when they reach Devuan stable.
- **Risks:**
  - It depends on a volunteer-run repository.
  - Compatibility with the proprietary NVIDIA driver is undocumented.
  - The fallback is Devuan's `xserver-xorg`, a package-list change only.
- **History:** 2026-09-28 decided (maintainer edit to desktop-stack.md). 2026-09-29: verified on the development laptop (AMD GPU on the internal and an external display, with the NVIDIA GPU on `nouveau`).

### DEC-028 Browsers: Brave Origin (default) + Firefox ESR (fallback)
- **Status:** Decided
- **Why:**
  - Brave Origin is Brave without AI, crypto, VPN, Rewards, Tor and most telemetry, and it's free on Linux.
  - Firefox ESR comes from Devuan's own repositories. It stays as a fallback that doesn't depend on an outside repository.
- **Source:** `brave-origin` from Brave's official APT repository (DEC-026). Brave's stable channel only, never beta or nightly.
- **Default:** `/etc/xdg/mimeapps.list` (shipped by satori-config) makes `brave-origin.desktop` the XDG default for web pages and links; a user's `~/.config/mimeapps.list` still wins. `satori-desktop`'s postinst points the `x-www-browser` alternative at `/usr/bin/brave-origin-stable`, on first install only, so a later choice survives upgrades.
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
- **Design:**
  - At a console login (PAM service `login`), `pam_gnome_keyring` receives the login password, starts the daemon, and creates or unlocks the `login` keyring with it.
  - `satori-session` then runs `gnome-keyring-daemon --start --components=secrets`, which attaches the running daemon to the X session's D-Bus.
  - Excalibur's `libpam-gnome-keyring` profile only handles password changes; Debian relies on display managers adding `pam_gnome_keyring` to their own PAM files, and satori has none (DEC-014). So `satori-config` ships the `pam-auth-update` profile `satori-gnome-keyring`: auth and session lines with `only_if=login`, so `sudo` and `su` never start keyring daemons for root.
  - It has priority -1, so it comes after `pam_elogind` (priority 0), which sets up the `XDG_RUNTIME_DIR` the daemon needs. `pam-auth-update` breaks priority ties by reverse name, which would otherwise put it first.
  - `tests/smoke/install.py` checks, on each installed system after a password login, that the daemon runs, the `login` keyring exists, and the PAM order is right.
- **History:** 2026-09-28 decided. 2026-09-29 (Phase 3): the maintainer's QEMU test found the keyring asking to be created at first login and to be unlocked at the next; added the `satori-gnome-keyring` PAM profile.

### DEC-031 Build container: pinned Devuan image, rootful Podman or Docker
- **Status:** Decided
- **What:**
  - `container/Containerfile` starts from `docker.io/devuan/devuan:excalibur`, pinned by digest.
  - It installs Devuan's `debootstrap` and Debian's live-build `.deb`, verified by SHA-256. The fallback download is snapshot.debian.org's permanent address for that file.
  - `sudo scripts/build.sh` builds the image and runs it `--privileged`. It uses Podman if installed, else Docker.
- **Why:**
  - It works the same on any host.
  - live-build needs chroots, mounts and device nodes, which require a rootful, privileged container. Rootless Podman can't create device nodes, so debootstrap fails there.
  - live-build runs in the container's own filesystem, so there are no bind-mount `nodev` problems. Only the `.deb` package cache is kept on the host (`out/cache/`).
- **Updating the pins:** Change the digest or the live-build version and checksums in the Containerfile in one commit, and note it in CHANGELOG.md.
- **History:** 2026-09-28 decided (Phase 1). 2026-09-29: the image build and the build run use the host's network (`--network=host`). On satori the firewall (DEC-023, before its amendment) blocked a bridge network's DNS, and the build needs no network isolation.

### DEC-032 Package versions increase with every build
- **Status:** Decided
- **Why:** Installed systems get satori updates by installing newer `.deb`s from `out/packages/` (DEC-006). APT only upgrades to a higher version, and every build used to produce version `0.1`.
- **Scheme:** `scripts/build.sh` derives the package version from `VERSION` and git; `scripts/build-packages.sh` stamps it into each package's changelog at build time.
  - A clean checkout of tag `v<VERSION>` gets `VERSION` itself, with `-` turned into `~` (`0.1-rc1` becomes `0.1~rc1`, which Debian sorts before `0.1`).
  - Any other build gets `<that>~dev<commit count>.g<short commit>`, e.g. `0.1~rc1~dev131.gb996478`. The commit count rises on every commit, so later builds sort higher, and every dev build sorts before the release it leads to.
  - After tagging a release, bump `VERSION` to the next one (e.g. `0.1-rc2`), so later dev builds sort above the tag.
  - Dirty-tree builds get the same version as their commit; `build-info.txt` records `git_dirty`.
- **History:** 2026-09-29 proposed (release candidate gate). Same day, confirmed by the maintainer after it carried the first update of the installed laptop from `0.1~rc1` to `0.1~rc2~dev22`.

### DEC-033 Developer tools: documented install, not in the ISO
- **Status:** Decided
- **Why:** Building and testing satori needs `git`, `podman`, QEMU and OVMF. Putting them in the ISO would push it towards GitHub's 2 GiB asset limit (DEC-020) and burden users who never build satori. This replaces SPEC's original optional `developer.list.chroot`, which was never built.
- **Design:** The README gives one `apt install` command, using Devuan packages only. On an installed satori it's all that's needed to run `scripts/build.sh` and the smoke tests.
- **History:** 2026-09-29 proposed (release candidate gate). Same day, confirmed by the maintainer after building satori on the installed laptop with the README command.

### DEC-034 Branding: Tokyo Night, placeholder art, CC-BY-SA-4.0
- **Status:** Decided
- **Theme:** Tokyo Night (night) everywhere satori styles something: the GRUB theme, wallpaper, herbstluftwm, polybar, rofi, dunst, alacritty and i3lock. Background `#1a1b26`, foreground `#c0caf5`, accent blue `#7aa2f7`, magenta `#bb9af7`, red `#f7768e`, dim `#565f89`.
- **Artwork:** placeholders until real art exists: an ensō (the Zen brush circle) in blue and magenta, with no text so rendering needs no fonts. Sources are SVGs in `branding/`, rendered to PNG when `satori-branding` is built (the build container has `librsvg2-bin`). Replacing a file with real art of the same name and size needs no code change.
- **License:** `branding/` is CC-BY-SA-4.0 (DEC-019); the rest of the repository stays GPL-3.0-or-later.
- **`satori-branding`** (identity): `/usr/lib/os-release` (and so `/etc/os-release`) says `ID=satori`, `ID_LIKE="devuan debian"`, `VERSION_CODENAME=excalibur`, with this build's version, and credits Devuan. Devuan's copy is diverted to `/usr/lib/os-release.devuan`, so reinstalling or upgrading `base-files` can't restore it. live-build's bootstrap stage turns `/etc/os-release` into a frozen copy of Devuan's file (with `IMAGE_ID=live`), which would also reach installed systems, so the build hook `0530-os-release` restores base-files' symlink to `/usr/lib/os-release`, then checks that os-release survives reinstalling `base-files`. Also the GRUB theme, the wallpaper (`/usr/share/backgrounds/satori/satori.png`) and the logo.
- **GRUB theme:** one `theme.txt` for the live ISO and installed systems, using GRUB's own `unicode.pf2` font. On installed systems `satori-branding` copies it to `/boot/grub/themes/satori`, because with LUKS GRUB can't read `/usr`, and `/etc/default/grub.d/satori-theme.cfg` sets `GRUB_THEME`. The live ISO shows it on screen and a plain text menu on the serial port, which the automated tests use. Its background also replaces live-build's default splash, which is Debian's artwork, and its entries are satori's own ("satori live", "satori live (safe graphics)") instead of live-build's "Live system".
- **Consequence:** GRUB's distributor name comes from `os-release`, so menu entries read "satori GNU/Linux". On UEFI, the next `grub-install` (for example when the GRUB package is upgraded) also creates an `EFI/satori` boot entry. Systems installed before satori-branding keep their old `devuan` entry alongside it.
- **Configuration** (`satori-config`, each used only when the user has no config of their own): `/etc/rofi.rasi` selects the rofi theme and is read before `~/.config/rofi/config.rasi`; `/etc/xdg/dunst/dunstrc.d/50-satori.conf` is a drop-in on dunst's own dunstrc; `satori-terminal` runs alacritty with `/usr/share/satori/alacritty.toml` (alacritty 0.15 has no system-wide config) and is now the `x-terminal-emulator` alternative, which had been xterm's `lxterm`.
- **GTK and icons:** Devuan packages no Tokyo Night GTK theme, so GTK apps get dark Adwaita (built into GTK) and Papirus-Dark icons (`papirus-icon-theme`, about 23 MB on the ISO), set in `/etc/xdg/gtk-3.0` and `gtk-4.0` `settings.ini` and a GSettings override. A packaged Tokyo Night GTK theme would need a third-party source (DEC-026).
- **Not changed:** `/etc/issue` and `/etc/issue.net` still name Devuan (DEC-035). `/etc/motd`'s Devuan notice is kept as attribution.
- **History:** 2026-09-29 decided (Phase 4): the maintainer chose placeholders, CC-BY-SA-4.0 and Tokyo Night. 2026-09-30: the first ISO build failed the os-release check because of live-build's copy; the hook now restores the symlink.

### DEC-035 Console login greeting (`/etc/issue`)
- **Status:** Open (before the Phase 4 acceptance check)
- **Problem:** the console login prompt, the first thing an installed satori shows after the LUKS prompt, reads "Devuan GNU/Linux excalibur". `/etc/issue` and `/etc/issue.net` are `base-files` conffiles, and dpkg can't divert a conffile, so SPEC §3.3's "`issue` via `dpkg-divert`" isn't possible.
- **Options:**
  1. Keep Devuan's text. The Phase 4 check is about logos, and this is text. Simplest.
  2. `satori-branding` rewrites `/etc/issue` on first install, only if it's still Devuan's unmodified text. dpkg then treats it as a local change: a later `base-files` update to that file asks which version to keep (rare, but it happens at Devuan releases). This breaks Debian policy, which says packages don't edit other packages' conffiles.
  3. The installer points the `getty` lines in `/etc/inittab` at a satori issue file (`agetty --issue-file`). That covers installed systems only, and lives in the installer rather than a package.
- **Recommendation:** option 1 for v0.1. Revisit if a satori `base-files` becomes worthwhile.
- **History:** 2026-09-29 opened (Phase 4).
