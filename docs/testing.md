# Testing satori

Automated tests run in QEMU and never touch the host's disks (see README):
`tests/smoke/live-boot.py`, `tests/smoke/install.py`, `tests/smoke/upgrade.py`.
This file is the manual checklist for what they can't cover: real hardware
(SPEC §5.2).

## Live-USB hardware check

Booting the live USB **doesn't touch the internal disk**: the live system runs
from the stick and RAM. Do this on any machine before installing satori on it
(it's part of the release candidate gate, SPEC §7).

### Prepare

1. Write the ISO to a USB stick. **Check the device name first** (`lsblk`); this
   overwrites the whole stick:

   ```sh
   sudo dd if=out/satori-<version>-amd64.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

2. Disable Secure Boot in the firmware setup (DEC-016); satori's boot chain
   isn't signed.
3. Boot from the stick (usually via a one-time boot menu key such as F12, F9
   or Esc) and pick "satori live". If the screen stays black, try "satori live
   (safe graphics)". The desktop starts on its own; the live user is `user`,
   password `live`.

### Checklist

Note anything that fails, with the output of `lspci -nn` and `dmesg | tail -50`.

| Area | Check |
|---|---|
| Graphics | Desktop appears at the panel's native resolution; no tearing when moving windows |
| External display | Plug in a monitor: `xrandr` lists it; `xrandr --output <name> --auto --right-of eDP-1` shows the desktop on it |
| Wi-Fi | Click the bar's network module (opens `nmtui`) → Activate a connection → join a network; Brave loads a page |
| Wired | If there's a port: plugging a cable gets an address (`ip addr`) |
| Audio | Play a video in Brave: sound from the speakers; volume keys and mute change it; headphones switch output (`pavucontrol`) |
| Microphone | `pavucontrol` → Input Devices shows the level moving when you speak |
| Brightness | Brightness keys change the panel backlight |
| Keyboard | Special keys, touchpad clicks and scrolling work |
| Bluetooth | `blueman-manager` sees nearby devices |
| Suspend | `Mod+Shift+e` → suspend, then wake with the power button or lid: the desktop comes back, Wi-Fi reconnects |
| Lock | `Mod+Escape` locks; your password (`live`) unlocks |
| Battery | The bar shows the battery; unplugging the charger changes it |

Hibernation can't be checked from the live USB (it needs the installed
system's swapfile). It's checked by `tests/smoke/install.py` in QEMU, and on
real hardware after the first install (SPEC §7, Phase 3).

### Hybrid NVIDIA laptops

On a laptop with an integrated GPU (Intel or AMD) plus an NVIDIA GPU, the
integrated one normally drives the internal panel and satori's desktop. The
kernel also loads the open `nouveau` driver for the NVIDIA GPU, which lets it
power down when idle but can cause trouble on some models. Check:

1. `lsmod | grep nouveau` shows it loaded, and `dmesg | grep -i nouveau` has no
   errors or hangs.
2. `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` (adjust the
   address from `lspci`) says `suspended` after a minute idle.
3. Suspend/resume (above) works with `nouveau` loaded.
4. If any of these fail, reboot, press `e` on the "satori" boot entry, add
   `modprobe.blacklist=nouveau` to the end of the `linux` line, press Ctrl-X,
   and repeat the checklist. If that fixes it, satori should blacklist
   `nouveau` by default; record the decision in DECISIONS.md.

## Before installing on a machine you depend on

The installer erases the whole disk (DEC-005): there's no dual-boot option.

- Push every git repository and back up your home directory, SSH and GPG
  keys, and anything else on the disk.
- Pass the live-USB check above on that machine.
- Keep the USB stick: it's also your rescue system.
