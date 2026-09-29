#!/bin/sh
# Build the satori ISO inside the pinned build container (container/Containerfile).
# live-build needs chroots and mounts, so this runs a privileged container as root:
#   sudo scripts/build.sh                   packages and ISO
#   sudo scripts/build.sh --packages-only   just satori's .debs, in out/packages/
#                                           (about a minute; for updating an
#                                           installed system, DEC-006)
# Uses podman if installed, else docker; override with CONTAINER_ENGINE=docker.
# Outputs land in out/ (SPEC.md §5.1).
set -eu

PACKAGES_ONLY=no
case "${1:-}" in
	"")              ;;
	--packages-only) PACKAGES_ONLY=yes ;;
	*)               echo "usage: $0 [--packages-only]" >&2; exit 2 ;;
esac

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
# Versions (SPEC.md §5.4, DEC-032). Debian package versions use ~ where the
# ISO name uses -, so that 0.1~rc1 < 0.1 and every dev build sorts before the
# release it leads to; the commit count makes each dev build sort higher.
DEB_BASE="$(echo "${BASE_VERSION}" | tr '-' '~')"
if [ "${GIT_DIRTY}" = no ] && git_ tag --points-at HEAD | grep -qx "v${BASE_VERSION}"; then
	VERSION="${BASE_VERSION}"
	PKG_VERSION="${DEB_BASE}"
else
	COUNT="$(git_ rev-list --count HEAD)"
	SHORT="$(git_ rev-parse --short HEAD)"
	VERSION="${BASE_VERSION}-dev${COUNT}.${SHORT}"
	PKG_VERSION="${DEB_BASE}~dev${COUNT}.g${SHORT}"
fi

# Both steps use the host's network: a bridge network needs forwarding and
# inbound DNS to the container engine's resolver, which satori's own firewall
# (DEC-023) drops. The build container needs no network isolation.
echo "==> Building container image with ${ENGINE}"
"${ENGINE}" build --network=host -t "${IMAGE}" -f "${REPO}/container/Containerfile" "${REPO}/container"
IMAGE_ID="$("${ENGINE}" image inspect --format '{{.Id}}' "${IMAGE}")"
BASE_IMAGE="$(sed -n 's/^FROM[[:space:]]*//p' "${REPO}/container/Containerfile")"

echo "==> Building satori ${VERSION}"
mkdir -p "${OUT}"
status=0
"${ENGINE}" run --rm --privileged --network=host \
	-v "${REPO}:/src:ro" \
	-v "${OUT}:/out" \
	-e SATORI_VERSION="${VERSION}" \
	-e SATORI_PKG_VERSION="${PKG_VERSION}" \
	-e SATORI_PACKAGES_ONLY="${PACKAGES_ONLY}" \
	-e SATORI_GIT_SHA="${GIT_SHA}" \
	-e SATORI_GIT_DIRTY="${GIT_DIRTY}" \
	-e SATORI_BASE_IMAGE="${BASE_IMAGE}" \
	-e SATORI_IMAGE_ID="${IMAGE_ID}" \
	"${IMAGE}" /src/scripts/build-in-container.sh || status=$?

# Hand outputs back to the invoking user so tests run without root. The
# package cache stays root-owned; only builds use it.
if [ -n "${SUDO_UID:-}" ]; then
	find "${OUT}" -maxdepth 1 -type f -exec chown "${SUDO_UID}:${SUDO_GID}" {} +
	[ -d "${OUT}/packages" ] && chown -R "${SUDO_UID}:${SUDO_GID}" "${OUT}/packages"
	chown "${SUDO_UID}:${SUDO_GID}" "${OUT}"
fi

if [ "${status}" -ne 0 ]; then
	echo "==> Build FAILED (exit ${status}); see ${OUT}/build.log" >&2
	exit "${status}"
fi
if [ "${PACKAGES_ONLY}" = yes ]; then
	echo "==> Done: packages ${PKG_VERSION} in ${OUT}/packages/"
else
	echo "==> Done: ${OUT}/satori-${VERSION}-amd64.iso"
fi
