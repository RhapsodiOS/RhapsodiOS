"""Boot-test drvIntelE100 under QEMU, on images of its own.

usage: python e100-boot.py BUNDLE MODEL MODE [PORT]

BUNDLE  an IntelE100.config directory, or the intele100 .apk holding one
MODEL   a QEMU eepro100 model (i82557b, i82559er, i82801, i82551, ...), or
        ne2k_pci for the negative check
MODE    probe   boot -s and stop at the shell: identification only
        single  boot -s, bring en0 up by hand and ping QEMU's gateway
        multi   boot normally, answer the network prompt, reach the
                Setup Assistant
PORT    QMP port, default 4510

golden.img and the rebuilt kernel come from E100_GOLDEN and E100_KERNEL
(default: golden.img and install/mach_kernel beside this script), so this
runs from a git worktree that has neither. Everything it writes lands under
this checkout's work/: e100-base.img, one e100-MODEL-MODE.img per run, and
e100-MODEL-MODE/ with serial.log, e100.pcap and the screenshots.
work/test.img is written only as graft-kernel.py's staging target - the
one image that tool will write - and nothing boots it.

Exits 1 if the serial log shows a panic, or if a single run's capture
lacks frames in either direction.
"""
import glob
import hashlib
import importlib.util
import os
import shutil
import sys
import tarfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rhap_image  # noqa: E402
import ufs_alloc  # noqa: E402

GOLDEN = os.environ.get("E100_GOLDEN", os.path.join(HERE, "golden.img"))
KERNEL = os.environ.get("E100_KERNEL",
                        os.path.join(HERE, "install", "mach_kernel"))
SHELL_WAIT = int(os.environ.get("E100_SHELL_WAIT", "110"))
WORK = os.path.join(HERE, "work")
MAC = "52:54:00:12:34:56"
GATEWAY = "10.0.2.2"


def load(name, filename):
    spec = importlib.util.spec_from_file_location(
        name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bundle_dir(path):
    if os.path.isdir(path):
        return os.path.abspath(path)
    dest = os.path.join(WORK, "e100-bundle")
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    with tarfile.open(path, "r:gz", ignore_zeros=True) as apk:
        apk.extractall(dest, filter="data")
    hits = glob.glob(os.path.join(dest, "**", "IntelE100.config"),
                     recursive=True)
    if len(hits) != 1:
        sys.exit("expected one IntelE100.config in %s, found %r" % (path, hits))
    return hits[0]


def read_file(image, path):
    with rhap_image.Image(image) as img:
        ino = img.resolve(path)
        if ino is None:
            sys.exit("%s has no %s" % (image, path))
        return img.read_file(ino)


def base_image():
    base = os.path.join(WORK, "e100-base.img")
    staging = os.path.join(WORK, "test.img")
    os.makedirs(WORK, exist_ok=True)
    load("graft_kernel", "graft-kernel.py").graft_kernel(GOLDEN, KERNEL,
                                                         staging)
    shutil.copyfile(staging, base)
    with open(KERNEL, "rb") as f:
        want = hashlib.sha256(f.read()).hexdigest()
    if hashlib.sha256(read_file(base, "/mach_kernel")).hexdigest() != want:
        sys.exit("the kernel in %s is not %s" % (base, KERNEL))
    return base


def install(base, bundle, image):
    """install-driver.py's steps without its `cp -c` clone, which GNU cp
    on this host rejects: copy, add the bundle, list it as a boot driver."""
    shutil.copyfile(base, image)
    inst = load("install_driver", "install-driver.py")
    name = inst._driver_name(bundle)
    with ufs_alloc.Allocator(image, writable=True) as a:
        a.validate()
        inst._install_bundle(a, "/private/Drivers/i386/%s.config" % name,
                             bundle)
        a.flush()
    print("  installed %s; Boot Drivers: %s"
          % (name, inst._add_boot_driver(image, name)))


def boot(image, model, mode, port):
    out = os.path.join(WORK, "e100-%s-%s" % (model, mode))
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    pcap = os.path.join(out, "e100.pcap").replace("\\", "/")
    nic = model if model == "ne2k_pci" else "%s,addr=03.0,mac=%s" % (model, MAC)
    gc = load("guest_console", "guest-console.py")
    g = gc.Guest(out, port=port, image=image, nic=nic,
                 extra=("-object",
                        "filter-dump,id=f0,netdev=n0,file=%s" % pcap))
    try:
        time.sleep(6)
        if mode == "multi":
            g.line("mach_kernel")
            time.sleep(105)
            g.shot("t105")
            g.line("y")
            time.sleep(40)
            g.shot("t145")
        else:
            g.line("-s")
            time.sleep(SHELL_WAIT)
            g.shot("shell")
            if mode == "single":
                g.line("ifconfig en0 10.0.2.15 netmask 255.255.255.0 up")
                time.sleep(8)
                g.shot("ifconfig")
                g.line("ping -c 3 " + GATEWAY)
                time.sleep(12)
                g.shot("ping")
                g.line("netstat -in")
                time.sleep(3)
                g.shot("netstat")
                time.sleep(20)  # two more statistics harvests reach the log
    finally:
        g.close()
    return out, pcap


def report(out, pcap, model, mode):
    with open(os.path.join(out, "serial.log"), "rb") as f:
        serial = f.read().decode("latin-1").splitlines()
    ours = [line for line in serial if "IntelE100" in line]
    print("--- IntelE100 lines in serial.log (%d) ---" % len(ours))
    print("\n".join(ours) if ours else "(none)")
    ok = True
    panics = [line for line in serial if "panic" in line.lower()]
    if panics:
        print("--- PANIC ---")
        print("\n".join(panics))
        ok = False
    if model != "ne2k_pci" and os.path.exists(pcap):
        s = load("e100_pcap", "e100-pcap.py").summarize(pcap, MAC)
        print("--- capture ---")
        for key in sorted(s):
            print("%s %d" % (key, s[key]))
        if mode == "single" and not (s["from_guest"] and s["to_guest"]):
            print("FAIL: no frames in one direction")
            ok = False
    print("logs and screenshots: %s" % out)
    return ok


def main(argv):
    if len(argv) not in (4, 5) or argv[3] not in ("probe", "single", "multi"):
        print(__doc__, file=sys.stderr)
        return 2
    bundle = bundle_dir(argv[1])
    model, mode = argv[2], argv[3]
    port = int(argv[4]) if len(argv) == 5 else 4510
    image = os.path.join(WORK, "e100-%s-%s.img" % (model, mode))
    install(base_image(), bundle, image)
    out, pcap = boot(image, model, mode, port)
    return 0 if report(out, pcap, model, mode) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
