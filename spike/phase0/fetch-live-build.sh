#!/bin/sh
# Download Debian's live-build source (pinned by version and SHA-256) and unpack
# it into .cache/, where build.sh runs it via LIVE_BUILD without installing it.
#
# Devuan's own live-build package (4.0.3+devuan2, from 2016) has no UEFI
# support, so the spike uses Debian trixie's current release instead.
set -eu

VERSION="20250505+deb13u1"
TARBALL="live-build_${VERSION}.tar.xz"
SHA256="1aad324e433d6cb6d038193252b74fd0ed1c1e1d7e1c6cf410c8fb09c5225b9e"
URLS="https://deb.debian.org/debian/pool/main/l/live-build/${TARBALL}
https://snapshot.debian.org/archive/debian/20250901T000000Z/pool/main/l/live-build/${TARBALL}"

HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${HERE}/.cache"
mkdir -p "${CACHE}"
cd "${CACHE}"

if [ ! -f "${TARBALL}" ]; then
	for url in ${URLS}; do
		echo "Downloading ${url}"
		if curl -fsSL -o "${TARBALL}.part" "${url}"; then
			mv "${TARBALL}.part" "${TARBALL}"
			break
		fi
	done
fi
[ -f "${TARBALL}" ] || { echo "error: could not download ${TARBALL}" >&2; exit 1; }

echo "${SHA256}  ${TARBALL}" | sha256sum -c -

rm -rf live-build
# The host may lack xz-utils; Python's tarfile handles .tar.xz on its own.
python3 -c "import sys, tarfile; tarfile.open(sys.argv[1]).extractall(filter='tar')" "${TARBALL}"
echo "${VERSION}" > live-build/.satori-version

# Run from source, live-build reads its own version with dpkg-parsechangelog
# (from dpkg-dev). A shim avoids installing dpkg-dev just for that.
mkdir -p bin
printf '#!/bin/sh\necho "1:%s"\n' "${VERSION}" > bin/dpkg-parsechangelog
chmod +x bin/dpkg-parsechangelog
echo "live-build ${VERSION} ready in ${CACHE}/live-build"
