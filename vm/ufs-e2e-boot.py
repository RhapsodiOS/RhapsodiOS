"""Gap 1 of the UFS gap tests: does a crashed machine boot multi-user
unattended?  See docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md.

usage:
  python ufs-e2e-boot.py new NAME [--dirty] [--base IMG]
        create work/ufs-gap/NAME/disk.qcow2 over the base image;
        --dirty writes fs_clean = 0 into the overlay, never the base
  python ufs-e2e-boot.py multi NAME [--port N]
        snapshot boot, unattended multi-user                  -> NAME/multi
  python ufs-e2e-boot.py fsck NAME [--port N]
        snapshot single-user boot: fsck -n                     -> NAME/fsck
  python ufs-e2e-boot.py preen NAME [--port N]
        snapshot single-user boot: fsck -p, then fsck -n       -> NAME/preen
  python ufs-e2e-boot.py crash NAME SECONDS [--port N]
        persistent single-user boot: mount -uw /, copy /usr/lib in the
        foreground, QMP quit SECONDS later                     -> NAME/crash

Only crash writes the overlay.  Every other boot is a snapshot, so each
starts from the overlay exactly as new or crash left it.  Each run's
directory holds serial.log, the screenshots, and result.txt.

A multi boot types -v at the boot prompt and y at the kernel's network
prompt, the same keystrokes a clean boot needs, and nothing else.
"""
import argparse
import os
import subprocess
import sys
import time

import make_badfs
import ufs_gap_lib as lib

NETWORK_PROMPT = "Continue without network?"
MULTIUSER_MARKER = "initPointer:"
PROMPT_WAIT = 1800      # boot, rc.boot's fsck -p and the root upgrade
MARKER_WAIT = 600
FSCK_WAIT = 600         # per fsck pass, screenshotted every 20 s


def dirty_args(overlay, offset):
    """qemu-io command writing fs_clean = 0 at offset in the overlay."""
    return ["qemu-io", "-f", "qcow2", "-c", "write -P 0 %d 1" % offset,
            os.path.abspath(overlay)]


def _overlay(name):
    return os.path.join(lib.WORK, name, "disk.qcow2")


def new(base, name, dirty):
    overlay = _overlay(name)
    lib.make_overlay(base, overlay)
    if dirty:
        offset = make_badfs.field_offset(base, "fs_clean")
        subprocess.run(dirty_args(overlay, offset), check=True)
    print("created %s%s" % (overlay, ", fs_clean = 0" if dirty else ""))


def _guest(name, run, port, persist):
    overlay = _overlay(name)
    if not os.path.exists(overlay):
        raise SystemExit("%s does not exist; run 'new %s' first"
                         % (overlay, name))
    if not lib.port_free(port):
        raise SystemExit("QMP port %d is in use" % port)
    outdir = os.path.join(lib.WORK, name, run)
    if os.path.exists(outdir):
        raise SystemExit("%s already exists; evidence is never overwritten"
                         % outdir)
    if persist:
        os.environ["RHAP_TEST_IMAGE"] = os.path.abspath(overlay)
    gc = lib.load_guest_console()
    g = gc.Guest(outdir, persist=persist, port=port,
                 image=os.path.abspath(overlay))
    return g, outdir


def multi(name, port):
    g, outdir = _guest(name, "multi", port, persist=False)
    start = time.time()

    def tick():
        g.shot("t%04d" % (time.time() - start))
    notes = []
    try:
        time.sleep(6)
        g.line("-v")
        if lib.wait_for(g.serial, NETWORK_PROMPT, PROMPT_WAIT, 15, tick):
            notes.append("network prompt after %d s" % (time.time() - start))
            g.line("y")
            seen = lib.wait_for(g.serial, MULTIUSER_MARKER, MARKER_WAIT, 15, tick)
            notes.append("%s %s after %d s" % (
                MULTIUSER_MARKER, "seen" if seen else "NOT seen",
                time.time() - start))
            time.sleep(60)
        else:
            notes.append("NO network prompt within %d s" % PROMPT_WAIT)
        g.shot("final")
    finally:
        g.close()
    lib.write_result(outdir, notes)


def fsck(name, port, preen):
    g, outdir = _guest(name, "preen" if preen else "fsck", port, persist=False)
    cmds = (["fsck -p /dev/hd0a"] if preen else []) + ["fsck -n /dev/hd0a"]
    try:
        lib.single_user(g)
        for c in cmds:
            g.line(c)
            flag = c.split()[1][1:]
            for t in range(20, FSCK_WAIT + 1, 20):
                time.sleep(20)
                g.shot("%s-%03d" % (flag, t))
    finally:
        g.close()
    lib.write_result(outdir, ["commands: " + "; ".join(cmds)])


def crash(name, seconds, port):
    g, outdir = _guest(name, "crash", port, persist=True)
    try:
        lib.single_user(g)
        g.line("mount -uw /")
        time.sleep(10)
        g.shot("rw")
        g.line("cp -R /usr/lib /private/tmp/%s" % name)
        time.sleep(seconds)
        g.shot("before-quit")
        g.cmd("quit")
        g.proc.wait(timeout=30)
    finally:
        g.close()
    lib.write_result(outdir, ["QMP quit %d s after starting the copy" % seconds])


def main(argv):
    p = argparse.ArgumentParser(
        description="UFS gap 1: an unattended boot after a crash")
    p.add_argument("command", choices=("new", "multi", "fsck", "preen", "crash"))
    p.add_argument("name")
    p.add_argument("seconds", nargs="?", type=int)
    p.add_argument("--dirty", action="store_true")
    p.add_argument("--base", default=lib.BASE)
    p.add_argument("--port", type=int, default=4492)
    a = p.parse_args(argv[1:])
    if a.command == "new":
        new(a.base, a.name, a.dirty)
    elif a.command == "multi":
        multi(a.name, a.port)
    elif a.command in ("fsck", "preen"):
        fsck(a.name, a.port, preen=(a.command == "preen"))
    else:
        if a.seconds is None:
            p.error("crash needs SECONDS")
        crash(a.name, a.seconds, a.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
