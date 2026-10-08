"""Build the hard-disk install media, a pre-installed disk, or the installer
CD, from apks.

    python -m instmedia.build --repo DIR --efi BOOTIA32.EFI --out IMAGE
                              [--preinstalled] [--fs-mb N] [--form disk|cd]

DIR is a flat directory of apks (instmedia.collect makes one).  The image
is staged in memory and read back before it is kept: readback.diff against
the node tree and ufs_check.check on the allocation accounting must both be
clean.  Refused, with every problem listed: paths two packages both claim,
a root missing a file its boot needs, and /dev nodes whose majors disagree
with the kernel's.

--form cd writes an ISO 9660 image instead (2048-byte sectors):

    0-15        the system area: the CD label at bytes 0 and 7680 (and the
                rest of label.CD_COPIES), secsize 2048
    16-21       volume descriptors, path tables, root directory (iso.py)
    22...       BOOT.CAT, README.TXT, BIOSBOOT.IMG (the El Torito hard-disk
                image hdimage.boot_image writes: the kernel, sarld, the Boot
                Drivers and the CD's tables), EFIBOOT.IMG (the ESP)
    start       the live root's UFS, fsize 2048, from the first 32-sector
                boundary after EFIBOOT.IMG to the end of the disc
"""
import argparse
import os
import posixpath
import re
import shutil
import sys
import tempfile

import ufs_check
from instmedia import (apkrepo, hdimage, iso, label, live, readback, rootfs,
                       space, testconfig, ufs, ufs_geometry)

BOOTERS = "/usr/standalone/i386"
DRIVERS = "/private/Drivers/i386"
# driverLoader, which loads the Active Drivers at startup, and sysinstall and
# driverDetect on the media, read the drivers through /usr/Devices, which
# files links to ../private/Devices.
DEVICES_TABLE = "/usr/Devices/System.config/Instance0.table"
# The Active Driver dhcpcd's /dev/bpf* come from; without it the network
# never comes up, and nothing says why.
BPF_DRIVER = "/private/Drivers/i386/BPF.config/BPF_reloc"
# What rc.cdrom starts, and the tools sysinstall runs in the live root.
CDIS_NEEDS = [live.RC_CDROM, live.CDIS + "/sysinstall",
              live.SETS + "/base.set", "/sbin/disk", "/sbin/mount",
              "/sbin/umount", "/sbin/apk", "/usr/sbin/chroot",
              "/usr/sbin/driverDetect", "/usr/sbin/pwd_mkdb",
              "/usr/bin/gzip", "/bin/sync"]
# The majors /dev must use for each disk family: sd from the kernel's own
# tables (src/kernel-7/bsd/dev/i386/conf.c: bdevsw 6, cdevsw 14), hd and fd
# from the "Block Major"/"Character Major" the EIDE and Floppy drivers
# register (drvEIDE and drvPCFloppy Default.table).  A node's family is its
# name without the raw device's leading "r" (hd0a, rhd0a, and controllers
# such as fdc0), and its kind picks the major.  console/null/zero/random
# come from conf.c.
DEV_MAJORS = {"hd": {"blk": 3, "chr": 15}, "sd": {"blk": 6, "chr": 14},
              "fd": {"blk": 1, "chr": 41}}
DEV_EXACT = {"console": ("chr", 0), "null": ("chr", 3), "zero": ("chr", 3),
             "random": ("chr", 17), "urandom": ("chr", 17)}
LIVE_HEADROOM = 32 * 1024 * 1024
# The installed system makes a swapfile, host keys and logs on first boot.
PREINSTALLED_HEADROOM = 512 * 1024 * 1024
# What a 650 MB CD-R holds.
CD_LIMIT = 681574400
# The live UFS on the CD: 2048-byte sectors and fragments, laid out like the
# DR2 CD's (sample.cd_volume), starting on a 64 KB boundary.
CD_NSECT, CD_NTRAK, CD_RPM = 64, 32, 300
CD_ALIGN = 32
# The label's d_front is a short and cannot reach past EFIBOOT.IMG, so the
# front porch is the ISO system area the label copies sit in, and p_base
# carries the rest of the way to the UFS.
CD_FRONT = 16
CD_VOLUME_ID = "RHAPSODIOS"
VERSION_FILE = "/System/Library/CoreServices/software_version"


