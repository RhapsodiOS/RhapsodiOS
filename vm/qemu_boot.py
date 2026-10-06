#!/usr/bin/env python3
"""Boot a disk image under QEMU and capture its consoles and screen.

    python vm/qemu_boot.py {bios,uefi} IMAGE OUTDIR [--esp ESP_IMAGE]
                           [--hd1 IMAGE [--boot-hd1]] [--keep-hd0]
                           [--nic MODEL]
                           [--ssh-port PORT] [--type SECONDS:TEXT ...]
                           [--keys SECONDS:TEXT ...]
                           [--at SECONDS[,SECONDS...]] [--firmware-dir DIR]

bios boots QEMU's own SeaBIOS.  uefi boots the IA32 edk2 firmware QEMU ships
as share/edk2-i386-code.fd, so no OVMF build is needed.  IMAGE is the first
IDE disk (i440FX/PIIX3, the controller the EIDE boot driver probes); --esp
adds a virtio disk for the two-disk layout, whose loader sits on an
ESP-only disk.  --hd1 adds a second IDE disk, the primary slave, which the
guest sees as hd1; --boot-hd1 makes it the boot disk, as the install
media is in the design's harness, with IMAGE, the blank target, still hd0.
--nic adds a network card of that QEMU model on QEMU's user network, and
--ssh-port forwards that 127.0.0.1 port to the guest's ssh.  Each --type
types TEXT and presses Enter at SECONDS, for a boot prompt or a single-user
shell; each --keys types TEXT without Enter, for menus that act on a key.

OUTDIR gets console.log (COM1: firmware and loader), kernel.log (COM2: the
kernel's serial console) and shot-<N>s.png screenshots.  QEMU quits after
the last --at or --type time.

Every drive is opened with -snapshot, so no boot ever writes an image, and
any path named golden.img or rhapsody.vmdk is refused outright, wherever it
lives (so the main checkout's masters are refused from a worktree too).
The one exception is --keep-hd0, for an installer's target: IMAGE keeps the
guest's writes while every other drive stays snapshotted.  It is refused
unless IMAGE is a throwaway file under the temp directory or a vm/work/p5-*
directory, and never for the masters, test.img, the media, the
preinstalled image or the bootstrapped base image.
QEMU gets native paths straight from Python: Git Bash does not rewrite
`-serial file:/d/...` for native programs, which is why this is not a shell
script.  Standard library only.
"""
import argparse
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_MASTERS = ("golden.img", "rhapsody.vmdk")
DEFAULT_AT = "60,120,180"
# Never opened writable by --keep-hd0, wherever they live.
_NEVER_KEPT = _MASTERS + ("test.img", "media.img", "preinstalled.img",
                          "rhap-i386-bootstrapped.img")


