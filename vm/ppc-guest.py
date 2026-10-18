#!/usr/bin/env python3
"""Run a Mac OS X Server 1.2v3 ppc guest under qemu-system-ppc.

    python vm/ppc-guest.py create [--base IMAGE] [--disk DISK]
    python vm/ppc-guest.py start  [--disk DISK] [--name NAME] [--telnet-port P]
                                  [--qmp-port P] [--snapshot] [--verbose] [--gui]
    python vm/ppc-guest.py run    [--telnet-port P] COMMAND
    python vm/ppc-guest.py stop   [--name NAME] [--qmp-port P]
    python vm/ppc-guest.py kernel [--base IMAGE] [--disk DISK] KERNEL

create makes DISK, a qcow2 overlay on the read-only base image (by default
~/Downloads/rhapsody.img, which is never written), and patches these files
on it in place, each kept at its original size:

  /etc/startup/0200_Tune      `nvram` -> `false`.  The stock 5.6 kernel's
      /dev/nvram adds PCI_IO_BASE_PHYS to the absolute reg of QEMU's
      /nvram@fff04000 node; the sum wraps to 0x7ff04000 and it traps.
  /etc/startup/0700_Devices   loads DEC21x4Ethernet instead of Floppy.
      mac99 has no floppy, and its PMAC_DEV_FLOPPY interrupt is not in the
      Sawtooth MPIC table, so registering it panics ("Interrupt 136 not
      found"); on ppc nothing else loads a PCI NIC driver.
  /etc/startup/1100_DirectoryServices  runs `nibindd -n`, so the local
      NetInfo domain does not wait at boot for a parent server.
  /etc/startup/1700_IPServices  clears root's NetInfo password, then starts
      inetd as before (the server-only bootpd/management parts are dropped).
  /etc/inetd.conf             enables telnetd.
  /etc/ttys                   marks the network ptys secure, so root may
                              telnet in.
  drvPPCGem.config            matches `gmac` (QEMU's sungem, a GEM) as well
      as the Sun card, and keeps the RXMAC summary bit masked: QEMU raises it
      despite MAC_RXMASK, and the driver never clears it, so it storms.
  DEC21x4Ethernet.config/Default.table  matches pci1011,19, QEMU's tulip
      (a 21143, already in the driver's Auto Detect IDs) in place of
      pci1385,1100.

start boots DISK on QEMU's mac99 (a "Sawtooth" G4 to the guest) in the
background, with a sungem NIC and a telnet forward.  The machine must not
have QEMU's default devices: the stock ATAPI CD-ROM on the second ata-3 bus
and the USB OHCI controller raise MPIC sources the stock 5.6 kernel has no
handler for.  The stock kernel cannot reach the network on mac99 (issue 61);
install a RhapsodiOS kernel with the Sawtooth fixes (see `kernel`) to get
telnet.  Boot takes about four minutes under TCG.  --snapshot discards every
write when QEMU exits.

kernel writes KERNEL over /mach_kernel on DISK in place, zero-padded to the
stock kernel's size (BootX loads by the Mach-O load commands, so the tail is
ignored); it must not be larger.  Put a further overlay on DISK first
(`qemu-img create -f qcow2 -F qcow2 -b disk.qcow2 kern.qcow2`) to keep the
stock kernel.

run logs in as root over telnet, runs COMMAND with /bin/sh, prints its
output and exits with its status.  stop quits QEMU through QMP after query-name confirms the guest
is NAME; run `sync; /sbin/reboot` first unless it is a --snapshot guest.

Standard library only.
"""

import argparse
import json
import os
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rhap_image  # noqa: E402

VM_DIR = os.path.dirname(os.path.abspath(__file__))
QEMU_DIR = r"C:\Program Files\qemu"
DEFAULT_BASE = os.path.join(os.path.expanduser("~"), "Downloads", "rhapsody.img")
DEFAULT_DISK = os.path.join(VM_DIR, "work", "ppc-mosxs", "disk.qcow2")

IPSERVICES = """#!/bin/sh

##
# Run the Internet super-server.
##

. /etc/rc.common

ConsoleMessage "Starting TCP/IP services"

# QEMU guest (vm/ppc-guest.py): root logs in over telnet with no password.
niutil -createprop . /users/root passwd ""

inetd
"""


