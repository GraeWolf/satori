#!/bin/bash
# Publish Tekne's APT repository from published GitHub releases (DEC-040).
# Run by .github/workflows/publish-repo.yml when a person publishes a release,
# in two steps:
#
#   ci-publish-repo.sh fetch WORK   on the runner: pick the releases, download
#                                   their .debs and check them
#   ci-publish-repo.sh build WORK   in the build container: build and sign
#                                   WORK/site/apt with scripts/build-repo.sh
#
# fetch needs gh with GH_TOKEN and GH_REPO. Of the published (not draft)
# releases that carry Tekne's .debs, the newest release goes into the
# "excalibur" suite and the newest release or pre-release into "excalibur-rc".
# Releases from before DEC-040 have no .debs and are skipped; a suite with no
# release is published empty. Each .deb must match the SHA-256 in that
# release's build-info.txt, which CI wrote when it built and tested it, and
# have that build's package version. With a releases JSON file in
# RELEASES_JSON, fetch uses it instead of asking GitHub, and with DRY_RUN=1 it
# stops before downloading (for testing the selection locally).
#
# build needs TEKNE_REPO_SIGNING_KEY (the armored signing subkey) and, if it
# has one, TEKNE_REPO_SIGNING_PASSPHRASE. The signatures must verify against
# packages/tekne-apt-sources/keys/tekne.gpg, the key installed systems trust,
# or nothing is published.
set -euo pipefail

die() { echo "ci-publish-repo: $*" >&2; exit 1; }
MODE="${1:?usage: $0 fetch|build WORK}"
WORK="${2:?usage: $0 fetch|build WORK}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGES="tekne-apt-sources tekne-branding tekne-config tekne-desktop"

fetch() {
	mkdir -p "${WORK}"
	local releases="${WORK}/releases.json"
	if [ -n "${RELEASES_JSON:-}" ]; then
		cp "${RELEASES_JSON}" "${releases}"
	else
		: "${GH_REPO:?}"
		gh api --paginate "repos/${GH_REPO}/releases" --jq '.[]' > "${releases}"
	fi

	# One line per usable release: "TAG PRERELEASE(true/false)", newest first
	# by Debian version order (DEC-032), so 0.2 sorts above 0.2~rc3.
	local candidates
	candidates="$(python3 - "${releases}" "${PACKAGES}" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
wanted = sys.argv[2].split()
# gh --paginate --jq '.[]' prints one JSON object per line; a test file may
# instead hold a JSON array.
items = json.loads(text) if text.lstrip().startswith("[") else [json.loads(l) for l in text.splitlines() if l.strip()]
for r in items:
    if r.get("draft"):
        continue
    names = {a["name"] for a in r.get("assets", [])}
    if "build-info.txt" not in names or not all(any(n.startswith(p + "_") and n.endswith(".deb") for n in names) for p in wanted):
        print(f"skip {r['tag_name']}: no Tekne .debs (published before DEC-040)", file=sys.stderr)
        continue
    print(r["tag_name"], "true" if r.get("prerelease") else "false")
PY
)"
	local best_rc="" best_rel="" tag pre v
	while read -r tag pre; do
		[ -n "${tag}" ] || continue
		v="$(echo "${tag#v}" | tr '-' '~')"
		if [ -z "${best_rc}" ] || dpkg --compare-versions "${v}" gt "$(echo "${best_rc#v}" | tr '-' '~')"; then
			best_rc="${tag}"
		fi
		if [ "${pre}" = false ] && { [ -z "${best_rel}" ] || dpkg --compare-versions "${v}" gt "$(echo "${best_rel#v}" | tr '-' '~')"; }; then
			best_rel="${tag}"
		fi
	done <<< "${candidates}"
	echo "ci-publish-repo: excalibur <- ${best_rel:-(empty)}; excalibur-rc <- ${best_rc:-(empty)}"
	echo "excalibur ${best_rel:--}" > "${WORK}/suites"
	echo "excalibur-rc ${best_rc:--}" >> "${WORK}/suites"
	[ "${DRY_RUN:-0}" = 1 ] && return 0

	local suite
	while read -r suite tag; do
		mkdir -p "${WORK}/${suite}"
		[ "${tag}" != - ] || continue
		# Both suites may take the same release; it's downloaded once, and
		# checked every time.
		local dl="${WORK}/download/${tag}"
		if [ ! -d "${dl}" ]; then
			mkdir -p "${dl}"
			gh release download "${tag}" --dir "${dl}" --pattern 'build-info.txt' --pattern 'tekne-*.deb'
		fi
		check_release "${tag}" "${dl}"
		local p
		for p in ${PACKAGES}; do cp "${dl}/${p}_"*.deb "${WORK}/${suite}/"; done
	done < "${WORK}/suites"
}

# The release's .debs are the ones its tested build made: same checksums and
# version as its build-info.txt, from a clean build of the tag (DEC-039).
check_release() {
	local tag="$1" dir="$2" info="$2/build-info.txt"
	field() { sed -n "s/^$1: //p" "${info}"; }
	[ -f "${info}" ] || die "${tag}: no build-info.txt"
	[ "$(field version)" = "${tag#v}" ] || die "${tag}: build-info.txt says version $(field version)"
	[ "$(field git_dirty)" = no ] || die "${tag}: build-info.txt says the tree was dirty"
	local pkgver p deb want got
	pkgver="$(field package_version)"
	for p in ${PACKAGES}; do
		deb="${dir}/${p}_${pkgver}_all.deb"
		[ -f "${deb}" ] || die "${tag}: $(basename "${deb}") missing"
		want="$(field deb | awk -v f="$(basename "${deb}")" '$1 == f { print $2 }')"
		got="$(sha256sum < "${deb}" | cut -d' ' -f1)"
		[ -n "${want}" ] || die "${tag}: build-info.txt has no checksum for $(basename "${deb}")"
		[ "${got}" = "${want}" ] || die "${tag}: $(basename "${deb}") doesn't match build-info.txt"
		[ "$(dpkg-deb -f "${deb}" Version)" = "${pkgver}" ] || die "${tag}: $(basename "${deb}") isn't version ${pkgver}"
	done
	echo "ci-publish-repo: ${tag}: $(echo ${PACKAGES} | wc -w) packages match build-info.txt"
}

build() {
	: "${TEKNE_REPO_SIGNING_KEY:?}"
	[ -f "${WORK}/suites" ] || die "run fetch first"
	export GNUPGHOME
	GNUPGHOME="$(mktemp -d)"
	trap 'gpgconf --kill gpg-agent 2>/dev/null || true; rm -rf "${GNUPGHOME}"' EXIT
	printf '%s\n' "${TEKNE_REPO_SIGNING_KEY}" | gpg --batch --quiet --import
	local args=() suite tag
	while read -r suite tag; do args+=("${suite}=${WORK}/${suite}"); done < "${WORK}/suites"
	TEKNE_REPO_VERIFY_KEY="${REPO}/packages/tekne-apt-sources/keys/tekne.gpg" \
		"${REPO}/scripts/build-repo.sh" "${WORK}/site/apt" "${args[@]}"
	# The public key, for anyone checking the repository by hand.
	cp "${REPO}/packages/tekne-apt-sources/keys/tekne.gpg" "${WORK}/site/apt/tekne.gpg"
}

case "${MODE}" in
	fetch) fetch ;;
	build) build ;;
	*) die "unknown mode ${MODE}" ;;
esac
