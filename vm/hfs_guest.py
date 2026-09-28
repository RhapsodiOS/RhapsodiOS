"""Boot the i386 guest against an HFS volume and check what it did.

An HFS test needs three IDE disks: the per-session root image (index 0, the
RHAP_TEST_IMAGE that guest-console.Guest boots), the HFS volume under test
(index 1) and a small UFS results disk (index 2).  The block device of a
disk's live partition cannot be opened (bsd/dev/ata_hd_registry.m returns
nil for it), so the HFS volume sits in partition a behind a NeXT disk label
copied from the installation floppy.

The results disk carries run.sh, the i386 mount_hfs and the mount point h.
The guest mounts it at /mnt, runs /mnt/run.sh and leaves out.txt, list.txt
and sums.txt on it; the host reads them back with rhap_image after qemu exits.

Usage:
    python hfs_guest.py build FLAVOUR OUT_IMG      hfs, hfsplus or wrapped
    python hfs_guest.py toast OUT_IMG              the devtools.toast HFS volume
    python hfs_guest.py check IMG                  consistency-check a labelled image
    python hfs_guest.py run MODE OUTDIR HFS_IMG MOUNT_HFS [--before BEFORE_IMG]
        MODE: toast (read-only mount of the toast volume), read, write, reread
"""

import importlib.util
import os
import sys
import time
import struct
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools", "hfsimg"))

import rhap_image           # noqa: E402
import ufs_build            # noqa: E402
import ufs_extract          # noqa: E402
import builder              # noqa: E402
import check as hfscheck    # noqa: E402
import content              # noqa: E402
import scenario             # noqa: E402
import volume               # noqa: E402

# The floppy template and devtools.toast are untracked, so a worktree has
# neither; RHAP_VM_ASSETS points at the vm/ directory that does.
ASSETS = os.environ.get("RHAP_VM_ASSETS") or HERE
TEMPLATE = os.path.join(ASSETS, "install", "rhapsody_dr2_x86_InstallationFloppy.img")
TOAST = os.path.join(ASSETS, "devtools.toast")
TOAST_PART = (968, 1324080)         # Apple_HFS partition: first sector, sectors
HFS_DEV = "/dev/hd1a"
RESULTS_DEV = "/dev/hd2a"
HD_MAJOR = 3        # block major of the hd disks
VOLUME_SIZE = 40 * 1024 * 1024
TOAST_SAMPLE_MAX = 2 * 1024 * 1024


LABEL_SECSIZE = 92          # dl_secsize, int
LABEL_FRONT = 112           # dl_front, short, in dl_secsize units


def label_front():
    """Byte offset of partition a in a disk built from the floppy's label."""
    with rhap_image.Image(TEMPLATE) as img:
        return img.part_start