def qemu_tool(name):
    return os.path.join(QEMU_DIR, name + ".exe")


def fit(text, size, path):
    """Pad text with a trailing comment line to exactly size bytes."""
    data = text.encode("latin-1")
    if len(data) > size:
        sys.exit("%s: patched text is %d bytes, more than its %d" % (path, len(data), size))
    if len(data) < size:
        data += b"#" * (size - len(data) - 1) + b"\n"
    return data


def patch_tune(text):
    assert text.count("nvram") == 3, "0200_Tune: expected three nvram calls"
    return text.replace("nvram", "false")


def patch_devices(text):
    floppy = "    driverLoader D=Floppy\n"
    header = "##\n# Set tape block sizes\n##\n"
    assert floppy in text and header in text
    text = text.replace(floppy, "    driverLoader D=DEC21x4Ethernet\n", 1)
    return text.replace(header, "", 1)     # a comment; makes room


def patch_dec21x4(text):
    assert " pci1385,1100 " in text
    return text.replace(" pci1385,1100 ", " pci1011,19   ", 1)


def patch_gem(text):
    old = '"Matching"      = "pci108e,2bad";'
    assert old in text
    return text.replace(old, '"Matching" = "pci108e,2bad gmac";', 1)


def patch_gem_imask(text):
    # Binary, through latin-1: in _enableAdapterInterrupts, GREG_IMASK &=
    # 0xffff7fee -> 0xffffffee, keeping the RXMAC summary bit masked.
    old = "\x3c\x00\xff\xff\x60\x00\x7f\xee"     # lis r0,-1; ori r0,r0,0x7fee
    assert text.count(old) == 1
    return text.replace(old, "\x3c\x00\xff\xff\x60\x00\xff\xee")


def patch_netinfo(text):
    header = "##\n# Start up NetInfo\n##\n"
    assert header in text and "\nnibindd\n" in text
    text = text.replace("\nnibindd\n", "\nnibindd -n\n", 1)
    return text.replace(header, "", 1)     # a comment; makes room


def patch_ipservices(text):
    assert "inetd" in text
    return IPSERVICES


def patch_inetd(text):
    assert "#telnet\t" in text
    return text.replace("#telnet\t", "telnet\t", 1)


def patch_ttys(text):
    out = []
    for line in text.splitlines():
        if line.startswith("#") or line.startswith("tty0"):
            continue  # comments and the unused serial lines make room
        if line.startswith("ttyp") or line.startswith("ttyq"):
            line = line.rstrip() + " secure"
        out.append(line)
    return "\n".join(out) + "\n"


PATCHES = [
    ("/private/etc/startup/0200_Tune", patch_tune),
    ("/private/etc/startup/0700_Devices", patch_devices),
    ("/private/etc/startup/1100_DirectoryServices", patch_netinfo),
    ("/private/etc/startup/1700_IPServices", patch_ipservices),
    ("/private/etc/inetd.conf", patch_inetd),
    ("/private/Drivers/ppc/DEC21x4Ethernet.config/Default.table", patch_dec21x4),
    ("/private/Drivers/ppc/drvPPCGem.config/Default.table", patch_gem),
    ("/private/Drivers/ppc/drvPPCGem.config/drvPPCGem_reloc", patch_gem_imask),
    ("/private/etc/ttys", patch_ttys),
]


def write_in_place(disk, img, inode, data):
    """Overwrite inode's data on the qcow2 disk; data is exactly its size.

    Fragment offsets come from img, the base image, so the file must not
    have been reallocated on the disk since."""
    assert len(data) == inode.size
    runs = []                            # [byte offset, data offset, length]
    for i, frag in enumerate(img.frags(inode)):
        off, n = img.frag_offset(frag), min(img.fsize, len(data) - i * img.fsize)
        if runs and runs[-1][0] + runs[-1][2] == off:
            runs[-1][2] += n
        else:
            runs.append([off, i * img.fsize, n])
    # Not qemu-io's `write -s`: on Windows it reads the source file in text
    # mode, which rewrites \r\n and stops at ^Z.  A raw window over the disk
    # takes the bytes as a block image; -S 0 writes zero runs too.
    tmp = disk + ".chunk"
    try:
        for off, start, n in runs:
            # The raw window must be whole sectors; past EOF is still this
            # file's own fragment, so zero-fill to the sector boundary.
            chunk = data[start:start + n]
            n = (n + 511) & ~511
            with open(tmp, "wb") as f:
                f.write(chunk + bytes(n - len(chunk)))
            subprocess.check_call([qemu_tool("qemu-img"), "convert", "-n", "-S", "0",
                                   "-f", "raw", tmp, "--target-image-opts",
                                   "driver=raw,offset=%d,size=%d,file.driver=qcow2,"
                                   "file.file.filename=%s" % (off, n, disk)])
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)


