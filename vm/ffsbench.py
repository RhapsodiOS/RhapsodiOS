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
              gdb_port=1232, mem_mb=128, iops=None, root_iops=None,
              extra=""):
    """The bench guest's command line.  Snapshot is per drive, not -snapshot,
    because -snapshot would also cover hd1 and hd2.  iops caps the disk
    under test's operations per second: QEMU's disk sits on the host page
    cache, so without it a synchronous write costs microseconds, not a
    seek."""
    drive = "file=%s,format=raw,if=ide,index=%d,media=disk,snapshot=%s"
    return [
        QEMU, "-name", "RhapsodiOS ffsbench",
        "-M", "pc", "-cpu", "pentium", "-accel", "tcg", "-m", str(mem_mb),
        "-nodefaults", "-vga", "cirrus", "-display", "none",
        "-drive", drive % (root_img, 0, "on") +
                  (",throttling.iops-total=%d" % root_iops if root_iops else ""),
        "-drive", drive % (hd1, 1, "off") +
                  (",throttling.iops-total=%d" % iops if iops else ""),
        "-drive", drive % (hd2, 2, "off"),
        "-netdev", "user,id=n0,net=10.10.0.0/16,host=10.10.0.1,dns=10.10.0.3,"
                   "hostfwd=tcp:127.0.0.1:%d-%s:22" % (ssh_port, GUEST_IP),
        "-device", "ne2k_pci,netdev=n0,addr=03.0,mac=52:54:00:12:34:56",
        "-serial", "null",
        "-serial", "file:%s" % serial,
        "-rtc", "base=utc",
        "-qmp", "tcp:127.0.0.1:%d,server=on,wait=off" % qmp_port,
        "-gdb", "tcp:127.0.0.1:%d" % gdb_port,
    ] + extra.split()


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
    # The floppy's own label: 1024-byte label sectors, like the installed
    # root disk (hfs_guest.wrap_label rewrites them to 512 for HFS).
    with open(hg.TEMPLATE, "rb") as f:
        head = bytearray(f.read(front))
    hg.ufs_build.patch_labels(head, front, mb * 1024)
    with open(path, "wb") as f:
        f.write(head)
        f.truncate(front + mb * 1024 * 1024)


# --- Task 4: driving the guest --------------------------------------------

import argparse
import json
import random
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.environ.get("RHAP_VM_ASSETS") or HERE
WORK = os.environ.get("FFSBENCH_WORK") or os.path.join(ASSETS, "work", "ffsbench")
ROOT_IMG = os.path.join(ASSETS, "work", "rhap-i386-bootstrapped.img")
SCRIPTS = os.path.join(HERE, "..", "tests", "ffsbench")

def lane(spec):
    """(ssh, qmp, gdb port, workload file) for a bench lane.  The default
    lane is 2532/4532/1232; FFSBENCH_PORTS="ssh,qmp,gdb" runs a second
    guest beside it, on its own copy of the workload disk because QEMU's
    image lock lets only one process hold a snapshot=off drive."""
    if not spec:
        return 2532, 4532, 1232, "workload.img"
    ssh, qmp, gdb = (int(x) for x in spec.split(","))
    return ssh, qmp, gdb, "workload-%d.img" % ssh


SSH_PORT, QMP_PORT, GDB_PORT, WORKLOAD_NAME = lane(os.environ.get("FFSBENCH_PORTS"))
IOPS = int(os.environ.get("FFSBENCH_IOPS") or 0) or None
QEMU_EXTRA = os.environ.get("FFSBENCH_QEMU_EXTRA", "")   # e.g. "-d cpu_reset -D f"


def guest_mem(spec):
    """Guest RAM in MB: FFSBENCH_MEM, else the 128 MB build guests run with."""
    return int(spec) if spec else 128


MEM_MB = guest_mem(os.environ.get("FFSBENCH_MEM"))
KERNEL_NAME = "mach_kernel_ffs"     # upload name; installed as /mach_kernel
GUEST_DIR = "/tmp/ffsbench"
BANNER_TRIES, BANNER_GAP = 20, 30   # first sshd banner: up to 10 minutes
MAX_BOOTFAILS = 3                   # in a row, before a campaign gives up
WATCHDOG_S = 60
RUN_LIMIT_S = 6 * 3600