def _load_qemu_shot():
    spec = importlib.util.spec_from_file_location(
        "qemu_shot", os.path.join(_HERE, "qemu-shot.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qemu_shot = _load_qemu_shot()
# What --type can send: qemu-shot's boot-prompt keys plus a path's.
KEYS = dict(qemu_shot.KEY_MAP, **{"/": ["slash"], ".": ["dot"]})


def refuse_masters(path):
    """Exit if path is one of the read-only master images, wherever it
    lives: by same-file identity against this checkout's own copy, or by
    basename against golden.img/rhapsody.vmdk anywhere (e.g. the main
    checkout, when running from a worktree that has no copy of its own)."""
    for name in _MASTERS:
        master = os.path.join(_HERE, name)
        if (os.path.exists(master) and os.path.exists(path)
                and os.path.samefile(path, master)):
            raise SystemExit("refusing to boot %s: it is a read-only master"
                             % path)
    if os.path.basename(path).lower() in (n.lower() for n in _MASTERS):
        raise SystemExit("refusing to boot %s: it is a read-only master"
                         % path)


def check_keepable(path):
    """Exit unless path may be opened writable by --keep-hd0: not a
    protected image, and inside the temp directory or a work/p5-* one."""
    real = os.path.realpath(path)
    if os.path.basename(real).lower() in _NEVER_KEPT:
        raise SystemExit("refusing to keep writes to %s: it is a protected "
                         "image" % path)
    temp = os.path.realpath(tempfile.gettempdir())
    try:
        under_temp = os.path.commonpath([real, temp]) == temp
    except ValueError:  # another drive
        under_temp = False
    parent = os.path.dirname(real)
    in_p5 = (os.path.basename(parent).startswith("p5-") and
             os.path.basename(os.path.dirname(parent)) == "work")
    if not (under_temp or in_p5):
        raise SystemExit("refusing to keep writes to %s: --keep-hd0 takes "
                         "a throwaway file under %s or work/p5-*"
                         % (path, temp))


def default_firmware_dir(qemu):
    found = shutil.which(qemu)
    if found is None:
        raise SystemExit("%s is not on PATH" % qemu)
    return os.path.join(os.path.dirname(os.path.realpath(found)), "share")


def parse_typed(spec):
    """"SECONDS:TEXT" -> (seconds, text), refusing keys KEYS cannot send."""
    seconds, sep, text = spec.partition(":")
    if not sep:
        raise ValueError("--type wants SECONDS:TEXT, not %r" % spec)
    for ch in text:
        if ch not in KEYS:
            raise ValueError("--type cannot send %r" % ch)
    return float(seconds), text


def parse_keys(spec):
    """"SECONDS:TEXT" -> (seconds, text, False): typed without Enter."""
    seconds, text = parse_typed(spec)
    return seconds, text, False


def build_args(mode, image, outdir, qmp_port, firmware_dir, esp=None,
               hd1=None, qemu="qemu-system-i386", boot_hd1=False, nic=None,
               ssh_port=None, keep_hd0=False):
    if boot_hd1 and hd1 is None:
        raise ValueError("boot_hd1 needs an hd1 image")
    if ssh_port is not None and nic is None:
        raise ValueError("ssh_port needs a nic")
    # --keep-hd0 drops the global -snapshot and snapshots the others
    # drive by drive, so only hd0 is written.
    hd0_opt = ",snapshot=off" if keep_hd0 else ""
    snap = ",snapshot=on" if keep_hd0 else ""
    if boot_hd1:
        # bootindex puts hd1 first in both firmwares' boot order; SeaBIOS
        # then gives it drive 0x80, the drive boot0 reads.
        disks = ["-drive", "id=hd0,file=%s,format=raw,if=none%s"
                 % (image, hd0_opt),
                 "-device", "ide-hd,drive=hd0,bus=ide.0,unit=0,bootindex=1",
                 "-drive", "id=hd1,file=%s,format=raw,if=none%s"
                 % (hd1, snap),
                 "-device", "ide-hd,drive=hd1,bus=ide.0,unit=1,bootindex=0"]
    else:
        disks = ["-drive",
                 "file=%s,format=raw,if=ide,index=0,media=disk%s"
                 % (image, hd0_opt)]
    args = [qemu, "-M", "pc", "-m", "256", "-nodefaults", "-vga", "cirrus",
            "-display", "none"] + ([] if keep_hd0 else ["-snapshot"]) +         disks + [
            "-serial", "file:%s" % os.path.join(outdir, "console.log"),
            "-serial", "file:%s" % os.path.join(outdir, "kernel.log"),
            "-rtc", "base=%s" % qemu_shot.RTC_BASE,
            "-qmp", "tcp:127.0.0.1:%d,server=on,wait=off" % qmp_port]
    if mode == "uefi":
        # Nehalem: QEMU's default CPU model lacks features edk2 asserts on.
        # disable_s3: stops edk2 reserving low ACPI NVS for S3 resume, which
        # would cap the contiguous memory the kernel is given.
        args += ["-cpu", "Nehalem", "-global", "PIIX4_PM.disable_s3=1",
                 "-drive", "if=pflash,format=raw,unit=0,readonly=on,file=%s"
                 % os.path.join(firmware_dir, "edk2-i386-code.fd"),
                 "-drive", "if=pflash,format=raw,unit=1,file=%s"
                 % os.path.join(outdir, "edk2-i386-vars.fd")]
    elif mode == "bios":
        args += ["-cpu", "pentium"]
        if not boot_hd1:
            args += ["-boot", "order=c"]
    else:
        raise ValueError("mode must be bios or uefi, not %r" % mode)
    if esp is not None:
        args += ["-drive", "id=esp,file=%s,format=raw,if=none%s"
                 % (esp, snap),
                 "-device", "virtio-blk-pci,drive=esp"]
    if hd1 is not None and not boot_hd1:
        args += ["-drive",
                 "file=%s,format=raw,if=ide,index=1,media=disk%s"
                 % (hd1, snap)]
    if nic is not None:
        netdev = "user,id=n0"
        if ssh_port is not None:
            netdev += ",hostfwd=tcp:127.0.0.1:%d-:22" % ssh_port
        args += ["-netdev", netdev,
                 "-device", "%s,netdev=n0,addr=03.0" % nic]
    return args


def run(mode, image, outdir, at_points, firmware_dir, esp=None, hd1=None,
        typed=(), boot_hd1=False, nic=None, ssh_port=None, keep_hd0=False):
    for path in (image, esp, hd1):
        if path is not None:
            if not os.path.exists(path):
                raise SystemExit("no such image: %s" % path)
            refuse_masters(path)
    if keep_hd0:
        check_keepable(image)
        for other in (esp, hd1):
            if other is not None and os.path.samefile(other, image):
                raise SystemExit("refusing to keep writes to %s: it is "
                                 "also another drive" % image)
    os.makedirs(outdir, exist_ok=True)
    if mode == "uefi":
        shutil.copyfile(os.path.join(firmware_dir, "edk2-i386-vars.fd"),
                        os.path.join(outdir, "edk2-i386-vars.fd"))
    port = qemu_shot.find_free_port()
    stderr_path = os.path.join(outdir, "qemu-stderr.log")
    proc = None
    qmp = None
    try:
        stderr_f = open(stderr_path, "wb")
        try:
            proc = subprocess.Popen(
                build_args(mode, image, outdir, port, firmware_dir, esp=esp,
                           hd1=hd1, boot_hd1=boot_hd1, nic=nic,
                           ssh_port=ssh_port, keep_hd0=keep_hd0),
                stdout=subprocess.DEVNULL, stderr=stderr_f)
        finally:
            stderr_f.close()
        start = time.monotonic()
        try:
            qmp = qemu_shot.QMP("127.0.0.1", port)
        except RuntimeError as e:
            raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
        events = sorted([(t, None) for t in at_points] + list(typed),
                        key=lambda e: e[0])
        for event in events:
            t, text = event[0], event[1]
            remaining = t - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)
            try:
                if text is not None:
                    enter = len(event) < 3 or event[2]
                    _type(qmp, text, enter)
                    print("typed %r%s at %ss" % (text, "" if enter else
                          " (no Enter)", qemu_shot.fmt_seconds(t)))
                    continue
                ppm = os.path.join(outdir, "_shot.ppm")
                qmp.execute("screendump", filename=ppm)
                with open(ppm, "rb") as f:
                    w, h, _, pixels = qemu_shot.parse_ppm(f.read())
                os.remove(ppm)
            except (OSError, RuntimeError) as e:
                raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
            png = os.path.join(outdir,
                               "shot-%ss.png" % qemu_shot.fmt_seconds(t))
            qemu_shot.write_png(png, w, h, pixels)
            print("wrote %s" % png)
    finally:
        if qmp is not None:
            try:
                qmp.execute("quit")
            except Exception:
                pass
            qmp.close()
        if proc is not None:
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    print("console: %s" % os.path.join(outdir, "console.log"))
    print("kernel:  %s" % os.path.join(outdir, "kernel.log"))


def _type(qmp, text, enter=True):
    for ch in text + ("\n" if enter else ""):
        qmp.execute("send-key", keys=[{"type": "qcode", "data": code}
                                      for code in KEYS[ch]])
        time.sleep(0.05)


def _qemu_failure_message(proc, stderr_path, error):
    status = proc.poll()
    if status is not None:
        return ("QEMU exited with status %s during the boot; its stderr "
                "is in %s" % (status, stderr_path))
    return ("lost the QMP connection (%s) while QEMU was still running; "
            "its stderr is in %s" % (error, stderr_path))


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("mode", choices=("bios", "uefi"))
    p.add_argument("image")
    p.add_argument("outdir")
    p.add_argument("--esp", default=None)
    p.add_argument("--hd1", default=None)
    p.add_argument("--boot-hd1", action="store_true")
    p.add_argument("--keep-hd0", action="store_true",
                   help="let IMAGE, a throwaway install target, keep writes")
    p.add_argument("--nic", default=None, metavar="MODEL")
    p.add_argument("--ssh-port", type=int, default=None)
    p.add_argument("--type", dest="typed", action="append", default=[],
                   type=parse_typed, metavar="SECONDS:TEXT")
    p.add_argument("--keys", dest="keys", action="append", default=[],
                   type=parse_keys, metavar="SECONDS:TEXT")
    p.add_argument("--at", default=DEFAULT_AT,
                   help="comma-separated screenshot times in seconds")
    p.add_argument("--firmware-dir", default=None)
    a = p.parse_args(argv[1:])
    at_points = [float(x) for x in a.at.split(",") if x]
    firmware_dir = a.firmware_dir or default_firmware_dir("qemu-system-i386")
    run(a.mode, a.image, a.outdir, at_points, firmware_dir, esp=a.esp,
        hd1=a.hd1, typed=a.typed + a.keys, boot_hd1=a.boot_hd1, nic=a.nic,
        ssh_port=a.ssh_port, keep_hd0=a.keep_hd0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