class BuildError(Exception):
    pass


def boot_drivers(table):
    m = re.search(rb'"Boot Drivers"\s*=\s*"([^"]*)"', table)
    if m is None:
        raise BuildError("Instance0.table has no Boot Drivers")
    return m.group(1).decode("ascii").split()


def check_tree(nodes, preinstalled):
    """What the booters, the kernel and the image's startup need that the
    root lacks: every Boot Driver (the network card is one); CDIS's pieces
    on the media; sshd and driverLoader on the pre-installed disk; the
    /usr/Devices path on both."""
    by_path = {n.path: n for n in nodes}
    table = by_path[live.SYSTEM_TABLE].data
    need = ["/mach_kernel", BOOTERS + "/boot0", BOOTERS + "/boot1",
            BOOTERS + "/boot", BOOTERS + "/sarld"]
    need += ["%s/%s.config/%s_reloc" % (DRIVERS, name, name)
             for name in boot_drivers(table)]
    if preinstalled:
        need += ["/usr/sbin/sshd", "/sbin/mount", "/usr/libexec/getty",
                 "/usr/sbin/driverLoader", BPF_DRIVER]
    else:
        need += CDIS_NEEDS
    problems = ["missing %s" % p for p in need if p not in by_path]
    tree = rootfs.Tree()
    for n in nodes[1:]:
        tree.put(n)
    try:
        real = tree.resolve(DEVICES_TABLE)
    except rootfs.TreeError as e:
        real = str(e)
    if real != live.SYSTEM_TABLE:
        problems.append("%s does not lead to %s (%s)"
                        % (DEVICES_TABLE, live.SYSTEM_TABLE, real))
    return problems


def check_sets(apks, sets):
    """Packages the sets name that the repository lacks, and repository
    packages no set names (they would not be on the media)."""
    problems = ["set %s names package %s not in the repository" % (s, p)
                for s in sorted(sets) for p in sets[s] if p not in apks]
    named = {p for pkgs in sets.values() for p in pkgs}
    problems += ["package %s is in no set" % p
                 for p in sorted(apks) if p not in named]
    return problems


def check_dev(nodes):
    """/dev nodes whose kind or major the kernel would not agree with."""
    problems = []
    for n in nodes:
        if not n.path.startswith("/private/dev/") or n.kind not in (
                "chr", "blk"):
            continue
        name = n.path.rsplit("/", 1)[1]
        want = DEV_EXACT.get(name)
        if want is None:
            family = DEV_MAJORS.get(
                (name[1:] if name.startswith("r") else name)[:2])
            want = (n.kind, family[n.kind]) if family else None
        if want is not None and (n.kind, n.data[0]) != want:
            problems.append("%s is %s %d, the kernel wants %s %d"
                            % ((n.path, n.kind, n.data[0]) + want))
    return problems


