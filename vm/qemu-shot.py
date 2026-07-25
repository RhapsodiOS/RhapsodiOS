#!/usr/bin/env python3
"""Boot a raw disk image headlessly under QEMU and capture the VGA console
as PNG screenshots, so boot progress can be checked without a human
watching the VGA window.

Also captures the guest's serial console: COM2 (0x2f8), where the kernel's
serial debug console writes, is redirected to OUTDIR/serial.log. COM1 is
left as -serial null because it belongs to the guest's drvISASerialPort.

Usage:
    python qemu-shot.py IMAGE OUTDIR [--at SECONDS[,SECONDS...]]
                         [--keys STRING] [--keys-at SECONDS] [--trace]

IMAGE must be a writable raw working image (e.g. vm/work/test.img), never
the original vm/rhapsody.vmdk or vm/golden.img; this is enforced by
rhap_inject.check_target (the same check rhap_inject.py's writer CLI uses,
so there is exactly one implementation of which image may be touched). The
drive is additionally opened with -snapshot, so even a permitted boot can
never write through to the backing file - this harness only observes boots,
it never needs to persist one.

Screenshot filenames encode host wall-clock seconds (e.g. shot-30s.png), not
guest boot progress. Under TCG these are not comparable between runs and
must not be read as a measure of how far the guest got.

Standard library only. No pip installs.
"""
import argparse
import json
import os
import socket
import struct
import subprocess
import sys
import time
import zlib

import rhap_inject

DEFAULT_AT = [5, 15, 30, 60, 90, 120]
DEFAULT_KEYS_AT = 3.0

# RTC base date/time passed to QEMU's -rtc. Must land strictly after the
# root filesystem's fs_time (epoch 894585442 = 1998-05-07T23:57:22Z) and
# within 2 days of it, or src/kernel-7/bsd/kern/kern_time.c's inittodr()
# prints a clock warning at boot (see kern_time.c ~line 264). Twelve hours
# after fs_time stays inside that window while tolerating up to 12 hours of
# negative timezone skew in how QEMU interprets the RTC base.
# vm/start-vm.cmd's -rtc must be kept in sync with this literal value.
RTC_BASE = "1998-05-08T12:00:00"
_HERE = os.path.dirname(os.path.abspath(__file__))

# Minimal character -> QMP qcode(s) mapping. Only covers what is needed to
# type "-v" and a kernel filename like "mach_kernel" at the boot prompt;
# not an exhaustive keymap.
KEY_MAP = {}
for _c in "abcdefghijklmnopqrstuvwxyz":
    KEY_MAP[_c] = [_c]
for _c in "0123456789":
    KEY_MAP[_c] = [_c]
KEY_MAP["-"] = ["minus"]
KEY_MAP["_"] = ["shift", "minus"]
KEY_MAP[" "] = ["spc"]
KEY_MAP["\n"] = ["ret"]
KEY_MAP["\r"] = ["ret"]


def chars_to_qcodes(s):
    """Validate every character in s has a QMP key mapping. Raises
    ValueError naming the first unmapped character."""
    for ch in s:
        if ch not in KEY_MAP:
            raise ValueError("no QMP key mapping for character %r" % ch)


def parse_ppm(data):
    """Parse a binary P6 PPM buffer, skipping whitespace and '#' comments
    between the P6/width/height/maxval header tokens. Returns
    (width, height, maxval, pixel_bytes)."""

    def skip_ws_comments(pos):
        while True:
            while pos < len(data) and data[pos:pos + 1].isspace():
                pos += 1
            if pos < len(data) and data[pos:pos + 1] == b"#":
                while pos < len(data) and data[pos:pos + 1] != b"\n":
                    pos += 1
            else:
                return pos

    def read_token(pos):
        pos = skip_ws_comments(pos)
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        return data[start:pos], pos

    pos = 0
    magic, pos = read_token(pos)
    if magic != b"P6":
        raise ValueError("not a P6 PPM: magic=%r" % magic)
    w_tok, pos = read_token(pos)
    h_tok, pos = read_token(pos)
    maxval_tok, pos = read_token(pos)
    # exactly one whitespace byte separates maxval from the pixel data
    pos += 1

    width, height, maxval = int(w_tok), int(h_tok), int(maxval_tok)
    if maxval > 255:
        raise ValueError("only 8-bit PPM samples are supported (maxval=%d)" % maxval)
    pixel_bytes = data[pos:pos + width * height * 3]
    return width, height, maxval, pixel_bytes


def write_png(path, w, h, rgb):
    raw = b"".join(b"\0" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6))
            + chunk(b"IEND", b"")
        )


