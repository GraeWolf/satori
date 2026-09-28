#!/bin/sh
# Phase 0 spike build. Must run as root (live-build needs chroots and mounts):
#   sudo spike/phase0/build.sh
# Output: out/phase0/satori-phase0-amd64.{iso,packages} and build.log
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
LB_SRC="${HERE}/.cache/live-build"
WORK="${REPO}/out/phase0/work"
OUT="${REPO}/out/phase0"

[ "$(id -u)" -eq 0 ] || { echo "error: run as root (sudo $0)" >&2; exit 1; }

missing=""
for cmd in debootstrap cpio curl python3; do
	command -v "${cmd}" >/dev/null 2>&1 || missing="${missing} ${cmd}"
done
[ -z "${missing}" ] || { echo "error: missing host tools:${missing}" >&2; exit 1; }
[ -e /usr/share/debootstrap/scripts/excalibur ] || { echo "error: debootstrap has no excalibur script" >&2; exit 1; }

if [ ! -x "${LB_SRC}/frontend/lb" ] || [ ! -x "${HERE}/.cache/bin/dpkg-parsechangelog" ]; then
	"${HERE}/fetch-live-build.sh"
fi

export LIVE_BUILD="${LB_SRC}"
export PATH="${LB_SRC}/frontend:${HERE}/.cache/bin:${PATH}"

# Build in a scratch copy so live-build's chroot/, binary/ and cache/ never land in git.
if [ -d "${WORK}" ]; then
	(cd "${WORK}" && lb clean --purge >/dev/null 2>&1 || true)
fi
rm -rf "${WORK}"
mkdir -p "${WORK}"
cp -a "${HERE}/auto" "${HERE}/config" "${WORK}/"
chmod +x "${WORK}"/auto/* "${WORK}"/config/hooks/live/*

cd "${WORK}"
lb config
lb build

cp live-image-amd64.hybrid.iso "${OUT}/satori-phase0-amd64.iso"
cp live-image-amd64.packages "${OUT}/satori-phase0-amd64.packages"
cp build.log "${OUT}/build.log"
(cd "${OUT}" && sha256sum satori-phase0-amd64.iso > satori-phase0-amd64.iso.sha256)

# Hand the outputs back to the invoking user so tests can run without root.
if [ -n "${SUDO_UID:-}" ]; then
	chown "${SUDO_UID}:${SUDO_GID}" "${REPO}/out" "${OUT}" "${OUT}"/satori-phase0-* "${OUT}/build.log"
fi

echo "Done: ${OUT}/satori-phase0-amd64.iso"