def fs_sectors(nodes, headroom):
    """A filesystem size, in 512-byte sectors, for nodes plus headroom."""
    data = sum(-(-len(n.data) // 1024) * 1024 for n in nodes
               if n.kind == "reg")
    size = max(data * 5 // 4, len(nodes) * 4096 * 2) + headroom
    return -(-size // (1024 * 1024)) * 2048


def release_line(by_path):
    """The release sysinstall's Welcome screen names (release_line() in
    cdis-3/sysinstall.tproj/main.c): software_version's first line, then its
    last in parentheses."""
    node = by_path.get(VERSION_FILE)
    lines = node.data.decode("ascii").splitlines() if node else []
    if len(lines) > 1 and lines[0] and lines[-1]:
        return "%s (%s)" % (lines[0], lines[-1])
    return lines[0] if lines and lines[0] else "RhapsodiOS"


def README_TEXT(release):
    return ("RhapsodiOS installer\nRelease: %s\nBoots on i386 PCs with a "
            "BIOS or IA32 UEFI firmware.\n" % release).encode("ascii")


def boot_tree(nodes):
    """The BIOS boot image's nodes: the kernel, sarld, each Boot Driver's and
    System's config directory from the live root (so the CD's
    Instance0.tables come along), and the directories above them."""
    by_path = {n.path: n for n in nodes}
    names = boot_drivers(by_path[live.SYSTEM_TABLE].data) + ["System"]
    dirs = ["%s/%s.config" % (DRIVERS, name) for name in names]
    keep = {"/"}
    for path in ["/mach_kernel", BOOTERS + "/sarld"] + dirs:
        while path != "/":
            keep.add(path)
            path = posixpath.dirname(path)
    chosen = [n for n in nodes if n.path in keep
              or any(n.path.startswith(d + "/") for d in dirs)]
    paths = {n.path for n in chosen}
    # A hard link whose other name stays behind becomes the file itself.
    return [by_path[n.data]._replace(path=n.path)
            if n.kind == "hlink" and n.data not in paths else n
            for n in chosen]


def check_iso(path, ents):
    """Where iso.read_iso finds the files and boot images, against where
    the layout put them."""
    with open(path, "rb") as f:
        info = iso.read_iso(f)
    want = {e.name: (e.lba, e.size) for e in ents.values()}
    problems = ["ISO lists %s at %r, not %r"
                % (name, info["files"].get(name), want[name])
                for name in sorted(want)
                if info["files"].get(name) != want[name]]
    problems += ["ISO lists %s, not in the layout" % name
                 for name in sorted(info["files"].keys() - want.keys())]
    for got, (what, name) in zip(
            (info["catalog_lba"], info["catalog"][1]["lba"],
             info["catalog"][3]["lba"]),
            (("the boot catalog", "BOOT.CAT"),
             ("the BIOS boot entry", "BIOSBOOT.IMG"),
             ("the EFI boot entry", "EFIBOOT.IMG"))):
        if got != ents[name].lba:
            problems.append("%s is at %d, not %s's %d"
                            % (what, got, name, ents[name].lba))
    return problems


def write_cd(out, esp, nodes, fs_mb):
    """Lay out and write the CD, then read it back; returns (live ufs
    geometry, total 512-byte sectors)."""
    by_path = {n.path: n for n in nodes}
    boot0, boot1, boot2 = (by_path[BOOTERS + "/" + name].data
                           for name in ("boot0", "boot1", "boot"))
    now = max(n.mtime for n in nodes)
    sectors = fs_mb * 2048 if fs_mb else fs_sectors(nodes, LIVE_HEADROOM)
    per = iso.SECTOR // 512
    g = ufs_geometry.geometry(fssize=sectors // per, secsize=iso.SECTOR,
                              nsect=CD_NSECT, ntrak=CD_NTRAK, rpm=CD_RPM,
                              fsize=iso.SECTOR)
    readme = README_TEXT(release_line(by_path))
    files = [("BOOT.CAT", iso.SECTOR), ("README.TXT", len(readme)),
             ("BIOSBOOT.IMG", hdimage.BOOT_IMAGE_SECTORS * 512),
             ("EFIBOOT.IMG", len(esp))]
    ents, end = iso.layout(files, iso.FIRST_LBA)
    start = -(-end // CD_ALIGN) * CD_ALIGN
    total = start + g.fssize
    if total * iso.SECTOR > CD_LIMIT:
        raise BuildError("the disc would be %d MB, more than the %d MB a CD "
                         "holds; the fallback, a live.list subset of the "
                         "packages, is not built yet"
                         % (total * iso.SECTOR >> 20, CD_LIMIT >> 20))
    bnodes = boot_tree(nodes)
    with tempfile.TemporaryDirectory() as tmp:
        boot = os.path.join(tmp, "BIOSBOOT.IMG")
        hdimage.boot_image(boot, fs_sectors(bnodes, 0), boot0, boot1, boot2,
                           bnodes, now)
        problems = readback.diff(boot, bnodes) + ufs_check.check(boot)
        if problems:
            raise BuildError("the boot image does not read back clean:\n"
                             + "\n".join(problems))
        try:
            with open(out, "wb") as f:
                f.truncate(total * iso.SECTOR)
                label.place(f, label.cd_label(g, CD_FRONT, g.fssize,
                                              "RhapsodiOS",
                                              p_base=start - CD_FRONT),
                            label.CD_COPIES)
                iso.write_iso(f, CD_VOLUME_ID, files, ents["BOOT.CAT"].lba,
                              "BIOSBOOT.IMG", "EFIBOOT.IMG", total, now)
                for name, data in (("README.TXT", readme),
                                   ("EFIBOOT.IMG", esp)):
                    f.seek(ents[name].lba * iso.SECTOR)
                    f.write(data)
                f.seek(ents["BIOSBOOT.IMG"].lba * iso.SECTOR)
                with open(boot, "rb") as b:
                    shutil.copyfileobj(b, f)
                ufs.write(f, start * iso.SECTOR, g, nodes, now)
            problems = (readback.diff(out, nodes) + ufs_check.check(out)
                        + check_iso(out, ents))
            if problems:
                raise BuildError("the disc does not read back clean:\n"
                                 + "\n".join(problems))
        except space.NoSpace:
            os.remove(out)
            raise BuildError("%d MB of UFS is too small for this root; pass "
                             "a larger --fs-mb" % (sectors // 2048))
        except BaseException:
            if os.path.exists(out):
                os.remove(out)
            raise
    return g, total * per


def build(repo, efi_path, out, preinstalled=False, fs_mb=None, form="disk"):
    """Returns (apks, nodes, live ufs geometry, total 512-byte sectors)."""
    if form not in ("disk", "cd"):
        raise BuildError("unknown form %r" % form)
    if preinstalled and form == "cd":
        raise BuildError("--preinstalled makes a disk; it cannot be a CD")
    apks = apkrepo.index(repo)
    with open(efi_path, "rb") as f:
        esp = hdimage.esp_image(f.read())
    nodes, conflicts = live.compose(
        apks, esp, preinstalled=preinstalled,
        password_hash=testconfig.TEST_PASSWORD_HASH if preinstalled else None,
        form=form)
    problems = ["%s: claimed by %s and %s" % c for c in conflicts]
    problems += check_tree(nodes, preinstalled) + check_dev(nodes)
    if not preinstalled:
        tree = rootfs.Tree()
        for n in nodes[1:]:
            tree.put(n)
        problems += check_sets(apks, live.read_sets(tree))
    if problems:
        raise BuildError("\n".join(problems))
    if form == "cd":
        g, total = write_cd(out, esp, nodes, fs_mb)
        return len(apks), len(nodes), g, total
    by_path = {n.path: n for n in nodes}
    boot0, boot1, boot2 = (by_path[BOOTERS + "/" + name].data
                           for name in ("boot0", "boot1", "boot"))
    now = max(n.mtime for n in nodes)
    sectors = fs_mb * 2048 if fs_mb else fs_sectors(
        nodes, PREINSTALLED_HEADROOM if preinstalled else LIVE_HEADROOM)
    try:
        g, total = hdimage.write(out, sectors, boot0, boot1, boot2, esp,
                                 nodes, now)
    except space.NoSpace:
        os.remove(out)
        raise BuildError("%d MB of UFS is too small for this root; pass a "
                         "larger --fs-mb" % (sectors // 2048))
    problems = readback.diff(out, nodes) + ufs_check.check(out)
    if problems:
        raise BuildError("the image does not read back clean:\n"
                         + "\n".join(problems))
    return len(apks), len(nodes), g, total


def main(argv):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", required=True)
    p.add_argument("--efi", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--preinstalled", action="store_true")
    p.add_argument("--fs-mb", type=int, default=None)
    p.add_argument("--form", choices=("disk", "cd"), default="disk")
    a = p.parse_args(argv[1:])
    try:
        napks, nnodes, g, total = build(a.repo, a.efi, a.out,
                                        a.preinstalled, a.fs_mb, a.form)
    except (BuildError, apkrepo.RepoError, live.ComposeError,
            rootfs.TreeError, hdimage.ImageError) as e:
        print("instmedia.build: %s" % e, file=sys.stderr)
        return 1
    print("%s: %d apks, %d nodes, %d MB of UFS, %d MB %s"
          % (a.out, napks, nnodes, g.fssize * g.secsize >> 20,
             total // 2048, "disc" if a.form == "cd" else "disk"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
