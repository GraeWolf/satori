# Building Tekne

How the ISO is built, tested and released, and where to change things. To
change an installed system rather than the build, see
[customizing.md](customizing.md). What Tekne is and why: [SPEC.md](../SPEC.md)
and [DECISIONS.md](../DECISIONS.md).

## Requirements

- A Linux host with root, Podman or Docker, and about 20 GB free. The build
  itself runs in a container, so the host distribution doesn't matter.
- Network access to Devuan's mirror and the Brave and XLibre repositories.
- For the tests: QEMU and OVMF, and ideally KVM (`/dev/kvm`).

On Tekne, or any Devuan or Debian host, one command installs all of it
(DEC-033):

```sh
sudo apt install git podman qemu-system-x86 qemu-utils ovmf python3
```

## Build

```sh
sudo scripts/build.sh                   # packages and ISO (about 10 min; the first build downloads about 1.5 GB)
sudo scripts/build.sh --packages-only   # just Tekne's .debs, for updating an installed system (about 1 min)
```

`scripts/build.sh` uses Podman if it's installed, otherwise Docker
(`CONTAINER_ENGINE=docker` forces Docker). Both the image build and the build
run use the host's network, so the host's firewall can't get in the way.

### What happens

1. **Build container.** `container/Containerfile` builds a Devuan Excalibur
   image, pinned by digest, with Debian's live-build `.deb` checked against its
   SHA-256 (DEC-003, DEC-031).
2. **Version.** From `VERSION` and git (DEC-032). A clean checkout of tag
   `v<VERSION>` builds as `<VERSION>`. Anything else builds as
   `<VERSION>-dev<commit count>.<short commit>`, and the packages get the
   Debian form, e.g. `0.1~rc2~dev40.gabc1234`, so every build upgrades the
   last.
3. **Packages.** Every directory under `packages/` is built with debhelper into
   `out/packages/`. `tekne-branding` also renders the SVGs in `branding/`.
4. **live-build.** `live-build/auto/config` holds every `lb config` option.
   The package lists and Tekne's packages are installed, then the chroot hooks
   run in order:

   | Hook | Does | Fails the build if |
   |---|---|---|
   | `0500-tekne-desktop` | `apt-get update` with `tekne-apt-sources`' repositories, then installs `tekne-desktop` | it can't install |
   | `0505-backports-kernel` | Switches to the `excalibur-backports` kernel and purges the stable one (DEC-036) | there isn't exactly one kernel, from backports |
   | `0510-check-apt-origins` | Checks the third-party repositories (DEC-026) | a globally trusted key isn't Devuan's or Debian's, or a third-party repository supplied a package outside its pin |
   | `0520-installer-grub-debs` | Downloads `grub-pc` and `grub-efi-amd64` for the installer | their versions don't match the installed GRUB binaries |
   | `0530-os-release` | Restores the `/etc/os-release` symlink live-build replaces | os-release doesn't say Tekne after reinstalling `base-files`, or the GRUB theme is missing from `/boot` |
   | `9900-fontconfig-cache` | Builds the system font cache | no cache was built |

5. **No-systemd check.** `scripts/check-no-systemd.sh` checks the package
   manifest against SPEC §4 and `tests/systemd-allowlist.txt` (which is
   empty).

### Outputs

In `out/`, with the build's version in each name:

| File | Contents |
|---|---|
| `tekne-<version>-amd64.iso` | Hybrid ISO, BIOS and UEFI (Secure Boot off) |
| `tekne-<version>-amd64.iso.sha256` | Checksum |
| `tekne-<version>-amd64.packages` | Package manifest |
| `build-info.txt` | Git commit, dirty flag, base image digest, build image, live-build version, ISO size and checksum |
| `build.log` | Full log |
| `packages/` | Tekne's `.deb`s |
| `cache/` | live-build's package cache, reused by later builds (root-owned; delete it with `sudo rm -rf out/cache` to start fresh) |

## Test

```sh
tests/smoke/live-boot.py               # live ISO on BIOS and UEFI: sysvinit, desktop processes, firewall, os-release
tests/smoke/install.py                 # unattended installs {BIOS,UEFI} x {plain,LUKS}: booted, checked, hibernated and resumed
tests/smoke/install.py uefi luks --keep   # one case, keeping the VM in out/install-test/uefi-luks
tests/smoke/upgrade.py out/install-test/uefi-luks   # upgrade a kept VM to out/packages and re-check it
scripts/test-in-qemu.sh uefi           # the newest ISO in a QEMU window (--disk, --installed)
```

