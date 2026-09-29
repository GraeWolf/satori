#!/usr/bin/env python3
"""Upgrade smoke test: move an installed system to newer satori packages.

    tests/smoke/upgrade.py CASE_DIR [PACKAGES_DIR]

CASE_DIR is a case kept by "tests/smoke/install.py --keep", for example
out/install-test/uefi-luks, installed from an earlier build. PACKAGES_DIR
(default out/packages) holds the current build's .debs.

This is how an installed satori gets updates (DEC-006, DEC-032):
  1. Boot the installed disk, unlock and log in over serial.
  2. Pass the new satori .debs in through QEMU fw_cfg (all but
     satori-installer, which only belongs in the live image) and install
     them with apt.
  3. Check every package moved to its new, higher version, then re-run
     installed-checks.sh and compare with install.py's expectations.
Exits non-zero on failure.
"""
import glob
import os
import subprocess
import sys

import install
from qemu_serial import OUT, Serial, qemu_command, start, stop

BEGIN, END = install.BEGIN, install.END


def deb_field(path, field):
    return subprocess.run(["dpkg-deb", "-f", path, field], capture_output=True,
                          text=True, check=True).stdout.strip()


def version_lt(a, b):
    return subprocess.run(["dpkg", "--compare-versions", a, "lt", b]).returncode == 0


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    case_dir = os.path.abspath(sys.argv[1])
    packages_dir = os.path.abspath(sys.argv[2] if len(sys.argv) == 3 else os.path.join(OUT, "packages"))
    name = os.path.basename(case_dir)
    mode, _, enc = name.partition("-")
    luks = enc == "luks"
    disk = os.path.join(case_dir, "disk.qcow2")
    vars_path = os.path.join(case_dir, "OVMF_VARS.fd") if mode == "uefi" else None
    if mode not in ("bios", "uefi") or not os.path.exists(disk):
        sys.exit(f"error: {case_dir} isn't a kept install.py case (e.g. out/install-test/uefi-luks)")

    debs = sorted(d for d in glob.glob(os.path.join(packages_dir, "satori-*.deb"))
                  if not os.path.basename(d).startswith("satori-installer_"))
    if not debs:
        sys.exit(f"error: no satori .debs in {packages_dir}")
    new = {deb_field(d, "Package"): deb_field(d, "Version") for d in debs}

    # fw_cfg names are limited to 55 characters, so the files get short names.
    cmd = qemu_command(mode, vars_path, install.MEMORY_MIB) + [
        "-boot", "c", "-drive", f"file={disk},if=virtio,format=qcow2",
        "-fw_cfg", f"name=opt/satori/check,file={install.CHECKS}",
    ]
    for i, deb in enumerate(debs):
        cmd += ["-fw_cfg", f"name=opt/satori/deb{i},file={deb}"]

    fw = "/sys/firmware/qemu_fw_cfg/by_name/opt/satori"
    pkgs = " ".join(new)
    script = (
        "modprobe qemu_fw_cfg; rm -rf /tmp/up; mkdir /tmp/up; "
        f"for d in {fw}/deb*; do cp $d/raw /tmp/up/$(basename $d).deb; done; "
        f"echo __SATORI\"\"_BEGIN__; dpkg-query -W -f \"BEFORE_\\${{Package}}=\\${{Version}}\\n\" {pkgs}; "
        "DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::=--force-confdef "
        "-o Dpkg::Options::=--force-confold /tmp/up/*.deb >/tmp/up/apt.log 2>&1 "
        "&& echo APT=ok || { echo APT=failed; tail -n 20 /tmp/up/apt.log; }; "
        f"dpkg-query -W -f \"AFTER_\\${{Package}}=\\${{Version}}\\n\" {pkgs}; "
        f"sh {fw}/check/raw; echo __SATORI\"\"_END__"
    )
    user, password = install.ANSWERS["USERNAME"], install.ANSWERS["PASSWORD"]
    log_path = os.path.join(case_dir, "serial-upgrade.log")
    with open(log_path, "w") as log:
        proc = start(cmd)
        con = Serial(proc, log)
        try:
            if luks:
                con.expect("unlock disk", install.BOOT_TIMEOUT)
                con.send(install.ANSWERS["LUKS_PASSPHRASE"] + "\n")
            con.expect("login:", install.BOOT_TIMEOUT)
            con.send(user + "\n")
            con.expect("assword:", install.CMD_TIMEOUT)
            con.send(password + "\n")
            con.expect("$ ", install.CMD_TIMEOUT)
            con.send(f"echo {password} | sudo -S -p '' sh -c '{script}'\n")
            con.expect(BEGIN, install.CMD_TIMEOUT)
            output = con.expect(END, 600)
            con.send(f"echo {password} | sudo -S -p '' poweroff\n")
            stop(proc, install.CMD_TIMEOUT)
        except (TimeoutError, RuntimeError) as err:
            print(f"FAIL [upgrade {name}]: {err}. Serial log: {log_path}")
            return 1
        finally:
            if proc.poll() is None:
                proc.kill()

    results = dict(line.strip().split("=", 1) for line in output.splitlines() if "=" in line)
    problems = []
    if results.get("APT") != "ok":
        problems.append("apt-get install of the new packages failed:\n" + output)
    for pkg, version in new.items():
        before, after = results.get(f"BEFORE_{pkg}"), results.get(f"AFTER_{pkg}")
        print(f"[upgrade {name}] {pkg}: {before} -> {after}")
        if after != version:
            problems.append(f"{pkg} is {after}, want {version}")
        elif before and not version_lt(before, after):
            problems.append(f"{pkg} didn't move to a higher version ({before} -> {after})")
    want = install.expected(mode, luks)
    want.pop("HIBERNATE")
    problems += [f"{k}: got {results.get(k)!r}, want {v!r}" for k, v in want.items() if results.get(k) != v]

    for problem in problems:
        print(f"[upgrade {name}]   {problem}")
    ok = not problems
    print(f"{'PASS' if ok else 'FAIL'} [upgrade {name}] (serial log: {log_path})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
