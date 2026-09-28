#!/usr/bin/env python3
"""Live boot smoke test: boot the ISO headless in QEMU and check it over serial.

    tests/smoke/live-boot.py [bios|uefi|all] [ISO]

Defaults to "all" and the newest out/satori-*-amd64.iso. For each firmware
mode it boots the ISO, presses "s" at the GRUB menu to pick the serial-console
entry, logs in as the live user, and checks SPEC.md §4 rule 1: PID 1 is
sysvinit's init and /run/systemd/system doesn't exist. Serial logs are
written to out/serial-<mode>.log. Exits non-zero if any mode fails.
"""
import glob
import os
import select
import shutil
import subprocess
import sys
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "out")
OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS = "/usr/share/OVMF/OVMF_VARS_4M.fd"
LIVE_USER, LIVE_PASSWORD = "user", "live"
SERIAL_ENTRY_TITLE = "serial console"   # GRUB entry in live-build/config/bootloaders/grub-pc/grub.cfg
SERIAL_ENTRY_HOTKEY = "s"

MENU_TIMEOUT = 60
BOOT_TIMEOUT = 300
CMD_TIMEOUT = 60

# Assembled at runtime so the echoed command line never matches the markers.
BEGIN, END = "__SATORI" + "_BEGIN__", "__SATORI" + "_END__"
CHECK_CMD = (
    'echo __SATORI""_BEGIN__; '
    'echo "PID1=$(cat /proc/1/comm)"; '
    '[ -d /run/systemd/system ] && echo RUN_SYSTEMD=present || echo RUN_SYSTEMD=absent; '
    "dpkg-query -W -f='${Package}\\n' | grep systemd | sed 's/^/PKG=/'; "
    'echo __SATORI""_END__\n'
)


class Serial:
    def __init__(self, proc, log):
        self.proc, self.log, self.buf = proc, log, ""

    def expect(self, needle, timeout):
        deadline = time.monotonic() + timeout
        while needle not in self.buf:
            if self.proc.poll() is not None:
                raise RuntimeError(f"QEMU exited while waiting for {needle!r}")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"timed out after {timeout}s waiting for {needle!r}")
            ready, _, _ = select.select([self.proc.stdout], [], [], min(remaining, 1.0))
            if ready:
                chunk = os.read(self.proc.stdout.fileno(), 4096).decode("utf-8", "replace")
                self.buf += chunk
                self.log.write(chunk)
                self.log.flush()
        before, _, self.buf = self.buf.partition(needle)
        return before

    def send(self, text):
        self.proc.stdin.write(text.encode())
        self.proc.stdin.flush()


def qemu_command(mode, iso, vars_copy):
    cmd = [
        "qemu-system-x86_64", "-m", "2048", "-smp", "2",
        "-display", "none", "-serial", "stdio", "-monitor", "none",
        "-no-reboot", "-cdrom", iso, "-boot", "d",
    ]
    if os.access("/dev/kvm", os.R_OK | os.W_OK):
        cmd += ["-enable-kvm", "-cpu", "host"]
    if mode == "uefi":
        cmd += [
            "-machine", "q35",
            "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
            "-drive", f"if=pflash,format=raw,file={vars_copy}",
        ]
    return cmd


def run(mode, iso):
    log_path = os.path.join(OUT, f"serial-{mode}.log")
    with tempfile.TemporaryDirectory() as tmp, open(log_path, "w") as log:
        vars_copy = os.path.join(tmp, "OVMF_VARS.fd")
        if mode == "uefi":
            shutil.copy(OVMF_VARS, vars_copy)
        proc = subprocess.Popen(qemu_command(mode, iso, vars_copy),
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        con = Serial(proc, log)
        started = time.monotonic()
        try:
            con.expect(SERIAL_ENTRY_TITLE, MENU_TIMEOUT)
            con.send(SERIAL_ENTRY_HOTKEY)
            con.expect("login:", BOOT_TIMEOUT)
            boot_secs = time.monotonic() - started
            con.send(LIVE_USER + "\n")
            con.expect("assword:", CMD_TIMEOUT)
            con.send(LIVE_PASSWORD + "\n")
            con.expect("$ ", CMD_TIMEOUT)
            con.send(CHECK_CMD)
            con.expect(BEGIN, CMD_TIMEOUT)
            output = con.expect(END, CMD_TIMEOUT)
            con.send("sudo poweroff\n")
            try:
                proc.wait(timeout=CMD_TIMEOUT)
            except subprocess.TimeoutExpired:
                pass
        except (TimeoutError, RuntimeError) as err:
            print(f"FAIL [{mode}]: {err}. Serial log: {log_path}")
            return False
        finally:
            if proc.poll() is None:
                proc.kill()

    lines = [line.strip() for line in output.splitlines()]
    results = dict(line.split("=", 1) for line in lines if "=" in line and not line.startswith("PKG="))
    packages = [line[4:] for line in lines if line.startswith("PKG=")]

    print(f"[{mode}] reached login prompt in {boot_secs:.0f}s")
    print(f"[{mode}] PID 1: {results.get('PID1')}")
    print(f"[{mode}] /run/systemd/system: {results.get('RUN_SYSTEMD')}")
    print(f"[{mode}] systemd-named packages: {', '.join(packages) or 'none'}")
    ok = results.get("PID1") == "init" and results.get("RUN_SYSTEMD") == "absent"
    print(f"{'PASS' if ok else 'FAIL'} [{mode}] (serial log: {log_path})")
    return ok


def main():
    args = sys.argv[1:]
    mode = args.pop(0) if args and args[0] in ("bios", "uefi", "all") else "all"
    if len(args) > 1:
        sys.exit(__doc__)
    if args:
        iso = os.path.abspath(args[0])
    else:
        isos = sorted(glob.glob(os.path.join(OUT, "satori-*-amd64.iso")), key=os.path.getmtime)
        if not isos:
            sys.exit("error: no out/satori-*-amd64.iso; run sudo scripts/build.sh first")
        iso = isos[-1]
    if not os.path.exists(iso):
        sys.exit(f"error: {iso} not found")

    print(f"Testing {iso}")
    modes = ["bios", "uefi"] if mode == "all" else [mode]
    results = [run(m, iso) for m in modes]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
