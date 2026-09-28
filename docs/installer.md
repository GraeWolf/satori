# satori-installer

A gum-based TUI that installs the running live system to a single whole disk,
with optional LUKS2 encryption, on BIOS or UEFI machines. Scope is fixed by DEC-005.

## 1. Approach

The installer **copies the live root filesystem** (the mounted squashfs) to the
target, then removes live-only packages and configures the target system. This is
the same model Devuan's `refractainstaller` uses. It needs no network during
install, and the installed system matches exactly what the user tested live.

Implementation: a bash script (`/usr/sbin/satori-install`) using `gum` for all
prompts, running as root from the live session. Before writing custom logic,
study refractainstaller and reuse its approach where it fits.

## 2. Flow

1. **Preflight**
   - The script must run as root in the live session. Otherwise it exits.
   - It detects the firmware mode (`/sys/firmware/efi` means UEFI, otherwise BIOS) and shows it. Installing in the other mode isn't supported.
   - It lists candidate disks (`lsblk`), excluding the live medium, read-only devices, and disks smaller than 20 GiB plus the swapfile size (installed RAM, rounded up to the next GiB).
2. **Target disk.** The user picks a disk with `gum choose`, which shows model, size, and existing partitions.
3. **Encryption.** "Encrypt the disk?" (`gum confirm`). If yes, the user enters a passphrase twice (`gum input --password`), with a minimum length and a match check.
4. **System settings**
   - Hostname (default `satori`)
   - Timezone (a filtered list from `/usr/share/zoneinfo`)
   - Locale (a curated short list, with an option to type one)
   - Keyboard layout (defaults to the live session's layout)
5. **User.** Full name, username (validated), and password twice. The user joins `sudo`, `audio`, `video`, `netdev`, `plugdev`, and `bluetooth`. The root account is locked.
6. **Summary and confirmation.** Show every choice. The user has to type the disk name (for example `nvme0n1`) to proceed. Anything else aborts, and nothing has been written yet.
7. **Partition**, from a fixed layout (§3).
8. **Encrypt and format.** Run `cryptsetup luksFormat --type luks2` if encryption was chosen, then `mkfs.vfat` for the ESP and `mkfs.ext4` for the other partitions.
9. **Copy** the live root to the target with `rsync -aHAX` (excluding `/proc`, `/sys`, `/dev`, `/run`, `/tmp`, `/media`, and live-only paths), and show progress.
10. **Configure the target** in a chroot:
    - `fstab` and `crypttab` by UUID
    - Hostname, `/etc/hosts`, timezone, locale, and keyboard (`/etc/default/keyboard`)
    - Create the user, lock root
    - Purge `live-boot`, `live-config*`, and `satori-installer`, and undo live-only overlays
    - Create the swapfile (DEC-017): `/swapfile`, size = RAM rounded up to the next GiB, mode 0600, created with `mkswap --file` so it has no holes
    - Configure resume: write `RESUME=UUID=<root fs UUID>` and `RESUME_OFFSET=<offset>` (the first physical extent from `filefrag -v /swapfile`) to `/etc/initramfs-tools/conf.d/resume`
    - For LUKS, `cryptsetup-initramfs` is installed
    - Run `update-initramfs -u -k all` (after the resume config, so the initramfs includes it)
    - Install the bootloader: `grub-install` (`grub-efi-amd64` with `--removable` as well as an NVRAM entry, or `grub-pc`), then `update-grub`
11. **Finish.** Unmount, close LUKS, copy the install log to the target's `/var/log/satori-installer.log`, and offer to reboot.

## 3. Partition layouts (GPT in both modes)

| # | UEFI | BIOS | Size | FS |
|---|---|---|---|---|
| 1 | ESP | BIOS boot (`bios_grub`) | 512 MiB / 1 MiB | vfat / none |
| 2 | `/boot` | `/boot` | 1 GiB | ext4 |
| 3 | `/` (LUKS2 if encrypted) | `/` (LUKS2 if encrypted) | rest | ext4 |

`/boot` is a separate, unencrypted partition in both modes. This keeps GRUB simple,
because GRUB's LUKS2 support is limited, and only one passphrase prompt (in the
initramfs) is needed.

## 4. Error handling

- `set -Eeuo pipefail` plus an `ERR`/`EXIT` trap. The trap unmounts everything under the target mountpoint, closes the LUKS mapping, and prints the log path.
- There's no rollback: once step 7 starts, the disk has been wiped. Each run starts from scratch, so a failed install is fixed by re-running the installer.
- Every command and its output goes to `/var/log/satori-installer.log`, which never contains passphrases or passwords.
- Passwords are passed to `cryptsetup` and `chpasswd` on stdin, never as command-line arguments.

## 5. UX rules

- Every screen shows the step number (for example "Step 3/6"), and `Esc` goes back until the confirmation step.
- No destructive action happens before step 6.
- Messages are short and technical. No wizard fluff.

## 6. Unattended mode (for tests)

`satori-install --answers <file>` reads a shell-style answers file
(`DISK=`, `ENCRYPT=`, `LUKS_PASSPHRASE=`, `HOSTNAME=`, `TZ=`, `LOCALE=`, `KEYMAP=`,
`USERNAME=`, `PASSWORD=`, `CONFIRM_DISK=`). It skips all prompts, then reboots or
powers off when done.

For automated tests, the live ISO has a boot entry that adds `satori.autoinstall` to the
existing "serial console" test entry (SPEC §5.2), which already provides `console=ttyS0`.
With that parameter, the live system looks
for an answers file on a small disk labelled `SATORI-TEST` and runs the installer
unattended. The test harness in `tests/smoke/` builds that disk, runs the
{BIOS, UEFI} × {plain, LUKS} matrix, and then boots each installed disk to check:
- A login prompt appears (for LUKS runs, after the passphrase is sent over serial).
- The no-systemd runtime check passes.
- The user can `sudo`.
- `lsblk` shows the expected layout.
- `/etc/initramfs-tools/conf.d/resume` matches the swapfile's current offset. Hibernate/resume itself is verified manually on real hardware (SPEC §7, Phase 3).
- No live-* packages remain.

This entry only works with the test disk present. Without it, `satori.autoinstall` does nothing.
