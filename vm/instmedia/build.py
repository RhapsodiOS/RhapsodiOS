"""Build the hard-disk install media, or a pre-installed disk, from apks.

    python -m instmedia.build --repo DIR --efi BOOTIA32.EFI --out IMAGE
                              [--preinstalled] [--fs-mb N]

DIR is a flat directory of apks (instmedia.collect makes one).  The image
is staged in memory and read back before it is kept: readback.diff against
the node tree and ufs_check.check on the allocation accounting must both be
clean.  Refused, with every problem listed: paths two packages both claim,
a root missing a file its boot needs, and /dev nodes whose majors disagree
with the kernel's.
"""
import argparse
import os
import re
import sys

import ufs_check
from instmedia import (apkrepo, hdimage, live, readback, rootfs, space,
                       testconfig)

BOOTERS = "/usr/standalone/i386"
DRIVERS = "/private/Drivers/i386"
# driverLoader, which loads the Active Drivers at startup, reads the system
# table through /usr/Devices, which files links to ../private/Devices.
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
    on the media; sshd, driverLoader and the /usr/Devices path on the
    pre-installed disk."""
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
    if preinstalled:
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


def build(repo, efi_path, out, preinstalled=False, fs_mb=None):
    apks = apkrepo.index(repo)
    with open(efi_path, "rb") as f:
        esp = hdimage.esp_image(f.read())
    nodes, conflicts = live.compose(
        apks, esp, preinstalled=preinstalled,
        password_hash=testconfig.TEST_PASSWORD_HASH if preinstalled else None)
    problems = ["%s: claimed by %s and %s" % c for c in conflicts]
    problems += check_tree(nodes, preinstalled) + check_dev(nodes)
    if not preinstalled:
        tree = rootfs.Tree()
        for n in nodes[1:]:
            tree.put(n)
        problems += check_sets(apks, live.read_sets(tree))
    if problems:
        raise BuildError("\n".join(problems))
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
    a = p.parse_args(argv[1:])
    try:
        napks, nnodes, g, total = build(a.repo, a.efi, a.out,
                                        a.preinstalled, a.fs_mb)
    except (BuildError, apkrepo.RepoError, live.ComposeError,
            rootfs.TreeError, hdimage.ImageError) as e:
        print("instmedia.build: %s" % e, file=sys.stderr)
        return 1
    print("%s: %d apks, %d nodes, %d MB of UFS, %d MB disk"
          % (a.out, napks, nnodes, g.fssize // 2048, total // 2048))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