LEGACY_SSH_OPTIONS = [
    "-o", "KexAlgorithms=diffie-hellman-group1-sha1",
    "-o", "HostKeyAlgorithms=ssh-dss",
    "-o", "Ciphers=3des-cbc",
    "-o", "MACs=hmac-sha1",
    "-o", "PubkeyAuthentication=no",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ServerAliveInterval=30",
    "-o", "ServerAliveCountMax=120",
]

# The bootstrapped image has nodes for hd0 and hd1 only: block major 3, raw
# major 15, eight minors per unit.
MKNODS = ("(test -b /dev/hd2a || mknod /dev/hd2a b 3 16) && "
          "(test -c /dev/rhd2a || mknod /dev/rhd2a c 15 16)")

# The installed root's geometry (63 sectors, 16 tracks, 16 cylinders per
# group); the floppy label's own 9x2 geometry gives newfs 7282 groups of
# 0.14 MB and a floating exception.
NEWFS = "newfs -u 63 -t 16 -c 16"

MOUNT = ("mkdir -p /mnt1 /mnt2 && %s && mount /dev/hd1a /mnt1 && "
         "mount -r /dev/hd2a /mnt2" % MKNODS)

# The build line under "Kernel Release 5.3:", in the kernel file and in the
# serial log of every boot, e.g.
# "Mon Oct  5 22:00:53 PDT 2026; root(rcbuilder):kernel-154.5.1-7.obj/RELEASE_I386"
STAMP = re.compile(rb"[A-Z][a-z]{2} [A-Z][a-z]{2} [ \d]\d \d\d:\d\d:\d\d [A-Z]+ \d{4}; "
                   rb"[\w()]+:[\w.\-]+/\w+")


def kernel_stamp(data):
    """The last kernel build stamp in a kernel file or a serial log."""
    if isinstance(data, str):
        data = data.encode("latin-1", "replace")
    m = STAMP.findall(data)
    return m[-1].decode("latin-1") if m else None


def check_stamp(serial_text, kernel_bytes):
    """Refuse to measure a guest that booted some other kernel."""
    booted, wanted = kernel_stamp(serial_text), kernel_stamp(kernel_bytes)
    if booted != wanted:
        raise SystemExit("WRONG KERNEL: booted %r, wanted %r" % (booted, wanted))


def banner_time(port, timeout=10):
    """Seconds until sshd's 'SSH-' banner arrives, or None."""
    t0 = time.monotonic()
    got = b""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=timeout) as s:
            while len(got) < 4:
                s.settimeout(max(0.1, timeout - (time.monotonic() - t0)))
                chunk = s.recv(4 - len(got))
                if not chunk:
                    return None
                got += chunk
    except OSError:
        return None
    return time.monotonic() - t0 if got == b"SSH-" else None


def boot_line(extra=""):
    """The line to type at boot:, or None to let the booter autoboot.  The
    test kernel is /mach_kernel itself: kernload links drivers against
    /mach_kernel's symbols, so a kernel booted under another name hangs at
    "Configuring device drivers"."""
    return "mach_kernel %s" % extra if extra else None


