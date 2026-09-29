#!/bin/sh
# Boot satori in a QEMU window for hands-on testing.
#   scripts/test-in-qemu.sh [bios|uefi] [--disk] [--installed] [ISO]
#
#   (default)     boot the newest out/satori-*-amd64.iso, no disk
#   --disk        also attach a virtual disk (out/qemu-test/disk-<mode>.qcow2,
#                 created blank if missing) to try the installer on:
#                 run "sudo satori-install" in the live session
#   --installed   boot that virtual disk instead of the ISO
#
# Defaults to uefi. Everything stays inside the VM: only the qcow2 file on the
# host is ever written. Delete out/qemu-test/ to start again from a blank disk.
# For the automated, headless checks use tests/smoke/live-boot.py and
# tests/smoke/install.py instead.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODE=uefi
DISK=no
INSTALLED=no
ISO=""
for arg in "$@"; do
	case "${arg}" in
		bios|uefi)   MODE="${arg}" ;;
		--disk)      DISK=yes ;;
		--installed) DISK=yes; INSTALLED=yes ;;
		-*)          echo "usage: $0 [bios|uefi] [--disk] [--installed] [ISO]" >&2; exit 2 ;;
		*)           ISO="${arg}" ;;
	esac
done

WORK="${REPO}/out/qemu-test"
DISK_FILE="${WORK}/disk-${MODE}.qcow2"
VARS="${WORK}/OVMF_VARS-${MODE}.fd"
mkdir -p "${WORK}"

# 4 GiB of RAM means a 4 GiB swapfile, so the installer needs 24 GiB.
set -- qemu-system-x86_64 -m 4096 -smp 2 -device virtio-vga
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	set -- "$@" -enable-kvm -cpu host
fi

if [ "${MODE}" = uefi ]; then
	# Keep the UEFI variables with the disk, so an installed system's boot
	# entry survives between runs.
	[ -f "${VARS}" ] || cp /usr/share/OVMF/OVMF_VARS_4M.fd "${VARS}"
	set -- "$@" -machine q35 \
		-drive "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd" \
		-drive "if=pflash,format=raw,file=${VARS}"
fi

if [ "${DISK}" = yes ]; then
	if [ ! -f "${DISK_FILE}" ]; then
		[ "${INSTALLED}" = no ] || { echo "error: ${DISK_FILE} doesn't exist; install to it first with --disk" >&2; exit 1; }
		qemu-img create -q -f qcow2 "${DISK_FILE}" 32G
		echo "Created blank virtual disk ${DISK_FILE}"
	fi
	set -- "$@" -drive "file=${DISK_FILE},if=virtio,format=qcow2"
fi

if [ "${INSTALLED}" = yes ]; then
	echo "Booting the installed virtual disk (${MODE})"
	set -- "$@" -boot c
else
	[ -n "${ISO}" ] || ISO="$(ls -t "${REPO}"/out/satori-*-amd64.iso 2>/dev/null | head -n1)"
	[ -n "${ISO}" ] && [ -f "${ISO}" ] || { echo "error: no ISO found; run sudo scripts/build.sh first" >&2; exit 1; }
	echo "Booting ${ISO} (${MODE})"
	set -- "$@" -cdrom "${ISO}" -boot d
fi

"$@"
