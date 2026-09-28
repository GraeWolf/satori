#!/bin/bash
# Build every package under packages/ into a .deb. Runs inside the build
# container (scripts/build-in-container.sh), which has debhelper and dpkg-dev.
#   build-packages.sh SOURCE_DIR OUTPUT_DIR
set -euo pipefail

SRC="${1:?usage: $0 SOURCE_DIR OUTPUT_DIR}"
DEST="${2:?usage: $0 SOURCE_DIR OUTPUT_DIR}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

mkdir -p "${DEST}"
for dir in "${SRC}"/*/; do
	[ -f "${dir}/debian/control" ] || continue
	name="$(basename "${dir}")"
	echo "==> Building package ${name}"
	cp -a "${dir}" "${TMP}/${name}"
	# --no-check-builddeps: the check always demands build-essential (a C
	# toolchain), which these architecture-independent packages never use.
	# debhelper, their only real build dependency, is in the container.
	(cd "${TMP}/${name}" && dpkg-buildpackage --build=binary --no-sign --no-check-builddeps)
done

cp "${TMP}"/*.deb "${DEST}/"
ls -1 "${DEST}"/*.deb
