"""Shared pieces of the UFS gap tests (ufs-e2e-boot.py and
ufs-reload-inject.py): where their files live, qcow2 overlays, waiting on the
kernel's serial log, and each run's result.txt.  See
docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md."""
import importlib.util
import os
import socket
import subprocess
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work", "ufs-gap")
BASE = os.path.join(HERE, "work", "ufs-e2e.img")
SHELL_WAIT = 135    # seconds from "-s" to a single-user shell, as in the P0 harness


def load_guest_console():
    spec = importlib.util.spec_from_file_location(
        "guest_console", os.path.join(HERE, "guest-console.py"))
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    return gc


def port_free(port):
    """True if nothing is listening on 127.0.0.1:port."""
    s = socket.socket()
    try:
        s.settimeout(1)
        return s.connect_ex(("127.0.0.1", port)) != 0
    finally:
        s.close()


def overlay_args(base, overlay):
    return ["qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw",
            "-b", os.path.abspath(base), os.path.abspath(overlay)]


def make_overlay(base, overlay):
    """A fresh qcow2 overlay backed by the raw base; never reuses one."""
    if os.path.exists(overlay):
        raise SystemExit("%s already exists; each run starts from a fresh "
                         "overlay" % overlay)
    os.makedirs(os.path.dirname(overlay), exist_ok=True)
    subprocess.run(overlay_args(base, overlay), check=True)


def wait_for(path, text, timeout, tick=15, on_tick=None):
    """Poll path until it contains text, calling on_tick() after each tick
    seconds of waiting.  True if text appeared, False on timeout."""
    deadline = time.time() + timeout
    while True:
        if os.path.exists(path):
            with open(path, "r", errors="replace") as f:
                if text in f.read():
                    return True
        if time.time() >= deadline:
            return False
        time.sleep(tick)
        if on_tick:
            on_tick()


def ffs_lines(serial_path):
    """The kernel's 'ffs: ' lines, in order."""
    if not os.path.exists(serial_path):
        return []
    with open(serial_path, "r", errors="replace") as f:
        return [s for s in (l.strip("\r\n") for l in f)
                if s.startswith("ffs: ")]


def write_result(outdir, notes):
    """Write and print outdir/result.txt: the notes, then every ffs: line."""
    lines = list(notes) + ["ffs: lines:"] + [
        "  " + l for l in ffs_lines(os.path.join(outdir, "serial.log"))]
    with open(os.path.join(outdir, "result.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))


def single_user(g):
    """Boot a Guest to its single-user shell and screenshot it."""
    time.sleep(6)
    g.line("-s")
    time.sleep(SHELL_WAIT)
    g.shot("shell")
