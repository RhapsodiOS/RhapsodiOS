"""FFS stall, hard-lock and corruption harness for a private i386 guest.

See docs/superpowers/specs/2026-10-05-ffs-stall-corruption-design.md and
docs/superpowers/plans/2026-10-05-ffs-stall-corruption.md.

The guest boots vm/work/rhap-i386-bootstrapped.img with only the root drive
under snapshot; hd1 (the disk under test) and hd2 (the workload) persist.
"""

import collections
import importlib
import math
import os
import re

QEMU = r"C:\Program Files\qemu\qemu-system-i386.exe"
GUEST_IP = "10.10.0.240"

ProbeSample = collections.namedtuple("ProbeSample", "t late_ms free pageouts")

# rhap_image.LABEL_OFFSETS: the four copies of the NeXT disk label.
LABEL_OFFSETS = (7680, 15360, 23040, 30720)

# Every marker tests/ffsbench/run.sh prints, in order.
RUN_MARKERS = ("PROBE-BUILT", "REPLAY-START", "REPLAY-END", "RM-END",
               "SLOW1", "SLOW2", "RUN-END")

CSV_HEADER = ("label,replay_s,rm_s,slow1_mbs,slow2_mbs,"
              "late_max_ms,late_p99_ms,banner_max_s,banner_missed")
CSV_FIELDS = CSV_HEADER.split(",")[1:]

# fsck -n text that means the superblock or root directory is unusable.
DESTROYED = re.compile(
    r"BAD SUPER BLOCK|CANNOT READ: BLK\(S\): 16\b|SEARCH FOR ALTERNATE SUPER-BLOCK"
    r"|ROOT INODE UNALLOCATED|ROOT INODE NOT DIRECTORY|CANNOT ALLOCATE ROOT INODE",
    re.IGNORECASE)


def qemu_args(root_img, hd1, hd2, serial, ssh_port=2532, qmp_port=4532,
              gdb_port=1232, mem_mb=128):
    """The bench guest's command line.  Snapshot is per drive, not -snapshot,
    because -snapshot would also cover hd1 and hd2."""
    drive = "file=%s,format=raw,if=ide,index=%d,media=disk,snapshot=%s"
    return [
        QEMU, "-name", "RhapsodiOS ffsbench",
        "-M", "pc", "-cpu", "pentium", "-accel", "tcg", "-m", str(mem_mb),
        "-nodefaults", "-vga", "cirrus", "-display", "none",
        "-drive", drive % (root_img, 0, "on"),
        "-drive", drive % (hd1, 1, "off"),
        "-drive", drive % (hd2, 2, "off"),
        "-netdev", "user,id=n0,net=10.10.0.0/16,host=10.10.0.1,dns=10.10.0.3,"
                   "hostfwd=tcp:127.0.0.1:%d-%s:22" % (ssh_port, GUEST_IP),
        "-device", "ne2k_pci,netdev=n0,addr=03.0,mac=52:54:00:12:34:56",
        "-serial", "null",
        "-serial", "file:%s" % serial,
        "-rtc", "base=utc",
        "-qmp", "tcp:127.0.0.1:%d,server=on,wait=off" % qmp_port,
        "-gdb", "tcp:127.0.0.1:%d" % gdb_port,
    ]


def parse_probe(line):
    """A wakeprobe line, 'wp <sec> <late_ms_max> <free_pages> <pageouts>'."""
    f = line.split()
    if len(f) != 5 or f[0] != "wp":
        return None
    try:
        return ProbeSample(*(int(x) for x in f[1:]))
    except ValueError:
        return None


def _p99(values):
    s = sorted(values)
    return s[max(0, math.ceil(0.99 * len(s)) - 1)]


def summarize(samples, banners):
    late = [s.late_ms for s in samples]
    seen = [b for b in banners if b is not None]
    return {
        "late_max_ms": max(late) if late else None,
        "late_p99_ms": _p99(late) if late else None,
        "banner_max_s": max(seen) if seen else None,
        "banner_missed": len(banners) - len(seen),
    }


def classify(fsck_n, preen_status):
    """Grade a crashed hd1 from its fsck -n text and fsck -p exit status."""
    if DESTROYED.search(fsck_n):
        return "destroyed"
    if preen_status == 0:
        asked = any(l.rstrip().endswith("? no") for l in fsck_n.splitlines())
        if "** Phase 5" in fsck_n and not asked:
            return "clean"
        return "preen"
    return "manual"


def crash_valid(guest_log):
    """A crash run counts only if the kill landed after the replay started."""
    return "REPLAY-START" in guest_log.splitlines()


class Watchdog(object):
    """Expires when nothing has fed it for timeout_s seconds."""

    def __init__(self, timeout_s=60):
        self.timeout_s = timeout_s
        self.last = None

    def feed(self, now):
        self.last = now

    def expired(self, now):
        return self.last is not None and now - self.last > self.timeout_s


def csv_row(label, run):
    return ",".join([label] + ["" if run.get(k) is None else str(run[k])
                               for k in CSV_FIELDS])


def _hfs_guest():
    # hfs_guest pulls in tools/hfsimg; load it only when a disk is built
    return importlib.import_module("hfs_guest")


def label_template():
    """The installation floppy whose NeXT label every ffsbench disk reuses."""
    assets = os.environ.get("RHAP_VM_ASSETS") or os.path.dirname(
        os.path.abspath(__file__))
    return os.path.join(assets, "install",
                        "rhapsody_dr2_x86_InstallationFloppy.img")


def label_front():
    return _hfs_guest().label_front()


def build_scratch(path, mb=1024):
    """A NeXT-labelled disk whose partition a is mb megabytes of zeros.  The
    guest newfs's it once; that result is the pristine copy every run
    starts from (ufs_build cannot make a volume larger than the floppy
    template's single 2.3 MB cylinder group)."""
    hg = _hfs_guest()
    front = hg.label_front()
    head = bytearray(hg.wrap_label(b""))
    hg.ufs_build.patch_labels(head, front, mb * 2048)
    with open(path, "wb") as f:
        f.write(head)
        f.truncate(front + mb * 1024 * 1024)
