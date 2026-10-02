#!/bin/bash
# Key rotation test (DEC-040, SPEC §8 Phase 10): the signing-subkey rotation
# in docs/building.md, "Rotating the signing subkey", run with throwaway keys
# and real APT, in the order that keeps installed systems updating:
#
#   1. A system trusts the current public key (primary + subkey A), the way
#      tekne-apt-sources installs it, and CI signs with A.
#   2. The maintainer adds subkey B with the offline primary.
#   3. A tekne-apt-sources update carrying the new public key (primary, A, B)
#      is published while CI still signs with A. The system accepts it.
#   4. CI's secret becomes B. The updated system verifies the repository
#      signed with B; a system that missed step 3 can't (the control).
#
# Repositories are built with scripts/build-repo.sh and read through file:
# URIs, so no network and no root are needed. scripts/build-in-container.sh
# runs this on every build, with the build container's APT (Devuan's, like
# Tekne's). Exits non-zero on failure.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
cleanup() {
	for home in "${T}"/gnupg-*; do [ -d "${home}" ] && GNUPGHOME="${home}" gpgconf --kill gpg-agent; done
	rm -rf "${T}"
}
trap cleanup EXIT
# apt checks signatures and reads file: repositories as its _apt user.
chmod 755 "${T}"
fail() { echo "FAIL [key-rotation]: $*"; exit 1; }
step() { echo "[key-rotation] $*"; }

g() { GNUPGHOME="${T}/gnupg-$1" gpg --batch --quiet --passphrase '' "${@:2}"; }
mkdir -m 700 "${T}/gnupg-offline" "${T}/gnupg-ci-a" "${T}/gnupg-ci-b"

# 1. The primary (certify only) and subkey A; CI holds only A.
g offline --quick-gen-key 'Tekne rotation test (throwaway)' ed25519 cert 1d
FPR="$(g offline --list-keys --with-colons | awk -F: '/^fpr/ { print $10; exit }')"
g offline --quick-add-key "${FPR}" ed25519 sign 1d
subkey() { g offline --list-keys --with-colons "${FPR}" | awk -F: '/^sub/ { s = 1; next } s && /^fpr/ { print $10 }' | sed -n "$1p"; }
A="$(subkey 1)"
g offline --export-secret-subkeys "${A}!" | g ci-a --import 2>/dev/null
g offline --export "${FPR}" > "${T}/key-v1.gpg"
step "primary ${FPR}, subkey A ${A}"

# A stand-in tekne-apt-sources: just the key, where the real one puts it.
fake_apt_sources() {  # VERSION KEYFILE OUTDIR
	local dir="${T}/pkg-$1"
	mkdir -p "${dir}/DEBIAN" "${dir}/usr/share/tekne/keyrings" "$3"
	cp "$2" "${dir}/usr/share/tekne/keyrings/tekne.gpg"
	printf '%s\n' "Package: tekne-apt-sources" "Version: $1" "Architecture: all" \
		"Maintainer: Tekne project <noreply@tekne.invalid>" "Description: rotation test" > "${dir}/DEBIAN/control"
	dpkg-deb --root-owner-group -b "${dir}" "$3/tekne-apt-sources_$1_all.deb" >/dev/null
}
publish() {  # CI_HOME VERIFY_KEY OUT DEBDIR
	GNUPGHOME="${T}/gnupg-$1" TEKNE_REPO_VERIFY_KEY="$2" \
		"${REPO}/scripts/build-repo.sh" "$3" excalibur="$4" >/dev/null
	chmod -R a+rX "$3"
}

