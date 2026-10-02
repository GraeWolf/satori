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
| `build-info.txt` | Git commit, dirty flag, base image digest, build image, live-build version, ISO size and checksum, and a `deb:` line with each `.deb`'s SHA-256 |
| `build.log` | Full log |
| `packages/` | Tekne's `.deb`s |
| `test-repo/` | A test APT repository of this build's packages and a decoy, signed with a throwaway key made for this build (`test-key.gpg`), plus a second throwaway key (`wrong-key.gpg`). For `repo.py` (DEC-040). |
| `cache/` | live-build's package cache, reused by later builds (root-owned; delete it with `sudo rm -rf out/cache` to start fresh) |

## Test

```sh
tests/smoke/live-boot.py               # live ISO on BIOS and UEFI: sysvinit, desktop processes, firewall, os-release
tests/smoke/repo.py                    # Tekne's APT repository: right key, wrong key, tampered .deb, pin (DEC-040)
tests/smoke/install.py                 # unattended installs {BIOS,UEFI} x {plain,LUKS}: booted, checked, hibernated and resumed
tests/smoke/install.py uefi luks --keep   # one case, keeping the VM in out/install-test/uefi-luks
tests/smoke/upgrade.py                 # install the previous release, upgrade it to this build with apt, re-check it
tests/smoke/upgrade.py out/install-test/uefi-luks   # the same upgrade, from a kept install.py case
scripts/test-in-qemu.sh uefi           # the newest ISO in a QEMU window (--disk, --installed)
```

They run without root and only write under `out/`. The installer runs only in
VMs: the unattended mode needs QEMU's fw_cfg, so it can't erase a real disk.
For real hardware there's the manual checklist in [testing.md](testing.md).
If the tests are much slower than usual, check the host CPU isn't stuck in a
low power state before suspecting Tekne.

## CI

`.github/workflows/build.yml` (DEC-038) runs the same `scripts/build.sh`,
`live-boot.py`, `repo.py` and `install.py` on GitHub's runners for every push
to `master`, every pull request and every tag, except commits that only change
Markdown or license texts. A green run keeps the ISO, checksum, manifest,
build-info and Tekne's `.deb`s as the `tekne-iso` artifact for 30 days; a
failed run keeps the build and serial logs. For a `v*` tag, a second job turns
a green run into a draft release (see "Release" below).

`.github/workflows/publish-repo.yml` (DEC-040) publishes Tekne's APT
repository when a release is published; see "Release".

## Where to change things

| To change | Edit | Notes |
|---|---|---|
| The desktop's packages | `packages/tekne-desktop/debian/control` | Check the package exists in Excalibur, and build: the no-systemd check fails the build on a systemd package. Record the choice in docs/desktop-stack.md. |
| Desktop defaults (session, keybindings, bar, theme, firewall, browser policies) | `packages/tekne-config/files/` | Defaults go under `/usr/share/tekne` or `/etc`, never in home directories. |
| Identity (os-release, GRUB theme, wallpaper, logo, console palette, LUKS banner) | `packages/tekne-branding/` and `branding/` | Artwork is CC-BY-SA-4.0. Replacing an SVG with real art of the same name and size needs no other change. |
| APT repositories | `packages/tekne-apt-sources/` | Third-party repositories only under DEC-026: a key checked against `keys/SHA256SUMS`, a `.sources` file with `Signed-By`, and a pin limited to specific packages. Tekne's own repository (DEC-040) follows the same rules; the build never fetches from it (`live-build/config/apt/apt.conf`). |
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
| Tekne's, Brave's and XLibre's signing keys | `packages/tekne-apt-sources/keys/` and `keys/SHA256SUMS` (checked when the package builds); Tekne's fingerprints are in DEC-040 |
| Melia's signing key | `packages/tekne-config/files/usr/share/tekne/keyrings/melia.gpg`, and its fingerprint in `tekne-get-melia` |
| GitHub Actions | `.github/workflows/build.yml` and `publish-repo.yml`: each `uses:` names a commit |

Packages from Devuan's mirror aren't pinned to versions: a build gets the
current ones, and the manifest records exactly which (SPEC §5.3).

## Release

Releases are published on GitHub Releases (DEC-020) and created by CI from a
tested tag (DEC-039).

1. Set `VERSION` to the release (e.g. `0.1`, or `0.1-rc2` for a release
   candidate). In CHANGELOG.md, move the "Unreleased" entries under a heading
   for it, `## 0.1 (YYYY-MM-DD)`, and commit.
2. Tag and push:

   ```sh
   git tag -a v0.1 -m "Tekne 0.1"
   git push origin master v0.1
   ```

   CI builds the tag (a clean checkout of `v<VERSION>`, so the ISO is named
   `tekne-0.1-amd64.iso` and its packages are `0.1`) and runs every test.
3. If they pass, the `release` job runs `scripts/ci-release.sh`. It checks
   that `build-info.txt` shows a clean build of exactly that version, that the
   ISO's checksum verifies, that every file is under GitHub's 2 GiB limit, and
   that CHANGELOG.md has the version's section, and that Tekne's `.deb`s match
   the checksums in `build-info.txt`. Then it creates a **draft** release with
   the ISO, `.sha256`, `.packages`, `build-info.txt` and the `.deb`s (all but
   `tekne-installer`), and the CHANGELOG section as notes. Tags with a `-` are
   marked as pre-releases.
4. Review the draft on GitHub and press "Publish".
5. Publishing starts `.github/workflows/publish-repo.yml` (DEC-040), which
   waits for your approval in the `repo-publish` environment. Once approved, it
   rebuilds Tekne's APT repository from the published releases' `.deb`s
   (checked again against their `build-info.txt`), signs it with the CI
   signing subkey, checks the signatures against `keys/tekne.gpg`, and deploys
   it to GitHub Pages: a release goes into `excalibur` and `excalibur-rc`, a
   pre-release into `excalibur-rc` only.
6. Point `tests/smoke/previous-release` at the release you just published
   (its tag, ISO name, and the ISO's SHA-256 from its `.sha256` asset), so
   CI's upgrade test starts from it (SPEC §8, Phase 9).
7. Set `VERSION` to the next version and commit, so later dev builds sort above
   the release: after a release candidate, the next candidate (`0.1-rc2` →
   `0.1-rc3`); after a final release, the next series (`0.1` → `0.2-rc1`).
   Never the final version straight after a candidate: `0.1~dev…` sorts below
   `0.1~rc2`, so systems installed from the candidate couldn't upgrade. The
   final version goes into `VERSION` only in the release commit (DEC-032).

If a check fails, nothing is released or published; the job log says which
check. To try the release checks on a local build:
`DRY_RUN=1 scripts/ci-release.sh v0.1 out`.
