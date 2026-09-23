"""Drive the guest's console over QMP: type text, press keys, capture the screen.

The kernel serial console added to this tree is output-only, so anything
interactive -- a single-user shell, a boot prompt, a getty -- has to be driven
through the emulated keyboard and read back from the framebuffer.

Boots vm/work/test.img.  Pass --persist to let writes reach the image (the
default uses -snapshot and discards them).

Usage:
    python guest-console.py --probe               boot -s and screenshot
    python guest-console.py --fix-mouse --persist run the mouse-driver fix
"""

import json, os, socket, struct, subprocess, sys, time, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE = os.environ.get("RHAP_TEST_IMAGE") or os.path.join(HERE, "work", "test.img")

SHIFT_MAP = {
    "_": "minus", ":": "semicolon", "?": "slash", "~": "grave_accent",
    "|": "backslash", '"': "apostrophe", "<": "comma", ">": "dot",
    "{": "bracket_left", "}": "bracket_right", "+": "equal", "(": "9", ")": "0",
}
PLAIN_MAP = {
    " ": "spc", "/": "slash", ".": "dot", "-": "minus", "=": "equal",
    ",": "comma", ";": "semicolon", "'": "apostrophe", "\\": "backslash",
    "[": "bracket_left", "]": "bracket_right", "`": "grave_accent",
}


def read_ppm(path):
    d = open(path, "rb").read()
    vals, i = [], 2
    while len(vals) < 3:
        while d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b"#":
            while d[i:i + 1] != b"\n":
                i += 1
            continue
        j = i
        while not d[j:j + 1].isspace():
            j += 1
        vals.append(int(d[i:j])); i = j
    i += 1
    w, h, _ = vals
    return w, h, d[i:i + w * h * 3]


def write_png(path, w, h, rgb):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    open(path, "wb").write(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 6))
        + chunk(b"IEND", b""))


class Guest(object):
    def __init__(self, outdir, persist=False, port=4481, com1="null", extra=()):
        # com1 is the first serial port, which the kernel does not use -- pass
        # "msmouse" to put a Microsoft serial mouse on it.  extra appends raw
        # qemu arguments, for hardware a driver under test needs (e.g.
        # "-parallel", "null").
        if persist:
            # a persistent boot writes IMAGE, so it obeys the same rule as every
            # other writer: never golden.img or rhapsody.vmdk, whatever
            # RHAP_TEST_IMAGE says
            import rhap_inject
            rhap_inject.check_target(IMAGE)
        self.outdir = outdir
        os.makedirs(outdir, exist_ok=True)
        self.serial = os.path.join(outdir, "serial.log")
        args = [
            "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
            "-m", "128", "-nodefaults", "-vga", "cirrus", "-display", "none",
            "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % IMAGE,
            "-netdev", "user,id=n0", "-device", "ne2k_pci,netdev=n0",
            "-serial", com1, "-serial", "file:%s" % self.serial,
            "-rtc", "base=1998-05-08T12:00:00",
            "-qmp", "tcp:127.0.0.1:%d,server,nowait" % port, "-boot", "order=c",
        ]
        args.extend(extra)
        if not persist:
            args.insert(args.index("-drive") + 2, "-snapshot")
        self.proc = subprocess.Popen(args)
        for _ in range(60):
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                time.sleep(0.5)
        else:
            raise RuntimeError("no QMP connection")
        self.f = self.sock.makefile("rw")
        self.f.readline()
        self.cmd("qmp_capabilities")

    def cmd(self, execute, **args):
        m = {"execute": execute}
        if args:
            m["arguments"] = args
        self.f.write(json.dumps(m) + "\n"); self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                return None
            r = json.loads(line)
            if "event" not in r:
                return r

    def key(self, *codes):
        self.cmd("send-key", keys=[{"type": "qcode", "data": c} for c in codes])
        time.sleep(0.12)

    def type(self, text):
        for ch in text:
            if ch in PLAIN_MAP:
                self.key(PLAIN_MAP[ch])
            elif ch in SHIFT_MAP:
                self.key("shift", SHIFT_MAP[ch])
            elif ch.isdigit() or (ch.isalpha() and ch.islower()):
                self.key(ch)
            elif ch.isalpha():
                self.key("shift", ch.lower())
            else:
                raise ValueError("no key mapping for %r" % ch)

    def line(self, text):
        self.type(text)
        self.key("ret")

    def shot(self, name):
        ppm = os.path.join(self.outdir, name + ".ppm")
        self.cmd("screendump", filename=os.path.abspath(ppm))
        time.sleep(1.5)
        w, h, rgb = read_ppm(ppm)
        write_png(ppm[:-4] + ".png", w, h, rgb)
        os.remove(ppm)
        print("  shot: %s.png" % name)

    def close(self):
        try:
            self.proc.terminate(); self.proc.wait(timeout=10)
        except Exception:
            self.proc.kill()


def probe():
    g = Guest("shots-probe-single")
    try:
        time.sleep(6)
        g.line("-s")
        for t, n in ((40, "t40"), (80, "t80"), (130, "t130")):
            time.sleep(t - (40 if n != "t40" else 6) if n == "t40" else 0)
            g.shot(n)
            time.sleep(35)
    finally:
        g.close()


if __name__ == "__main__":
    if "--probe" in sys.argv:
        probe()


def fix_mouse():
    """Enable drvPS2Mouse and retire drvBusMouse, from a single-user shell."""
    P = "/private/Drivers/i386"
    g = Guest("shots-fixmouse", persist=True, port=4483)
    try:
        time.sleep(6)
        g.line("-s")
        print("waiting for single-user prompt...")
        time.sleep(135)
        g.shot("01-prompt")

        # NOTE: do NOT run fsck here.  Grafting deliberately leaves the donor's
        # blocks allocated but unreferenced; fsck "repairs" that by freeing them,
        # after which the allocator can hand those blocks to a later write and
        # overwrite the grafted kernel.  Observed: it removed /mach_kernel's
        # directory entry outright.  The graft artifacts do not prevent mounting
        # read-write, so mount directly.
        print("mount -w / ...")
        g.line("mount -w /")
        time.sleep(12)

        print("enabling PS2Mouse ...")
        g.line("cp %s/PS2Mouse.config/Default.table %s/PS2Mouse.config/Instance0.table" % (P, P))
        time.sleep(6)
        print("retiring BusMouse ...")
        g.line("mv %s/BusMouse.config/Instance0.table %s/BusMouse.config/Instance0.off" % (P, P))
        time.sleep(6)
        g.line("ls %s/PS2Mouse.config %s/BusMouse.config" % (P, P))
        time.sleep(6)
        g.shot("03-after")
        g.line("sync")
        time.sleep(8)
        g.line("sync")
        time.sleep(8)
        g.shot("04-synced")
    finally:
        g.close()


if "--fix-mouse" in sys.argv:
    fix_mouse()


def test_mouse():
    """Boot multi-user and check the cursor responds to motion events."""
    g = Guest("shots-mousecheck", port=4485)
    try:
        time.sleep(6)
        g.line("-v")
        time.sleep(26)
        g.line("y")                      # "Continue without network?"
        print("waiting for the window server...")
        time.sleep(250)
        g.shot("before")
        for _ in range(40):
            g.cmd("input-send-event", events=[
                {"type": "rel", "data": {"axis": "x", "value": 12}},
                {"type": "rel", "data": {"axis": "y", "value": 9}}])
            time.sleep(0.04)
        time.sleep(3)
        g.shot("after")
    finally:
        g.close()


if "--test-mouse" in sys.argv:
    test_mouse()