def cmd_create(args):
    if os.path.exists(args.disk):
        sys.exit("%s exists; delete it to start over" % args.disk)
    os.makedirs(os.path.dirname(args.disk), exist_ok=True)
    subprocess.check_call([qemu_tool("qemu-img"), "create", "-q", "-f", "qcow2",
                           "-F", "raw", "-b", os.path.abspath(args.base), args.disk])
    with rhap_image.Image(args.base) as img:
        for path, patch in PATCHES:
            inode = img.inode(img.resolve(path))
            new = fit(patch(img.read_file(inode).decode("latin-1")), inode.size, path)
            write_in_place(args.disk, img, inode, new)
            print("patched", path)
    print("created", args.disk)


def cmd_kernel(args):
    data = open(args.kernel, "rb").read()
    with rhap_image.Image(args.base) as img:
        inode = img.inode(img.resolve("/mach_kernel"))
        if len(data) > inode.size:
            sys.exit("%s is %d bytes; /mach_kernel has room for %d"
                     % (args.kernel, len(data), inode.size))
        write_in_place(args.disk, img, inode, data + bytes(inode.size - len(data)))
    print("installed %s as /mach_kernel on %s" % (args.kernel, args.disk))


def cmd_start(args):
    if not os.path.exists(args.disk):
        sys.exit("%s missing; run create first" % args.disk)
    logdir = os.path.dirname(os.path.abspath(args.disk))
    qemu = [
        qemu_tool("qemu-system-ppc"), "-name", args.name,
        "-M", "mac99,usb=off", "-m", "512", "-nodefaults", "-vga", "std", "-g", "800x600x8",
        "-drive", "file=%s,format=qcow2,if=ide,index=0,media=disk%s"
        % (args.disk, ",snapshot=on" if args.snapshot else ""),
        "-prom-env", r"boot-device=hd:6,\\:tbxi",
        "-prom-env", "boot-args=" + ("-v" if args.verbose else ""),
    ]
    if args.nic:
        # BOOTP must hand out a host name, or 0800_Network falls back to
        # bpwhoami and waits for it to time out.
        qemu += ["-netdev", "user,id=n0,hostname=mosxs,hostfwd=tcp:127.0.0.1:%d-:23"
                 % args.telnet_port,
                 "-device", "%s,netdev=n0" % args.nic]
    if args.cdrom:
        qemu += ["-drive", "file=%s,format=raw,if=ide,index=1,media=cdrom" % args.cdrom]
    qemu += [
        "-serial", "file:" + os.path.join(logdir, args.name + "-serial.log"),
        "-qmp", "tcp:127.0.0.1:%d,server=on,wait=off" % args.qmp_port,
        "-no-shutdown",                  # keep a powered-off guest's screen
        "-display", "default" if args.gui else "none",
    ]
    out = open(os.path.join(logdir, args.name + "-qemu.log"), "w")
    flags = getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    p = subprocess.Popen(qemu, stdin=subprocess.DEVNULL, stdout=out, stderr=out, creationflags=flags)
    time.sleep(2)
    if p.poll() is not None:             # e.g. a port already taken
        out.close()
        sys.exit("QEMU exited: " + open(out.name).read().strip())
    print("started %s (pid %d): telnet 127.0.0.1:%d, QMP 127.0.0.1:%d"
          % (args.name, p.pid, args.telnet_port, args.qmp_port))


def qmp(port, name, command):
    s = socket.create_connection(("127.0.0.1", port), timeout=10)
    f = s.makefile("rw")
    f.readline()

    def call(cmd):
        f.write(json.dumps({"execute": cmd}) + "\n")
        f.flush()
        while True:
            r = json.loads(f.readline())
            if "event" not in r:
                return r

    call("qmp_capabilities")
    who = call("query-name")["return"].get("name")
    if who != name:
        sys.exit("QMP port %d is guest %r, not %r; not touching it" % (port, who, name))
    return call(command)