def read_conf(path):
    conf = {}
    with open(path, "r", encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    return conf


def ssh_argv(conf, port, command):
    """ssh keeps the first value it sees for an option, so the port goes
    first, and vm.conf's Port= (the shared box) is never passed at all.
    root's login shell is csh, so the command runs under /bin/sh."""
    quoted = "'" + command.replace("'", "'\\''") + "'"
    return ([conf.get("Ssh", "ssh.exe"), "-T", "-p", str(port)] +
            LEGACY_SSH_OPTIONS + ["%s@%s" % (conf["User"], conf["Host"]),
                                  "/bin/sh -c " + quoted])


class Ssh(object):
    """ssh to the bench guest, with the password supplied through
    SSH_ASKPASS the way vm/rhap-remote.ps1 does it."""

    def __init__(self, conf, port=SSH_PORT):
        self.conf, self.port = conf, port

    def run(self, command, stdin=None, on_line=None):
        """Run command, feeding each stdout line to on_line(text, host_time).
        Returns (exit status, stdout text)."""
        fd, ask = tempfile.mkstemp(suffix=".cmd")
        os.write(fd, b"@echo off\r\necho %RHAP_SSH_PASS%\r\n")
        os.close(fd)
        env = dict(os.environ, SSH_ASKPASS=ask, SSH_ASKPASS_REQUIRE="force",
                   RHAP_SSH_PASS=self.conf.get("Password", ""))
        env.setdefault("DISPLAY", "unused")
        try:
            p = subprocess.Popen(
                ssh_argv(self.conf, self.port, command), env=env,
                stdin=subprocess.DEVNULL if stdin is None else subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if stdin is not None:
                threading.Thread(target=_feed, args=(p, stdin), daemon=True).start()
            out = []
            for raw in iter(p.stdout.readline, b""):
                text = raw.decode("latin-1").rstrip("\r\n")
                out.append(text)
                if on_line:
                    on_line(text, time.time())
            p.wait()
            return p.returncode, "\n".join(out)
        finally:
            os.remove(ask)

    def push(self, local, remote):
        with open(local, "rb") as f:
            data = f.read()
        for attempt in range(3):     # a loaded host drops the odd connection
            rc, out = self.run("cat > %s && wc -c < %s" % (remote, remote),
                               stdin=data)
            if rc == 0 and out.split()[-1:] == [str(len(data))]:
                return
            time.sleep(10)
        raise RuntimeError("push %s -> %s failed: %s" % (local, remote, out))


def _feed(p, data):
    try:
        p.stdin.write(data)
    finally:
        p.stdin.close()


class Qmp(object):
    """A QMP client that keeps the events it reads, so a caller can wait
    for the RESET a guest reboot raises."""

    KEYS = {".": ["dot"], "-": ["minus"], "_": ["shift", "minus"],
            "=": ["equal"], " ": ["spc"], "\n": ["ret"], "/": ["slash"]}

    def __init__(self, port=QMP_PORT, timeout=60):
        deadline = time.monotonic() + timeout
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.5)
        self.f = self.sock.makefile("rwb")
        self.events = []
        self.lock = threading.Lock()
        self._read()
        self.execute("qmp_capabilities")

    def _read(self):
        line = self.f.readline()
        if not line:
            raise RuntimeError("QMP connection closed")
        return json.loads(line)

    def execute(self, cmd, **args):
        with self.lock:
            msg = {"execute": cmd}
            if args:
                msg["arguments"] = args
            self.f.write(json.dumps(msg).encode() + b"\n")
            self.f.flush()
            while True:
                r = self._read()
                if "event" in r:
                    self.events.append(r["event"])
                elif "error" in r:
                    raise RuntimeError("QMP %s: %s" % (cmd, r["error"]))
                else:
                    return r.get("return")

    def wait_event(self, name, timeout):
        deadline = time.monotonic() + timeout
        with self.lock:
            try:
                while name not in self.events:
                    left = deadline - time.monotonic()
                    if left <= 0:
                        return False
                    self.sock.settimeout(left)
                    r = self._read()
                    if "event" in r:
                        self.events.append(r["event"])
            except (socket.timeout, OSError):
                return False
            finally:
                self.sock.settimeout(5)
        return True

    def type(self, text):
        for ch in text:
            if ch.isalnum():
                codes = ["shift", ch.lower()] if ch.isupper() else [ch]
            else:
                codes = self.KEYS[ch]
            self.execute("send-key",
                         keys=[{"type": "qcode", "data": c} for c in codes])
            time.sleep(0.05)

    def quit(self):
        try:
            self.execute("quit")
        except (RuntimeError, OSError, ValueError):
            pass


def ports_free():
    for port in (SSH_PORT, QMP_PORT, GDB_PORT):
        s = socket.socket()
        s.settimeout(1)
        busy = s.connect_ex(("127.0.0.1", port)) == 0
        s.close()
        if busy:
            raise SystemExit("port %d is in use" % port)


class Guest(object):
    """One QEMU process running the bench guest."""

    def __init__(self, outdir, hd1, hd2, root_iops=None):
        ports_free()
        os.makedirs(outdir, exist_ok=True)
        self.serial = os.path.join(outdir, "serial.log")
        flags = 0x00000008 | 0x00000200 if os.name == "nt" else 0
        self.proc = subprocess.Popen(
            qemu_args(ROOT_IMG, hd1, hd2, self.serial, SSH_PORT, QMP_PORT,
                      GDB_PORT, mem_mb=MEM_MB, iops=IOPS, root_iops=root_iops,
                      extra=QEMU_EXTRA),
            creationflags=flags,
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=open(os.path.join(outdir, "qemu.err"), "wb"))
        self.qmp = Qmp()
        if self.qmp.execute("query-name").get("name") != "RhapsodiOS ffsbench":
            raise SystemExit("QMP on %d is not our guest" % QMP_PORT)

    def serial_text(self):
        try:
            with open(self.serial, "rb") as f:
                return f.read().decode("latin-1")
        except OSError:
            return ""

    def wait_sshd(self):
        """One banner attempt every BANNER_GAP seconds, no tighter."""
        for _ in range(BANNER_TRIES):
            time.sleep(BANNER_GAP)
            if banner_time(SSH_PORT) is not None:
                return True
        return False

    def quit(self):
        self.qmp.quit()
        try:
            self.proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            self.proc.kill()


def _conf():
    return read_conf(os.path.join(ASSETS, "vm.conf"))


def _log(outdir, name, text):
    with open(os.path.join(outdir, name), "a", encoding="utf-8") as f:
        f.write(text + "\n")


def boot_test_kernel(g, ssh, kernel, bootargs=""):
    """Install kernel as /mach_kernel on the snapshot root, reboot into it
    and check its stamp.  The swap lives only in QEMU's snapshot overlay,
    which outlives a guest reboot inside one QEMU process.  Both moves are
    renames, so the base image's corrupt root never frees the blocks its
    /mach_kernel shares with another file."""
    if not g.wait_sshd():
        raise SystemExit("sshd never answered on the stock kernel")
    ssh.push(kernel, "/" + KERNEL_NAME)
    rc, out = ssh.run("mv /mach_kernel /mach_kernel_orig && mv /%s /mach_kernel"
                      % KERNEL_NAME)
    if rc != 0:
        raise SystemExit("could not install the kernel: %s" % out)
    g.qmp.events = []
    ssh.run("sync; /sbin/reboot")
    if not g.qmp.wait_event("RESET", 300):
        raise SystemExit("the guest never reset after /sbin/reboot")
    line = boot_line(bootargs)
    if line:
        time.sleep(6)
        g.qmp.type(line + "\n")
    if not g.wait_sshd():
        raise SystemExit("sshd never answered on %s" % KERNEL_NAME)
    with open(kernel, "rb") as f:
        check_stamp(g.serial_text(), f.read())
    # rc empties /tmp at boot, so the scripts go over after the reboot
    ssh.run("mkdir -p %s" % GUEST_DIR)
    for name in ("wakeprobe.c", "run.sh", "crash.sh"):
        ssh.push(os.path.join(SCRIPTS, name), "%s/%s" % (GUEST_DIR, name))


def _fresh_hd1(outdir):
    os.makedirs(outdir, exist_ok=True)
    hd1 = os.path.join(outdir, "hd1.img")
    shutil.copyfile(os.path.join(WORK, "scratch-pristine.img"), hd1)
    return hd1


def _workload():
    path = os.path.join(WORK, WORKLOAD_NAME)
    if not os.path.exists(path):
        shutil.copyfile(os.path.join(WORK, "workload.img"), path)
    return path


ROOT_TARGET = "/private/tmp/ffsbench-root"


def run_command(script, single=False):
    """The guest command for one run.  By default the replay writes to the
    fresh hd1; single=True writes into the root filesystem instead, as
    rbuild really does, so sshd's reads share a disk queue with it."""
    if single:
        return "%s && mkdir -p %s && sh %s/%s /mnt2 %s" % (
            MOUNT, ROOT_TARGET, GUEST_DIR, script, ROOT_TARGET)
    return "%s && sh %s/%s /mnt2 /mnt1" % (MOUNT, GUEST_DIR, script)


def _drive(g, ssh, outdir, script, on_marker=None, single=False):
    """Run a guest script while watching wakeprobe and sshd.  Returns the
    guest log, 'ok' / 'exit <n>' / 'hardlock', and the banner times."""
    wd = Watchdog(WATCHDOG_S)
    banners, stop = [], threading.Event()
    lines, state = [], {"result": None}

    def on_line(text, t):
        lines.append(text)
        _log(outdir, "guest.log", "%.1f %s" % (t, text))
        if text == "PROBE-BUILT" or parse_probe(text):
            wd.feed(t)
        if on_marker:
            on_marker(text, t)

    def probe_banners():
        while not stop.wait(5):
            b = banner_time(SSH_PORT, timeout=5)
            banners.append(b)
            _log(outdir, "banner.log", "%.1f %s" % (time.time(), b))

    def run():
        rc, _ = ssh.run(run_command(script, single), on_line=on_line)
        state["result"] = "ok" if rc == 0 else "exit %d" % rc

    threading.Thread(target=probe_banners, daemon=True).start()
    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    start = time.time()
    while worker.is_alive():
        worker.join(5)
        now = time.time()
        if worker.is_alive() and (wd.expired(now) or now - start > RUN_LIMIT_S):
            capture(g, outdir)
            state["result"] = "hardlock"
            break
    stop.set()
    return "\n".join(lines), state["result"], banners


def boot_or_skip(g, ssh, kernel, bootargs, outdir):
    """Boot the test kernel.  A guest whose sshd never answers is logged as
    a bootfail and the run is skipped, not counted; a wrong kernel stays
    fatal, since measuring it would credit results to the wrong code."""
    try:
        boot_test_kernel(g, ssh, kernel, bootargs)
        return True
    except SystemExit as e:
        if str(e).startswith("WRONG KERNEL"):
            raise
        _log(outdir, "result.txt", "bootfail: %s" % e)
        return False


def _bootfail(fails):
    if fails >= MAX_BOOTFAILS:
        raise SystemExit("%d boots in a row failed; giving up" % fails)


def _marker_values(log):
    vals = {}
    for line in log.splitlines():
        f = line.split()
        if len(f) == 2 and f[0] in ("REPLAY-END", "RM-END", "SLOW1", "SLOW2"):
            vals[f[0]] = f[1]
    return vals


def _new_outdir(label, name):
    outdir = os.path.join(WORK, "runs", label, name)
    if os.path.exists(outdir):
        raise SystemExit("%s exists; evidence is never overwritten" % outdir)
    return outdir


def bench(kernel, label, runs, bootargs="", start=0, single=False):
    conf = _conf()
    csv_dir = os.path.join(WORK, "runs", label)
    i, done, fails = start, 0, 0
    while done < runs:
        outdir = _new_outdir(label, "bench-%d" % i)
        i += 1
        hd1 = _fresh_hd1(outdir)
        g = Guest(outdir, hd1, _workload(),
                  root_iops=(IOPS or 100) if single else None)
        try:
            ssh = Ssh(conf)
            booted = boot_or_skip(g, ssh, kernel, bootargs, outdir)
            if booted:
                log, result, banners = _drive(g, ssh, outdir, "run.sh",
                                              single=single)
                if result == "ok":
                    _, man = ssh.run("cat %s/manifest.txt" % GUEST_DIR)
                    _log(outdir, "manifest.txt", man)
        finally:
            g.quit()
            os.remove(hd1)
        if not booted:
            fails += 1
            _bootfail(fails)
            continue
        fails = 0
        done += 1
        v = _marker_values(log)
        samples = [s for s in map(parse_probe, log.splitlines()) if s]
        run = dict(summarize(samples, banners), replay_s=v.get("REPLAY-END"),
                   rm_s=v.get("RM-END"), slow1_mbs=v.get("SLOW1"),
                   slow2_mbs=v.get("SLOW2"))
        row = csv_row(label, run)
        _log(outdir, "result.txt", "%s\n%s" % (result, row))
        if not os.path.exists(os.path.join(csv_dir, "bench.csv")):
            _log(csv_dir, "bench.csv", CSV_HEADER)
        _log(csv_dir, "bench.csv", row if result == "ok" else row + "  # " + result)
        print(result, row)


def _replay_budget(label):
    """Median replay_s of this label's good bench rows, else 600 s."""
    path = os.path.join(WORK, "runs", label, "bench.csv")
    vals = []
    if os.path.exists(path):
        for line in open(path).read().splitlines()[1:]:
            f = line.split(",")
            if "#" not in line and len(f) > 1 and f[1]:
                vals.append(float(f[1]))
    return sorted(vals)[len(vals) // 2] if vals else 600.0


def crash(kernel, label, runs, seed=0, bootargs="", start=0):
    conf = _conf()
    budget = _replay_budget(label)
    tally = collections.Counter()
    i, done, fails = start, 0, 0
    while done < runs:
        outdir = _new_outdir(label, "crash-%d" % i)
        delay = random.Random(seed + i).uniform(5, budget)
        hd1 = _fresh_hd1(outdir)
        g = Guest(outdir, hd1, _workload())
        killed = threading.Event()

        def kill(g=g):
            killed.set()
            g.qmp.quit()

        def on_marker(text, t, delay=delay):
            if text == "REPLAY-START":
                threading.Timer(delay, kill).start()
        try:
            ssh = Ssh(conf)
            booted = boot_or_skip(g, ssh, kernel, bootargs, outdir)
            if booted:
                log, result, _ = _drive(g, ssh, outdir, "crash.sh", on_marker)
        finally:
            g.quit()
        if not booted:
            os.remove(hd1)
            i += 1
            fails += 1
            _bootfail(fails)
            continue
        fails = 0
        if result == "hardlock":
            grade = "hardlock"
        elif not crash_valid(log) or not killed.is_set():
            _log(outdir, "result.txt", "invalid: the kill did not land in the replay")
            os.remove(hd1)
            i += 1
            continue
        else:
            keep = os.path.join(outdir, "hd1-after-crash.img")
            shutil.copyfile(hd1, keep)
            grade = _grade(conf, outdir, hd1)
            if grade == "clean":
                os.remove(keep)
        os.remove(hd1)
        tally[grade] += 1
        _log(outdir, "result.txt", "delay %.1f s: %s" % (delay, grade))
        print("crash %d: %s" % (i, grade))
        i += 1
        done += 1
    _log(os.path.join(WORK, "runs", label), "crash.txt", json.dumps(tally))
    print(dict(tally))


def _grade(conf, outdir, hd1):
    """Boot the stock kernel with the crashed hd1 attached and fsck it."""
    fdir = os.path.join(outdir, "fsck")
    g = Guest(fdir, hd1, _workload())
    try:
        if not g.wait_sshd():
            return "ungraded"   # hd1-after-crash.img is kept for a regrade
        _, out = Ssh(conf).run("fsck -n /dev/rhd1a; echo PREEN; "
                               "fsck -p /dev/rhd1a; echo STATUS $?")
    finally:
        g.quit()
    _log(fdir, "fsck.txt", out)
    fsck_n, _, rest = out.partition("PREEN")
    m = re.search(r"STATUS (\d+)", rest)
    return classify(fsck_n, int(m.group(1)) if m else 8)


def capture(g, outdir):
    """savevm, then the registers and the kernel stack through the gdbstub."""
    try:
        g.qmp.execute("human-monitor-command", **{"command-line": "savevm hang"})
    except (RuntimeError, OSError) as e:
        _log(outdir, "gdb.txt", "savevm failed: %s" % e)
    try:
        regs, stack = gdb_snapshot(GDB_PORT)
        _log(outdir, "gdb.txt", "registers %s\nstack %s" % (regs, stack))
    except (OSError, ValueError) as e:
        _log(outdir, "gdb.txt", "gdbstub failed: %s" % e)


def _gdb_reply(s):
    data = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            raise OSError("gdbstub closed")
        data += chunk
        start = data.find(b"$")
        end = data.find(b"#", start + 1)
        if start >= 0 and end >= 0 and len(data) >= end + 3:
            s.sendall(b"+")
            return data[start + 1:end].decode()


def _gdb_packet(s, body):
    s.sendall(("$%s#%02x" % (body, sum(body.encode()) % 256)).encode())
    return _gdb_reply(s)


def gdb_snapshot(port):
    """Stop the guest, read the registers and 4 KB from ESP up (linear
    address: kernel segments are based at 0xc0000000), then detach with D
    so the VM is not left paused."""
    with socket.create_connection(("127.0.0.1", port), timeout=10) as s:
        s.sendall(b"\x03")
        _gdb_reply(s)
        regs = _gdb_packet(s, "g")
        esp = int.from_bytes(bytes.fromhex(regs[32:40]), "little")
        stack = _gdb_packet(s, "m%x,1000" % ((esp + 0xc0000000) & 0xffffffff))
        _gdb_packet(s, "D")
    return regs, stack


def prep(scratch_mb=1024, workload_mb=256):
    """Make scratch-pristine.img and workload.img once: the guest newfs's
    both, then unpacks apks/, replay.list and slow.c onto the workload."""
    conf = _conf()
    scratch = os.path.join(WORK, "scratch-pristine.img")
    workload = _workload()
    for p in (scratch, workload):
        if os.path.exists(p):
            raise SystemExit("%s exists" % p)
    build_scratch(scratch, scratch_mb)
    build_scratch(workload, workload_mb)
    tar = os.path.join(WORK, "workload.tar")
    with tarfile.open(tar, "w", format=tarfile.USTAR_FORMAT) as t:
        for name in ("replay.list", "slow.c", "apks"):
            t.add(os.path.join(WORK, name), arcname=name)
    with open(tar, "rb") as f:
        data = f.read()
    outdir = os.path.join(WORK, "prep")
    g = Guest(outdir, scratch, workload)
    try:
        if not g.wait_sshd():
            raise SystemExit("sshd never answered")
        ssh = Ssh(conf)
        _, out = ssh.run(
            "%s && %s /dev/rhd1a > /dev/null && %s /dev/rhd2a > /dev/null"
            " && mkdir -p /mnt2 && mount /dev/hd2a /mnt2 && (cd /mnt2 && pax -r)"
            " && umount /mnt2 && fsck -n /dev/rhd1a && fsck -n /dev/rhd2a"
            " && echo PREP-OK" % (MKNODS, NEWFS, NEWFS), stdin=data)
        _log(outdir, "prep.txt", out)
        if "PREP-OK" not in out:
            raise SystemExit("prep failed; see %s" % os.path.join(outdir, "prep.txt"))
        g.qmp.events = []
        ssh.run("sync; /sbin/reboot")
        g.qmp.wait_event("RESET", 300)
    finally:
        g.quit()
    print("prep ok")



# --- stall mode: a real rbuild kernel with repeated ssh logins -------------

STALL_DIR = "/build/ffsstall"
LOGIN_EVERY_S = 15
LOGIN_LIMIT_S = 120
STALL_RUN_LIMIT_S = 2 * 3600


def rbuild_start_command():
    """Start wakeprobe and `rbuild kernel` in the background, detached from
    the ssh session, on the root filesystem as a real build would be."""
    return ("PATH=/build/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin; export PATH; "
            "mkdir -p %(d)s %(d)s-state %(g)s && "
            "cc -O -o %(g)s/wakeprobe %(g)s/wakeprobe.c && "
            "(nohup %(g)s/wakeprobe > %(g)s/wp.log 2>&1 &) && "
            "(nohup sh -c 'rbuild kernel --state %(d)s-state --arch i386 "
            "/build/src /build/repo %(d)s; echo RBUILD-EXIT $?' "
            "> %(g)s/rbuild.log 2>&1 &)"
            % {"d": STALL_DIR, "g": GUEST_DIR})


def stall_summary(logins, limit=LOGIN_LIMIT_S):
    done = sorted(t for t in logins if t is not None)
    return {"logins": len(logins),
            "login_max_s": done[-1] if done else None,
            "login_median_s": done[len(done) // 2] if done else None,
            "login_timeouts": len(logins) - len(done)}


def timed_login(conf, command, limit=LOGIN_LIMIT_S):
    """Seconds for a full ssh login that runs command, or None after limit."""
    fd, ask = tempfile.mkstemp(suffix=".cmd")
    os.write(fd, b"@echo off\r\necho %RHAP_SSH_PASS%\r\n")
    os.close(fd)
    env = dict(os.environ, SSH_ASKPASS=ask, SSH_ASKPASS_REQUIRE="force",
               RHAP_SSH_PASS=conf.get("Password", ""))
    env.setdefault("DISPLAY", "unused")
    t0 = time.monotonic()
    p = subprocess.Popen(ssh_argv(conf, SSH_PORT, command), env=env,
                         stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT)
    try:
        out, _ = p.communicate(timeout=limit)
        return time.monotonic() - t0, out.decode("latin-1")
    except subprocess.TimeoutExpired:
        p.kill()
        p.communicate()
        return None, ""
    finally:
        os.remove(ask)


def no_update_command():
    """Stop the update daemon (its 30 s sync is what drives the mapfs
    deadlock), and prove it is gone, so a kernel that deadlocks can still
    be measured as a control."""
    return ("kill `ps -axc | awk '$NF == \"update\" {print $1}'`; sleep 2; "
            "ps -axc | awk '$NF == \"update\"' | grep -q . || echo UPDATE-GONE")


def stall(kernel, label, bootargs="", no_update=False):
    """Boot kernel, start a real rbuild kernel, and log in every
    LOGIN_EVERY_S seconds until it finishes, timing each login."""
    conf = _conf()
    outdir = _new_outdir(label, "stall-0")
    hd1 = _fresh_hd1(outdir)
    g = Guest(outdir, hd1, _workload(), root_iops=IOPS)
    logins, state = [], "running"
    try:
        ssh = Ssh(conf)
        if not boot_or_skip(g, ssh, kernel, bootargs, outdir):
            return
        if no_update:
            _, out = ssh.run(no_update_command())
            _log(outdir, "result.txt", "no_update: %s" % out.strip()[-40:])
            if "UPDATE-GONE" not in out:
                raise SystemExit("could not stop update: %s" % out)
        ssh.run(rbuild_start_command())
        start = time.time()
        while time.time() - start < STALL_RUN_LIMIT_S:
            time.sleep(LOGIN_EVERY_S)
            t, out = timed_login(conf, "tail -2 %s/rbuild.log" % GUEST_DIR)
            logins.append(t)
            _log(outdir, "logins.log", "%.1f %s %s" % (
                time.time() - start, t, out.strip().replace("\n", " | ")[-160:]))
            m = re.search(r"RBUILD-EXIT (\d+)", out)
            if m:
                state = ("complete" if "rbuild: kernel complete" in out
                         else "exit %s" % m.group(1))
                break
        elapsed = time.time() - start
        _, rlog = ssh.run("cat %s/rbuild.log" % GUEST_DIR)
        _log(outdir, "rbuild.log", rlog)
        _, wp = ssh.run("cat %s/wp.log" % GUEST_DIR)
        _log(outdir, "wp.log", wp)
        samples = [s for s in map(parse_probe, wp.splitlines()) if s]
        late = summarize(samples, [])
        res = dict(stall_summary(logins), rbuild=state, elapsed_s=int(elapsed),
                   late_max_ms=late["late_max_ms"], late_p99_ms=late["late_p99_ms"])
    finally:
        g.quit()
        os.remove(hd1)
    _log(outdir, "result.txt", json.dumps(res))
    print(json.dumps(res))


def main(argv):
    p = argparse.ArgumentParser(description="FFS replay, crash and stall harness")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("prep")
    st = sub.add_parser("stall")
    st.add_argument("--kernel", required=True)
    st.add_argument("--label", required=True)
    st.add_argument("--bootargs", default="")
    st.add_argument("--no-update", action="store_true",
                    help="stop the update daemon first (a control run)")
    for name, runs in (("bench", 3), ("crash", 20)):
        s = sub.add_parser(name)
        s.add_argument("--kernel", required=True)
        s.add_argument("--label", required=True)
        s.add_argument("--runs", type=int, default=runs)
        s.add_argument("--bootargs", default="")
        s.add_argument("--start", type=int, default=0,
                       help="first run index, to continue a campaign")
        if name == "bench":
            s.add_argument("--single-disk", action="store_true",
                           help="replay onto the root disk, throttled")
        if name == "crash":
            s.add_argument("--seed", type=int, default=0)
    a = p.parse_args(argv[1:])
    if a.cmd == "prep":
        prep()
    elif a.cmd == "stall":
        stall(a.kernel, a.label, a.bootargs, a.no_update)
    elif a.cmd == "bench":
        bench(a.kernel, a.label, a.runs, a.bootargs, a.start, a.single_disk)
    else:
        crash(a.kernel, a.label, a.runs, a.seed, a.bootargs, a.start)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
