#!/usr/bin/env python3
"""Boot a disk image under QEMU and capture its consoles and screen.

    python vm/qemu_boot.py {bios,uefi} IMAGE OUTDIR [--esp ESP_IMAGE]
                           [--at SECONDS[,SECONDS...]] [--firmware-dir DIR]

bios boots QEMU's own SeaBIOS.  uefi boots the IA32 edk2 firmware QEMU ships
as share/edk2-i386-code.fd, so no OVMF build is needed.  IMAGE is the first
IDE disk (i440FX/PIIX3, the controller the EIDE boot driver probes); --esp
adds a virtio disk for the two-disk layout, whose loader sits on an
ESP-only disk.

OUTDIR gets console.log (COM1: firmware and loader), kernel.log (COM2: the
kernel's serial console) and shot-<N>s.png screenshots.  QEMU quits after
the last --at time.

Every drive is opened with -snapshot, so no boot ever writes an image, and
any path named golden.img or rhapsody.vmdk is refused outright, wherever it
lives (so the main checkout's masters are refused from a worktree too).
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
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_MASTERS = ("golden.img", "rhapsody.vmdk")
DEFAULT_AT = "60,120,180"


def _load_qemu_shot():
    spec = importlib.util.spec_from_file_location(
        "qemu_shot", os.path.join(_HERE, "qemu-shot.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


qemu_shot = _load_qemu_shot()


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


def default_firmware_dir(qemu):
    found = shutil.which(qemu)
    if found is None:
        raise SystemExit("%s is not on PATH" % qemu)
    return os.path.join(os.path.dirname(os.path.realpath(found)), "share")


def build_args(mode, image, outdir, qmp_port, firmware_dir, esp=None,
               qemu="qemu-system-i386"):
    args = [qemu, "-M", "pc", "-m", "256", "-nodefaults", "-vga", "cirrus",
            "-display", "none", "-snapshot",
            "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % image,
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
        args += ["-cpu", "pentium", "-boot", "order=c"]
    else:
        raise ValueError("mode must be bios or uefi, not %r" % mode)
    if esp is not None:
        args += ["-drive", "id=esp,file=%s,format=raw,if=none" % esp,
                 "-device", "virtio-blk-pci,drive=esp"]
    return args


def run(mode, image, outdir, at_points, firmware_dir, esp=None):
    for path in (image, esp):
        if path is not None:
            if not os.path.exists(path):
                raise SystemExit("no such image: %s" % path)
            refuse_masters(path)
    os.makedirs(outdir, exist_ok=True)
    if mode == "uefi":
        shutil.copyfile(os.path.join(firmware_dir, "edk2-i386-vars.fd"),
                        os.path.join(outdir, "edk2-i386-vars.fd"))
    port = qemu_shot.find_free_port()
    stderr_path = os.path.join(outdir, "qemu-stderr.log")
    stderr_f = open(stderr_path, "wb")
    proc = subprocess.Popen(
        build_args(mode, image, outdir, port, firmware_dir, esp=esp),
        stdout=subprocess.DEVNULL, stderr=stderr_f)
    start = time.monotonic()
    qmp = None
    try:
        try:
            qmp = qemu_shot.QMP("127.0.0.1", port)
        except RuntimeError as e:
            raise SystemExit(_qemu_failure_message(proc, stderr_path, e))
        for t in sorted(at_points):
            remaining = t - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)
            ppm = os.path.join(outdir, "_shot.ppm")
            try:
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
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5)
        stderr_f.close()
    print("console: %s" % os.path.join(outdir, "console.log"))
    print("kernel:  %s" % os.path.join(outdir, "kernel.log"))


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
    p.add_argument("--at", default=DEFAULT_AT,
                   help="comma-separated screenshot times in seconds")
    p.add_argument("--firmware-dir", default=None)
    a = p.parse_args(argv[1:])
    at_points = [float(x) for x in a.at.split(",") if x]
    firmware_dir = a.firmware_dir or default_firmware_dir("qemu-system-i386")
    run(a.mode, a.image, a.outdir, at_points, firmware_dir, esp=a.esp)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
