#!/bin/sh
# Runs as root inside an installed satori system booted by tests/smoke/install.py
# (delivered through QEMU fw_cfg). Prints KEY=VALUE lines; install.py compares
# them with what the answers file asked for (docs/installer.md §6).

echo "PID1=$(cat /proc/1/comm)"
[ -d /run/systemd/system ] && echo RUN_SYSTEMD=present || echo RUN_SYSTEMD=absent
echo "SYSTEMD_PKGS=$(dpkg-query -W -f '${Package}\n' | grep -c systemd)"
echo "LIVE_PKGS=$(dpkg-query -W -f '${Package} ${db:Status-Status}\n' 'live-*' satori-installer 2>/dev/null | awk '$2 == "installed"' | wc -l)"
echo "LIVE_FILES=$(ls /usr/lib/live/config/0161-satori-autologin /usr/local/sbin/satori-serial-getty /usr/share/satori-installer 2>/dev/null | wc -l)"
echo "AUTOLOGIN=$(grep -c -- '--autologin' /etc/inittab)"

echo "ROOT_FS=$(findmnt -no FSTYPE /)"
echo "BOOT_FS=$(findmnt -no FSTYPE /boot)"
echo "EFI_FS=$(findmnt -no FSTYPE /boot/efi 2>/dev/null || echo none)"
echo "CRYPT=$(lsblk -rno TYPE | grep -c crypt)"

echo "SWAP_ACTIVE=$(swapon --show=NAME --noheadings | grep -cx /swapfile)"
echo "SWAP_GIB=$(( $(stat -c %s /swapfile) / 1073741824 ))"
echo "SWAP_OFFSET=$(filefrag -v /swapfile | awk '$1 == "0:" { sub(/\.\.$/, "", $4); print $4; exit }')"
echo "CMDLINE_OFFSET=$(sed -n 's/.*resume_offset=\([0-9]*\).*/\1/p' /proc/cmdline)"
echo "CMDLINE_RESUME=$(sed -n 's/.*resume=UUID=\([^ ]*\).*/\1/p' /proc/cmdline)"
echo "ROOT_UUID=$(findmnt -no UUID /)"

echo "HOSTNAME=$(cat /etc/hostname)"
echo "TIMEZONE=$(cat /etc/timezone)"
echo "LANG=$(sed -n 's/^LANG=//p' /etc/default/locale | tr -d '"')"
echo "KEYMAP=$(sed -n 's/^XKBLAYOUT=//p' /etc/default/keyboard | tr -d '"')"
echo "ROOT_PASSWORD=$(passwd -S root | awk '{print $2}')"
echo "USER_GROUPS=$(id -nG tester | tr ' ' ',')"
echo "FIREWALL=$(nft list chain inet satori input 2>/dev/null | grep -q 'policy drop' && echo loaded || echo missing)"
echo "GRUB_PKG=$(dpkg-query -W -f '${Package} ${db:Status-Status}\n' grub-pc grub-efi-amd64 2>/dev/null | awk '$2 == "installed" { print $1 }')"
