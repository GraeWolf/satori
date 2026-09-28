#!/bin/sh
# Boot an ISO in a QEMU window for hands-on testing.
#   scripts/test-in-qemu.sh [bios|uefi] [ISO]
# Defaults to uefi and the newest out/satori-*-amd64.iso. For the automated,
# headless check use tests/smoke/live-boot.py instead.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-uefi}"
ISO="${2:-$(ls -t "${REPO}"/out/satori-*-amd64.iso 2>/dev/null | head -n1)}"
[ -n "${ISO}" ] && [ -f "${ISO}" ] || { echo "error: no ISO found; run sudo scripts/build.sh first" >&2; exit 1; }

set -- qemu-system-x86_64 -m 4096 -smp 2 -cdrom "${ISO}" -boot d
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	set -- "$@" -enable-kvm -cpu host
fi

case "${MODE}" in
	bios) ;;
	uefi)
		VARS="$(mktemp --suffix=.fd)"
		trap 'rm -f "${VARS}"' EXIT
		cp /usr/share/OVMF/OVMF_VARS_4M.fd "${VARS}"
		set -- "$@" -machine q35 \
			-drive "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd" \
			-drive "if=pflash,format=raw,file=${VARS}"
		;;
	*) echo "usage: $0 [bios|uefi] [ISO]" >&2; exit 1 ;;
esac

echo "Booting ${ISO} (${MODE})"
"$@"