def cmd_stop(args):
    print(qmp(args.qmp_port, args.name, "quit"))


class Telnet(object):
    """Just enough telnet: refuse every option, collect the rest."""

    IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240

    def __init__(self, port):
        self.s = socket.create_connection(("127.0.0.1", port), timeout=30)
        self.buf = b""

    def _recv(self, timeout):
        self.s.settimeout(timeout)
        data = self.s.recv(4096)
        if not data:
            raise EOFError("guest closed the connection")
        out, i = bytearray(), 0
        while i < len(data):
            c = data[i]
            if c != self.IAC or i + 1 >= len(data):
                out.append(c)
                i += 1
                continue
            op = data[i + 1]
            if op in (self.DO, self.DONT, self.WILL, self.WONT) and i + 2 < len(data):
                reply = self.WONT if op in (self.DO, self.DONT) else self.DONT
                self.s.sendall(bytes([self.IAC, reply, data[i + 2]]))
                i += 3
            elif op == self.SB:
                end = data.find(bytes([self.IAC, self.SE]), i)
                i = len(data) if end < 0 else end + 2
            else:
                i += 2
        self.buf += bytes(out)

    def expect(self, marker, timeout=60):
        deadline = time.time() + timeout
        while marker not in self.buf:
            left = deadline - time.time()
            if left <= 0:
                raise TimeoutError("no %r from guest; got %r" % (marker, self.buf[-200:]))
            try:
                self._recv(left)
            except socket.timeout:
                pass
        head, self.buf = self.buf.split(marker, 1)
        return head

    def send(self, line):
        self.s.sendall(line.encode("latin-1") + b"\r\n")


def cmd_run(args):
    # Markers are split by quotes in what we send, so the terminal's echo of
    # a command line never matches them.
    t = Telnet(args.telnet_port)
    t.expect(b"login: ")
    t.send("root")
    t.expect(b"# ", timeout=120)
    t.send("exec /bin/sh")
    t.send("PS1=''; stty -echo; echo MOSXS-''READY")
    t.expect(b"MOSXS-READY\r\n")
    t.send(args.command)
    t.send("echo MOSXS-''STATUS=$?")
    out = t.expect(b"MOSXS-STATUS=", timeout=args.timeout)
    status = t.expect(b"\r\n")
    t.send("exit")
    sys.stdout.write(out.replace(b"\r\n", b"\n").decode("latin-1"))
    sys.exit(int(status.strip() or 1))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("create")
    p.add_argument("--base", default=DEFAULT_BASE)
    p.add_argument("--disk", default=DEFAULT_DISK)
    p = sub.add_parser("start")
    p.add_argument("--disk", default=DEFAULT_DISK)
    p.add_argument("--name", default="ppc-mosxs")
    p.add_argument("--telnet-port", type=int, default=2481)
    p.add_argument("--qmp-port", type=int, default=4681)
    p.add_argument("--snapshot", action="store_true")
    p.add_argument("--verbose", action="store_true", help="boot with -v")
    p.add_argument("--gui", action="store_true", help="show the screen in a window")
    p.add_argument("--nic", default="sungem", help="QEMU NIC model (sungem, or tulip)")
    p.add_argument("--cdrom", help="ISO to attach as hd0's slave (the second bus storms on stock 5.6)")
    p = sub.add_parser("run")
    p.add_argument("--telnet-port", type=int, default=2481)
    p.add_argument("--timeout", type=int, default=3600)
    p.add_argument("command")
    p = sub.add_parser("kernel")
    p.add_argument("--base", default=DEFAULT_BASE)
    p.add_argument("--disk", default=DEFAULT_DISK)
    p.add_argument("kernel")
    p = sub.add_parser("stop")
    p.add_argument("--name", default="ppc-mosxs")
    p.add_argument("--qmp-port", type=int, default=4681)
    args = ap.parse_args()
    {"create": cmd_create, "start": cmd_start, "run": cmd_run, "stop": cmd_stop,
     "kernel": cmd_kernel}[args.cmd](args)


if __name__ == "__main__":
    main()