def wrap_label(hfs):
    """A disk image: the floppy's label area, relabelled for 512-byte
    sectors, then `hfs` as partition a.

    HFS addresses the device in 512-byte blocks (hfs_mountfs sets
    hfs_phys_block_size to 512), and a partition's block size is the label's
    dl_secsize (IODiskPartition.m _initPartition).  The floppy's label says
    1024, so every copy is rewritten to 512 with dl_front doubled, which
    leaves partition a at the same byte offset."""
    part = label_front()
    if len(hfs) % 512:
        raise ValueError("volume is not a whole number of 512-byte sectors")
    with open(TEMPLATE, "rb") as f:
        image = bytearray(f.read(part))
    found = 0
    for off in range(0, part, 512):
        if image[off:off + 4] != ufs_build.LABEL_MAGIC:
            continue
        secsize = struct.unpack_from(">i", image, off + LABEL_SECSIZE)[0]
        front = struct.unpack_from(">h", image, off + LABEL_FRONT)[0]
        struct.pack_into(">i", image, off + LABEL_SECSIZE, 512)
        struct.pack_into(">h", image, off + LABEL_FRONT, front * secsize // 512)
        found += 1
    if not found:
        raise ValueError("no NeXT label in the template")
    image += hfs
    ufs_build.patch_labels(image, part, len(hfs) // 512)
    return bytes(image)


def open_volume(path):
    return volume.Volume(path, label_front())


def build_image(flavour, out):
    hfs = builder.BUILDERS[flavour](scenario.base_manifest(), VOLUME_SIZE)
    with open(out, "wb") as f:
        f.write(wrap_label(hfs))


def toast_image(out):
    first, count = TOAST_PART
    with open(TOAST, "rb") as f:
        f.seek(first * 512)
        hfs = f.read(count * 512)
    with open(out, "wb") as f:
        f.write(wrap_label(hfs))


def results_disk(path, script, mount_hfs):
    N = ufs_extract.Node
    with open(mount_hfs, "rb") as f:
        binary = f.read()
    nodes = [N("/", "dir", 0o40755, 0, 0, 0, None),
             N("/h", "dir", 0o40755, 0, 0, 0, None),
             N("/mount_hfs", "reg", 0o100755, 0, 0, 0, binary),
             N("/run.sh", "reg", 0o100644, 0, 0, 0, script.encode("utf-8"))]
    with open(path, "wb") as f:
        f.write(ufs_build.build(TEMPLATE, nodes))


def read_results(path):
    out = {}
    with rhap_image.Image(path) as img:
        for name in ("out.txt", "list.txt", "sums.txt"):
            ino = img.resolve("/" + name)
            out[name] = None if ino is None else \
                img.read_file(img.inode(ino)).decode("utf-8", "replace")
    return out


def _guest_console():
    spec = importlib.util.spec_from_file_location(
        "guest_console", os.path.join(HERE, "guest-console.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def boot(outdir, hfs_img, results_img, timeout):
    """Boot single-user, run /mnt/run.sh, wait for END or the timeout."""
    gc = _guest_console()
    drive = "file=%s,format=raw,if=ide,index=%d,media=disk,snapshot=off"
    # a QMP port of its own: guest-console's default (4481) is shared by
    # every other session that boots a guest
    port = int(os.environ.get("RHAP_QMP_PORT", "4493"))
    g = gc.Guest(outdir, port=port, extra=("-drive", drive % (hfs_img, 1),
                                           "-drive", drive % (results_img, 2)))
    try:
        time.sleep(6)
        g.line("-s")
        time.sleep(135)
        # golden.img's /dev has nodes for hd0 and hd1 only; the results
        # disk is the third IDE disk, so make its node (8 minors per unit)
        g.line("mount -uw /")
        time.sleep(5)
        g.line("mknod %s b %d %d" % (RESULTS_DEV, HD_MAJOR, 2 * 8))
        time.sleep(3)
        g.line("mount %s /mnt" % RESULTS_DEV)
        time.sleep(5)
        g.line("sh /mnt/run.sh")
        deadline = time.time() + timeout
        while time.time() < deadline:
            time.sleep(15)
            try:
                r = read_results(results_img)
            except Exception:
                continue
            if r["out.txt"] and "END" in r["out.txt"].split():
                break
        g.shot("end")
    finally:
        g.close()
    return read_results(results_img)


def nfc(s):
    return unicodedata.normalize("NFC", s)


def expectation(mode, hfs_img):
    """(expected tree, content name function, cksum sample or None, script)."""
    if mode == "toast":
        with open_volume(hfs_img) as v:
            walk = v.walk()
        expected = dict((p[1:], None if e.is_dir else e.data.logical_size)
                        for p, e in walk if "\x00" not in p)
        sample = sorted(p for p, s in expected.items()
                        if s is not None and s <= TOAST_SAMPLE_MAX)
        return expected, None, sample, scenario.read_script(HFS_DEV, read_only=True, sample=sample)
    if mode == "read":
        expected = scenario.tree(scenario.base_manifest())
        return expected, scenario.content_name, None, scenario.read_script(HFS_DEV)
    if mode == "reread":
        expected = scenario.expected_after_write(scenario.base_manifest())
        return expected, scenario.content_name, None, scenario.read_script(HFS_DEV)
    if mode == "write":
        expected = scenario.expected_after_write(scenario.base_manifest())
        return expected, scenario.content_name, None, scenario.write_script(HFS_DEV)
    raise ValueError("mode must be toast, read, reread or write")


def verify(mode, outdir, hfs_img, results, before=None):
    """Every problem with a finished run, as a list of strings."""
    expected, name_of, sample, _ = expectation(mode, hfs_img)
    expected = dict((nfc(p), s) for p, s in expected.items())
    problems = []
    out = results["out.txt"] or ""
    for want in ("mount rc=0", "report done", "umount rc=0", "END"):
        if want not in out:
            problems.append("guest never reported %r; out.txt: %r" % (want, out))
    serial_log = os.path.join(outdir, "serial.log")
    if os.path.exists(serial_log):
        with open(serial_log, "rb") as f:
            serial = f.read().decode("latin-1")
        for line in serial.splitlines():
            if "panic" in line or line.startswith("hfs: "):
                problems.append("serial: " + line)
    listed = set(nfc(p) for p in scenario.parse_list(results["list.txt"] or ""))
    listed = set(p for p in listed if "HFS+ Private Data" not in p)
    if listed != set(expected):
        problems.append("guest listing differs: missing %s, unexpected %s"
                        % (sorted(set(expected) - listed)[:10], sorted(listed - set(expected))[:10]))
    sums = dict((nfc(p), v) for p, v in scenario.parse_sums(results["sums.txt"] or "").items())
    with open_volume(hfs_img) as v:
        walk = [(nfc(p[1:]), e) for p, e in v.walk()]
        if mode == "toast":
            files = dict((p, e) for p, e in walk if not e.is_dir)
            if set(sums) != set(sample):
                problems.append("guest checksummed %d files, expected %d" % (len(sums), len(sample)))
            for p, (crc, size) in sums.items():
                data = v.read_file(files[p]) if p in files else b""
                if (content.cksum(data), len(data)) != (crc, size):
                    problems.append("guest cksum of %s differs from the host's" % p)
            return problems
        want = scenario.expected_sums(expected, name_of)
        if sums != want:
            bad = sorted(p for p in set(sums) | set(want) if sums.get(p) != want.get(p))
            problems.append("guest checksums differ for %s" % bad[:10])
        problems += ["image: " + p for p in hfscheck.check(v)]
        got = dict((p, None if e.is_dir else e.data.logical_size) for p, e in walk)
        if got != expected:
            bad = sorted(p for p in set(got) | set(expected) if got.get(p, -1) != expected.get(p, -1))
            problems.append("image tree differs from the expected one at %s" % bad[:10])
        for p, e in walk:
            if not e.is_dir and p in expected and \
                    v.read_file(e) != content.data(name_of(p), e.data.logical_size):
                problems.append("image contents of %s are wrong" % p)
    if before is not None:
        problems += compare_wrapper(before, hfs_img)
    return problems


def compare_wrapper(before, after):
    """A wrapped volume's HFS wrapper must come through untouched."""
    part = label_front()
    out = []
    with open(before, "rb") as a, open(after, "rb") as b:
        a.seek(part + 1024)
        b.seek(part + 1024)
        if a.read(512) != b.read(512):
            out.append("wrapper MDB changed")
        a.seek(-1024, 2)
        b.seek(-1024, 2)
        if a.read(512) != b.read(512):
            out.append("alternate wrapper MDB changed")
    return out


def run(mode, outdir, hfs_img, mount_hfs, before=None, timeout=1800):
    os.makedirs(outdir, exist_ok=True)
    results_img = os.path.join(outdir, "results.img")
    script = expectation(mode, hfs_img)[3]
    results_disk(results_img, script, mount_hfs)
    results = boot(outdir, hfs_img, results_img, timeout)
    problems = verify(mode, outdir, hfs_img, results, before)
    for p in problems:
        print("FAIL: " + p)
    print("PASS" if not problems else "FAILED: %d problems" % len(problems))
    return 0 if not problems else 1


def main(argv):
    if len(argv) >= 4 and argv[1] == "build":
        build_image(argv[2], argv[3])
        return 0
    if len(argv) == 3 and argv[1] == "toast":
        toast_image(argv[2])
        return 0
    if len(argv) == 3 and argv[1] == "check":
        with open_volume(argv[2]) as v:
            problems = hfscheck.check(v)
        for p in problems:
            print(p)
        print("%d problems" % len(problems))
        return 1 if problems else 0
    if len(argv) >= 6 and argv[1] == "run":
        before = argv[argv.index("--before") + 1] if "--before" in argv else None
        return run(argv[2], argv[3], argv[4], argv[5], before)
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
