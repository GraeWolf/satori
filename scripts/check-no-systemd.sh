#!/bin/sh
# Rules 2 and 3 of the no-systemd rule (SPEC.md §4), checked against a
# live-build package manifest (lines of "package<TAB>version").
#   scripts/check-no-systemd.sh out/tekne-<version>-amd64.packages
set -eu

MANIFEST="${1:?usage: $0 MANIFEST}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWLIST="${REPO}/tests/systemd-allowlist.txt"

FORBIDDEN="systemd systemd-sysv systemd-timesyncd systemd-resolved systemd-boot libpam-systemd"

packages="$(cut -f1 "${MANIFEST}" | sed 's/:.*//' | sort -u)"
allowed="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "${ALLOWLIST}" | grep -v '^$' || true)"
fail=0

for pkg in ${FORBIDDEN}; do
	if echo "${packages}" | grep -qx "${pkg}"; then
		echo "FAIL rule 2: forbidden package installed: ${pkg}"
		fail=1
	fi
done

for pkg in $(echo "${packages}" | grep systemd || true); do
	if ! echo "${allowed}" | grep -qx "${pkg}"; then
		echo "FAIL rule 3: '${pkg}' contains 'systemd' and is not in tests/systemd-allowlist.txt"
		fail=1
	fi
done

if [ "${fail}" -eq 0 ]; then
	echo "PASS: no forbidden packages; every systemd-named package is allowlisted"
fi
exit "${fail}"
