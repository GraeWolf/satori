#!/bin/sh
# Build the satori ISO inside the pinned build container (container/Containerfile).
# live-build needs chroots and mounts, so this runs a privileged container as root:
#   sudo scripts/build.sh
# Uses podman if installed, else docker; override with CONTAINER_ENGINE=docker.
# Outputs land in out/ (SPEC.md §5.1).
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${REPO}/out"
IMAGE="localhost/satori-build:latest"

[ "$(id -u)" -eq 0 ] || { echo "error: run as root: sudo $0" >&2; exit 1; }

ENGINE="${CONTAINER_ENGINE:-}"
if [ -z "${ENGINE}" ]; then
	for candidate in podman docker; do
		if command -v "${candidate}" >/dev/null 2>&1; then
			ENGINE="${candidate}"
			break
		fi
	done
fi
[ -n "${ENGINE}" ] || { echo "error: install podman (or docker) first" >&2; exit 1; }

# Root reading a user-owned checkout trips git's safe.directory check.
git_() { git -c safe.directory="${REPO}" -C "${REPO}" "$@"; }

BASE_VERSION="$(cat "${REPO}/VERSION")"
GIT_SHA="$(git_ rev-parse HEAD)"
if [ -n "$(git_ status --porcelain)" ]; then GIT_DIRTY=yes; else GIT_DIRTY=no; fi
if [ "${GIT_DIRTY}" = no ] && [ "$(git_ tag --points-at HEAD)" = "v${BASE_VERSION}" ]; then
	VERSION="${BASE_VERSION}"
else
	VERSION="${BASE_VERSION}-dev.$(git_ rev-parse --short HEAD)"
fi

echo "==> Building container image with ${ENGINE}"
"${ENGINE}" build -t "${IMAGE}" -f "${REPO}/container/Containerfile" "${REPO}/container"
IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' "${IMAGE}")"
BASE_IMAGE="$(sed -n 's/^FROM[[:space:]]*//p' "${REPO}/container/Containerfile")"

echo "==> Building satori ${VERSION}"
mkdir -p "${OUT}"
status=0
"${ENGINE}" run --rm --privileged \
	-v "${REPO}:/src:ro" \
	-v "${OUT}:/out" \
	-e SATORI_VERSION="${VERSION}" \
	-e SATORI_GIT_SHA="${GIT_SHA}" \
	-e SATORI_GIT_DIRTY="${GIT_DIRTY}" \
	-e SATORI_BASE_IMAGE="${BASE_IMAGE}" \
	-e SATORI_IMAGE_ID="${IMAGE_ID}" \
	"${IMAGE}" /src/scripts/build-in-container.sh || status=$?

# Hand outputs back to the invoking user so tests run without root. The
# package cache stays root-owned; only builds use it.
if [ -n "${SUDO_UID:-}" ]; then
	find "${OUT}" -maxdepth 1 -type f -exec chown "${SUDO_UID}:${SUDO_GID}" {} +
	chown "${SUDO_UID}:${SUDO_GID}" "${OUT}"
fi

if [ "${status}" -ne 0 ]; then
	echo "==> Build FAILED (exit ${status}); see ${OUT}/build.log" >&2
	exit "${status}"
fi
echo "==> Done: ${OUT}/satori-${VERSION}-amd64.iso"