class QMP:
    """Minimal synchronous QMP client: connect, negotiate capabilities,
    execute commands, ignoring async events."""

    def __init__(self, host, port, connect_timeout=30.0):
        deadline = time.monotonic() + connect_timeout
        sock = None
        last_err = None
        while time.monotonic() < deadline:
            try:
                sock = socket.create_connection((host, port), timeout=2.0)
                break
            except OSError as e:
                last_err = e
                time.sleep(0.2)
        if sock is None:
            raise RuntimeError("could not connect to QMP at %s:%d: %s" % (host, port, last_err))
        self.sock = sock
        self.buf = b""
        self._read_json()  # server greeting
        self.execute("qmp_capabilities")

    def _read_json(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("QMP connection closed unexpectedly")
            self.buf += chunk
        line, _, self.buf = self.buf.partition(b"\n")
        return json.loads(line.decode("utf-8"))

    def execute(self, cmd, **arguments):
        msg = {"execute": cmd}
        if arguments:
            msg["arguments"] = arguments
        self.sock.sendall(json.dumps(msg).encode("utf-8") + b"\n")
        while True:
            reply = self._read_json()
            if "event" in reply:
                continue
            if "error" in reply:
                raise RuntimeError("QMP command %r failed: %s" % (cmd, reply["error"]))
            return reply.get("return")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def find_free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def build_qemu_args(image, qmp_port, trace, serial_log):
    args = [
        "qemu-system-i386", "-M", "pc", "-cpu", "pentium", "-accel", "tcg",
        "-m", "128", "-k", "en-us",
        "-nodefaults", "-vga", "cirrus", "-display", "none",
        "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % image,
        "-snapshot",
        "-netdev", "user,id=n0", "-device", "ne2k_pci,netdev=n0",
        "-serial", "null", "-serial", "file:%s" % serial_log,
        "-rtc", "base=%s" % RTC_BASE,
        "-boot", "order=c",
        "-qmp", "tcp:127.0.0.1:%d,server,nowait" % qmp_port,
    ]
    if trace:
        logs_dir = os.path.join(_HERE, "logs")
        os.makedirs(logs_dir, exist_ok=True)
        trace_log = os.path.join(logs_dir, "qemu-trace.log")
        args += [
            "-trace", "enable=ide_*",
            "-trace", "enable=pci_cfg_*",
            "-d", "int",
            "-D", trace_log,
        ]
    return args


def fmt_seconds(t):
    return str(int(t)) if float(t).is_integer() else str(t)


def run(image, outdir, at_points, keys, keys_at, trace):
    try:
        rhap_inject.check_target(image)
    except rhap_inject.SafetyError as e:
        raise SystemExit(str(e))

    if keys is not None:
        chars_to_qcodes(keys)  # fail fast on an unmapped character

    os.makedirs(outdir, exist_ok=True)

    serial_log = os.path.join(outdir, "serial.log")
    print("serial console (COM2) log: %s" % serial_log)
    print("note: capture times are host wall-clock seconds, not guest boot "
          "progress; under TCG they are not comparable between runs")

    qmp_port = find_free_port()
    qemu_args = build_qemu_args(image, qmp_port, trace, serial_log)

    proc = subprocess.Popen(qemu_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    start = time.monotonic()
    qmp = None
    try:
        qmp = QMP("127.0.0.1", qmp_port)

        events = [(t, "shot", None) for t in at_points]
        if keys is not None:
            events.append((keys_at, "keys", keys))
        events.sort(key=lambda e: e[0])

        for target, kind, payload in events:
            remaining = target - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)

            if kind == "shot":
                ppm_path = os.path.join(outdir, "_shot.ppm")
                qmp.execute("screendump", filename=ppm_path)
                with open(ppm_path, "rb") as f:
                    data = f.read()
                w, h, maxval, pixels = parse_ppm(data)
                png_path = os.path.join(outdir, "shot-%ss.png" % fmt_seconds(target))
                write_png(png_path, w, h, pixels)
                os.remove(ppm_path)
                print("wrote %s (%dx%d)" % (png_path, w, h))
            else:
                for ch in payload:
                    qmp.execute("send-key", keys=[{"type": "qcode", "data": code} for code in KEY_MAP[ch]])
                    time.sleep(0.05)
                print("sent keys %r at %.1fs" % (payload, target))
    finally:
        if qmp is not None:
            try:
                qmp.execute("quit")
            except Exception:
                pass
            qmp.close()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def _fix_keys_arg(argv):
    """argparse treats an option value starting with '-' as another
    option, so a bare 'argv --keys -v' is rejected. Rewrite it to
    '--keys=-v' so callers can pass values like '-v' as documented."""
    out = []
    i = 0
    while i < len(argv):
        if argv[i] == "--keys" and i + 1 < len(argv):
            out.append("--keys=" + argv[i + 1])
            i += 2
        else:
            out.append(argv[i])
            i += 1
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("image", help="raw disk image to boot (never vm/rhapsody.vmdk)")
    p.add_argument("outdir", help="directory to write shot-<seconds>s.png into")
    p.add_argument("--at", default=None,
                    help="comma-separated capture points in seconds (default: %s)"
                         % ",".join(str(s) for s in DEFAULT_AT))
    p.add_argument("--keys", default=None, help="keystrokes to send via QMP sendkey")
    p.add_argument("--keys-at", type=float, default=DEFAULT_KEYS_AT,
                    help="seconds after launch to send --keys (default: %.1f)" % DEFAULT_KEYS_AT)
    p.add_argument("--trace", action="store_true",
                    help="add the ide_*/pci_cfg_* trace args start-vm.cmd -trace uses")
    args = p.parse_args(_fix_keys_arg(sys.argv[1:]))

    at_points = DEFAULT_AT if args.at is None else [float(s) for s in args.at.split(",")]

    run(args.image, args.outdir, at_points, args.keys, args.keys_at, args.trace)


if __name__ == "__main__":
    main()
