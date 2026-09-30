#!/bin/bash
# Runs inside the build container; started by scripts/build.sh.
# /src is the repository (read-only). /out receives the outputs and keeps
# live-build's package cache between builds.
set -euo pipefail

: "${SATORI_VERSION:?}" "${SATORI_PKG_VERSION:?}" "${SATORI_GIT_SHA:?}" "${SATORI_GIT_DIRTY:?}"
: "${SATORI_BASE_IMAGE:?}" "${SATORI_IMAGE_ID:?}"
NAME="satori-${SATORI_VERSION}-amd64"
WORK=/build

rm -rf /out/packages
if [ "${SATORI_PACKAGES_ONLY:-no}" = yes ]; then
	/src/scripts/build-packages.sh /src/packages /out/packages "${SATORI_PKG_VERSION}"
	exit 0
fi
rm -f /out/satori-*-amd64.* /out/build-info.txt /out/build.log

rm -rf "${WORK}"
mkdir -p "${WORK}/cache"
cp -a /src/live-build/auto /src/live-build/config "${WORK}/"

# Only the downloaded .deb caches persist. The bootstrap stage cache stays in
# the work directory, so every build starts from a freshly bootstrapped base.
for stage in bootstrap chroot binary; do
	mkdir -p "/out/cache/packages.${stage}"
	ln -s "/out/cache/packages.${stage}" "${WORK}/cache/packages.${stage}"
done

# satori's own packages (packages/*), also copied to out/packages/ for updating
# installed systems by hand (DEC-006). live-build installs every .deb in
# config/packages.chroot/ during its package-list step, before the third-party
# repositories exist, so satori-desktop goes into the chroot as a plain file
# instead; config/hooks/normal/0500-satori-desktop.hook.chroot installs it.
/src/scripts/build-packages.sh /src/packages /out/packages "${SATORI_PKG_VERSION}" 2>&1 | tee /out/build.log
mkdir -p "${WORK}/config/packages.chroot" "${WORK}/config/includes.chroot/var/cache/satori"
for deb in /out/packages/*.deb; do
	case "$(basename "${deb}")" in
		satori-desktop_*) cp "${deb}" "${WORK}/config/includes.chroot/var/cache/satori/" ;;
		*)                cp "${deb}" "${WORK}/config/packages.chroot/" ;;
	esac
done

# The live ISO's GRUB uses satori-branding's theme, the same one installed
# systems get (DEC-034). Its background also replaces live-build's default
# splash.png, which is Debian's artwork.
mkdir -p "${WORK}/branding" "${WORK}/config/bootloaders/grub-pc/themes"
dpkg-deb -x /out/packages/satori-branding_*_all.deb "${WORK}/branding"
cp -a "${WORK}/branding/usr/share/grub/themes/satori" "${WORK}/config/bootloaders/grub-pc/themes/"
cp "${WORK}/branding/usr/share/grub/themes/satori/background.png" "${WORK}/config/bootloaders/grub-pc/splash.png"

cd "${WORK}"
lb config 2>&1 | tee -a /out/build.log
lb build 2>&1 | tee -a /out/build.log

cp live-image-amd64.packages "/out/${NAME}.packages"
echo "==> Checking the no-systemd rule (SPEC.md §4)" | tee -a /out/build.log
/src/scripts/check-no-systemd.sh "/out/${NAME}.packages" 2>&1 | tee -a /out/build.log

cp live-image-amd64.hybrid.iso "/out/${NAME}.iso"
(cd /out && sha256sum "${NAME}.iso" > "${NAME}.iso.sha256")

cat > /out/build-info.txt <<EOF
version: ${SATORI_VERSION}
package_version: ${SATORI_PKG_VERSION}
git_sha: ${SATORI_GIT_SHA}
git_dirty: ${SATORI_GIT_DIRTY}
build_date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
base_image: ${SATORI_BASE_IMAGE}
build_image_id: ${SATORI_IMAGE_ID}
live_build: $(dpkg-query -W -f '${Version}' live-build)
iso: ${NAME}.iso
iso_size_bytes: $(stat -c %s "/out/${NAME}.iso")
iso_sha256: $(cut -d' ' -f1 "/out/${NAME}.iso.sha256")
packages: $(wc -l < "/out/${NAME}.packages")
EOF
cat /out/build-info.txt
