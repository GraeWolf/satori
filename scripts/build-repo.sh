#!/bin/bash
# Build Tekne's signed APT repository (DEC-040) from directories of .debs.
#   build-repo.sh OUT_DIR SUITE=DEB_DIR [SUITE=DEB_DIR ...]
#
# Writes OUT_DIR/pool/main/*.deb (shared by every suite) and, per suite,
# OUT_DIR/dists/SUITE/{InRelease,Release,Release.gpg} and
# main/binary-amd64/Packages{,.gz}. Tekne is amd64-only (DEC-009), so its
# architecture-independent packages are listed under binary-amd64.
#
# Signs with the secret key in GNUPGHOME (with only a signing subkey there, as
# in CI, gpg uses that subkey). Environment:
#   GNUPGHOME                       required: the keyring to sign with
#   TEKNE_REPO_SIGNING_PASSPHRASE   the key's passphrase, if it has one
#   TEKNE_REPO_VERIFY_KEY           a public key file; every signed Release
#                                   must verify against it, or the script
#                                   fails (CI passes keys/tekne.gpg, so a
#                                   wrong secret can never be published)
#
# Used by scripts/build-in-container.sh (a test repository signed with a
# throwaway key) and by CI's publishing job (the real key), inside the build
# container, so both build the same layout with the same tools.
set -euo pipefail

die() { echo "build-repo: $*" >&2; exit 1; }
USAGE="usage: $0 OUT_DIR SUITE=DEB_DIR [SUITE=DEB_DIR ...]"
OUT="${1:?${USAGE}}"
shift
[ $# -gt 0 ] || die "${USAGE}"
: "${GNUPGHOME:?GNUPGHOME must point at the signing keyring}"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

rm -rf "${OUT}"
mkdir -p "${OUT}/pool/main"

for arg in "$@"; do
	suite="${arg%%=*}"
	dir="${arg#*=}"
	[[ "${suite}" =~ ^[a-z][a-z0-9-]*$ ]] || die "bad suite name '${suite}'"
	[ -d "${dir}" ] || die "${dir} isn't a directory"

	# Every suite shares the pool; a file name must always mean the same file.
	mkdir -p "${TMP}/${suite}/pool/main"
	for deb in "${dir}"/*.deb; do
		[ -e "${deb}" ] || continue
		name="$(basename "${deb}")"
		if [ -e "${OUT}/pool/main/${name}" ]; then
			cmp -s "${deb}" "${OUT}/pool/main/${name}" \
				|| die "two different files are both called ${name}"
		else
			cp "${deb}" "${OUT}/pool/main/${name}"
		fi
		# A copy, not a link: TMP and OUT_DIR may be on different filesystems
		# (in the build container, /tmp and the /out bind mount are).
		cp "${OUT}/pool/main/${name}" "${TMP}/${suite}/pool/main/${name}"
	done

	# Paths in Packages are relative to OUT_DIR ("pool/main/..."), so it's
	# generated from a copy of the pool holding only this suite's files.
	dists="${OUT}/dists/${suite}"
	mkdir -p "${dists}/main/binary-amd64"
	(cd "${TMP}/${suite}" && apt-ftparchive packages pool/main) > "${dists}/main/binary-amd64/Packages"
	gzip -9n < "${dists}/main/binary-amd64/Packages" > "${dists}/main/binary-amd64/Packages.gz"

	# Origin and Label are what tekne-apt-sources' pin matches (o=Tekne), so
	# the pin works whatever URL the repository is served from.
	(cd "${dists}" && apt-ftparchive \
		-o APT::FTPArchive::Release::Origin=Tekne \
		-o APT::FTPArchive::Release::Label=Tekne \
		-o APT::FTPArchive::Release::Suite="${suite}" \
		-o APT::FTPArchive::Release::Codename="${suite}" \
		-o APT::FTPArchive::Release::Architectures=amd64 \
		-o APT::FTPArchive::Release::Components=main \
		-o "APT::FTPArchive::Release::Description=Tekne's own packages (DEC-040)" \
		release .) > "${TMP}/Release"
	mv "${TMP}/Release" "${dists}/Release"

	sign() {
		if [ -n "${TEKNE_REPO_SIGNING_PASSPHRASE:-}" ]; then
			printf '%s' "${TEKNE_REPO_SIGNING_PASSPHRASE}" | gpg --batch --yes --pinentry-mode loopback \
				--passphrase-fd 0 --digest-algo SHA512 "$@"
		else
			gpg --batch --yes --digest-algo SHA512 "$@"
		fi
	}
	sign --clearsign --output "${dists}/InRelease" "${dists}/Release"
	sign --armor --detach-sign --output "${dists}/Release.gpg" "${dists}/Release"

	if [ -n "${TEKNE_REPO_VERIFY_KEY:-}" ]; then
		gpgv --keyring "${TEKNE_REPO_VERIFY_KEY}" "${dists}/InRelease" 2>/dev/null \
			|| die "${suite}/InRelease doesn't verify against ${TEKNE_REPO_VERIFY_KEY}"
		gpgv --keyring "${TEKNE_REPO_VERIFY_KEY}" "${dists}/Release.gpg" "${dists}/Release" 2>/dev/null \
			|| die "${suite}/Release.gpg doesn't verify against ${TEKNE_REPO_VERIFY_KEY}"
	fi
	echo "build-repo: ${suite}: $(grep -c '^Package:' "${dists}/main/binary-amd64/Packages") packages"
done
