"""Sample QEMU's 8259 PIC state and per-IRQ counts across a guest boot.

Written to diagnose a stall in which the guest stopped receiving IRQ 14. The
decisive reading is the master PIC's in-service register: if its cascade bit
(IRQ 2, mask 0x04) is set and never clears while the slave shows the IRQ
pending and unmasked, the master is refusing to forward slave interrupts.

Boots work/test.img with -snapshot, types "-v" at the boot prompt to get the
text console, then dumps "info pic" and "info irq" at intervals into
OUTDIR/picstate.txt alongside the serial log.

Usage: python pic-probe.py
Compare with:
    grep -E "=====|irr=" shots-picprobe/picstate.txt
"""

import json, os, socket, subprocess, sys, time

IMG = "work/test.img"
OUT = "shots-picprobe"
PORT = 4471
SAMPLES = [20, 35, 50, 65, 80, 100, 125, 150]

os.makedirs(OUT, exist_ok=True)
serial = os.path.join(OUT, "serial.log")

class QMP(object):
    def __init__(self, port):
        for _ in range(60):
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=5)
                break
            except OSError:
                time.sleep(0.5)
        else:
            raise RuntimeError("no qmp")
        self.f = self.s.makefile("rw")
        self.f.readline()
        self.cmd("qmp_capabilities")
    def cmd(self, ex, **args):
        m = {"execute": ex}
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
    def hmp(self, c):
        r = self.cmd("human-monitor-command", **{"command-line": c})
        return (r or {}).get("return", "")

p = subprocess.Popen([
    "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg", "-m", "128",
    "-nodefaults", "-vga", "cirrus", "-display", "none",
    "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % IMG, "-snapshot",
    "-netdev", "user,id=n0", "-device", "ne2k_pci,netdev=n0",
    "-serial", "null", "-serial", "file:%s" % serial,
    "-rtc", "base=1998-05-08T12:00:00",
    "-qmp", "tcp:127.0.0.1:%d,server,nowait" % PORT, "-boot", "order=c",
])
log = open(os.path.join(OUT, "picstate.txt"), "w")
try:
    q = QMP(PORT)
    time.sleep(6)
    for k in ["minus", "v", "ret"]:
        q.cmd("send-key", keys=[{"type": "qcode", "data": k}])
        time.sleep(0.15)
    t0 = time.time()
    for at in SAMPLES:
        while time.time() - t0 < at:
            time.sleep(0.4)
        log.write("\n===== t=%ds =====\n" % at)
        log.write("--- info pic ---\n" + q.hmp("info pic") + "\n")
        log.write("--- info irq ---\n" + q.hmp("info irq") + "\n")
        log.flush()
        try:
            sz = os.path.getsize(serial)
        except OSError:
            sz = 0
        print("t=%ds captured (serial %d bytes)" % (at, sz))
finally:
    log.close()
    try:
        p.terminate(); p.wait(timeout=10)
    except Exception:
        p.kill()
print("done")