# A system: its own APT state, trusting the key file in its directory.
system() {  # NAME KEYFILE
	local s="${T}/sys-$1"
	mkdir -p "${s}/lists/partial" "${s}/cache/archives/partial" "${s}/src" "${s}/pref"
	cp "$2" "${s}/tekne.gpg"
	chmod -R a+rX "${s}"
	: > "${s}/status"
	cp "${REPO}/packages/tekne-apt-sources/preferences/tekne.pref" "${s}/pref/"
}
apt_() {  # NAME apt-get-args...
	local s="${T}/sys-$1"
	apt-get -o Dir::State::Lists="${s}/lists" -o Dir::State::status="${s}/status" \
		-o Dir::Cache="${s}/cache" -o Dir::Etc::SourceList=/dev/null -o Dir::Etc::SourceParts="${s}/src" \
		-o Dir::Etc::PreferencesParts="${s}/pref" -o Dir::Etc::Preferences=/dev/null \
		-o Debug::NoLocking=1 "${@:2}"
}
use_repo() {  # NAME REPO_DIR
	printf '%s\n' "Types: deb" "URIs: file:$2" "Suites: excalibur" "Components: main" \
		"Architectures: amd64" "Signed-By: ${T}/sys-$1/tekne.gpg" > "${T}/sys-$1/src/tekne.sources"
	rm -rf "${T}/sys-$1/lists"/* && mkdir -p "${T}/sys-$1/lists/partial"
}
updates() { apt_ "$1" update > "${T}/sys-$1/update.log" 2>&1 && ! grep -q '^[EW]: .*\(not signed\|NO_PUBKEY\|signature\)' "${T}/sys-$1/update.log"; }

fake_apt_sources 1 "${T}/key-v1.gpg" "${T}/debs1"
publish ci-a "${T}/key-v1.gpg" "${T}/repo1" "${T}/debs1"
system updated "${T}/key-v1.gpg"
system missed "${T}/key-v1.gpg"
for s in updated missed; do
	use_repo "${s}" "${T}/repo1"
	updates "${s}" || fail "a system trusting the current key can't read the current repository: $(tail -3 "${T}/sys-${s}/update.log")"
done
step "1. both systems trust the current key and read the repository signed with A"

# 2. A new signing subkey, made with the offline primary.
g offline --quick-add-key "${FPR}" ed25519 sign 1d
B="$(subkey 2)"
[ -n "${B}" ] && [ "${B}" != "${A}" ] || fail "no second subkey"
g offline --export "${FPR}" > "${T}/key-v2.gpg"
step "2. added subkey B ${B}"

# 3. The tekne-apt-sources update with the new key, still signed with A.
fake_apt_sources 2 "${T}/key-v2.gpg" "${T}/debs2"
publish ci-a "${T}/key-v1.gpg" "${T}/repo2" "${T}/debs2"
use_repo updated "${T}/repo2"
updates updated || fail "the key update, signed with A, was refused: $(tail -3 "${T}/sys-updated/update.log")"
(cd "${T}/sys-updated" && apt_ updated download tekne-apt-sources=2 >/dev/null 2>&1) \
	|| fail "couldn't download tekne-apt-sources 2"
dpkg-deb -x "${T}/sys-updated/tekne-apt-sources_2_all.deb" "${T}/sys-updated/root"
cp "${T}/sys-updated/root/usr/share/tekne/keyrings/tekne.gpg" "${T}/sys-updated/tekne.gpg"
cmp -s "${T}/sys-updated/tekne.gpg" "${T}/key-v2.gpg" || fail "the installed key isn't the new one"
step "3. the updated system accepted tekne-apt-sources 2 (signed with A) and now trusts A and B"

# 4. CI switches to B: only B's secret, as in the CI secret.
g offline --export-secret-subkeys "${B}!" | g ci-b --import 2>/dev/null
publish ci-b "${T}/key-v2.gpg" "${T}/repo3" "${T}/debs2"
gpgv --keyring "${T}/key-v1.gpg" "${T}/repo3/dists/excalibur/InRelease" 2>/dev/null \
	&& fail "the repository after the switch is still signed with A"
use_repo updated "${T}/repo3"
updates updated || fail "the updated system can't read the repository signed with B: $(tail -3 "${T}/sys-updated/update.log")"
step "4. CI signs with B; the updated system reads the repository"
use_repo missed "${T}/repo3"
updates missed && fail "a system without the key update read a repository signed with B"
grep -q 'not signed\|NO_PUBKEY' "${T}/sys-missed/update.log" || fail "the control failed for another reason: $(tail -3 "${T}/sys-missed/update.log")"
step "   control: a system that missed step 3 can't verify it (as expected), so step 3 must come first"
echo "PASS [key-rotation]"