They run without root and only write under `out/`. The installer runs only in
VMs: the unattended mode needs QEMU's fw_cfg, so it can't erase a real disk.
For real hardware there's the manual checklist in [testing.md](testing.md).
If the tests are much slower than usual, check the host CPU isn't stuck in a
low power state before suspecting Tekne.

## CI

`.github/workflows/build.yml` (DEC-038) runs the same `scripts/build.sh`,
`live-boot.py` and `install.py` on GitHub's runners for every push to
`master`, every pull request and every tag, except commits that only change
Markdown or license texts. A green run keeps the ISO, checksum, manifest and
build-info as the `tekne-iso` artifact for 30 days; a failed run keeps the
build and serial logs.

## Where to change things

| To change | Edit | Notes |
|---|---|---|
| The desktop's packages | `packages/tekne-desktop/debian/control` | Check the package exists in Excalibur, and build: the no-systemd check fails the build on a systemd package. Record the choice in docs/desktop-stack.md. |
| Desktop defaults (session, keybindings, bar, theme, firewall, browser policies) | `packages/tekne-config/files/` | Defaults go under `/usr/share/tekne` or `/etc`, never in home directories. |
| Identity (os-release, GRUB theme, wallpaper, logo, console palette, LUKS banner) | `packages/tekne-branding/` and `branding/` | Artwork is CC-BY-SA-4.0. Replacing an SVG with real art of the same name and size needs no other change. |
| APT repositories | `packages/tekne-apt-sources/` | Third-party repositories only under DEC-026: a key checked against `keys/SHA256SUMS`, a `.sources` file with `Signed-By`, and a pin limited to specific packages. |
| The installer | `packages/tekne-installer/files/usr/sbin/tekne-install` | Design in [installer.md](installer.md). Test with `install.py` and `scripts/test-in-qemu.sh --disk`, never on a real disk. |
| Base packages and firmware | `live-build/config/package-lists/` | |
| The live session only | `live-build/config/includes.chroot/`, `live-build/config/hooks/live/` | Nothing an installed system keeps belongs here. |
| Boot menu of the ISO | `live-build/config/bootloaders/grub-pc/` | live-build replaces any line containing its `LINUX_LIVE` placeholder, comments included. |

Every decision has an entry in DECISIONS.md. When one changes, update the
entry (with a dated History line) and every doc that refers to it, in the same
commit.

## Pinned inputs

Every external input is pinned. To update one, change it and its checksum in
one commit and note it in CHANGELOG.md.

| Input | Where |
|---|---|
| Build container base image | `container/Containerfile`: `FROM ...@sha256:...` |
| Debian live-build | `container/Containerfile`: version, SHA-256, and snapshot.debian.org SHA-1 |
| Brave and XLibre signing keys | `packages/tekne-apt-sources/keys/` and `keys/SHA256SUMS` (checked when the package builds) |
| Melia's signing key | `packages/tekne-config/files/usr/share/tekne/keyrings/melia.gpg`, and its fingerprint in `tekne-get-melia` |
| GitHub Actions | `.github/workflows/build.yml`: each `uses:` names a commit |

Packages from Devuan's mirror aren't pinned to versions: a build gets the
current ones, and the manifest records exactly which (SPEC §5.3).

## Release

Releases are published on GitHub Releases (DEC-020). Each file must be under
2 GiB; the ISO's size is in `build-info.txt`.

1. Set `VERSION` to the release (e.g. `0.1`), move CHANGELOG.md's "Unreleased"
   entries under a heading for it, and commit.
2. Tag and push: `git tag -a v0.1 -m "Tekne 0.1" && git push origin master v0.1`.
   CI builds the tag, which is a clean checkout of `v<VERSION>`, so the ISO is
   named `tekne-0.1-amd64.iso` and its packages `0.1`.
3. When that run is green, download its `tekne-iso` artifact and attach the
   ISO, `.sha256`, `.packages` and `build-info.txt` to a GitHub release for the
   tag, with the CHANGELOG entry as its notes.
4. Set `VERSION` to the next version (e.g. `0.2-rc1`) and commit, so later dev
   builds sort above the release.
