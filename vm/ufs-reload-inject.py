"""Gap 2 of the UFS gap tests: change 2 in ffs_reload, on the fixed kernel.
See docs/superpowers/specs/2026-09-25-ufs-gap-tests-design.md.

usage: python ufs-reload-inject.py RUN [--base IMG] [--port N]

  r1 r2 r3   a read error in ffs_reload's superblock (r1), cylinder-summary
             (r2) or root-inode-block (r3) read; the stock IDE driver retries
             a failing read three times, each try 90-100s, before giving up,
             so the runner waits out the retries for the error to reach
             ffs_reload; each must be released so later mounts and the
             unmount still return
  r4         fs_ronly: a refused upgrade, umount, then a read-write mount,
             which must still be refused
  r5         the 4 GB clamp after a reload: a write ending at 4 GiB works,
             one past it fails with "File too large"

Each run boots a snapshot of work/ufs-gap/r-root/disk.qcow2 single-user,
with a fresh dirty test disk as hd1 at work/ufs-gap/RUN/test.img.  r1-r3
attach it through QEMU's blkdebug driver.  The host arms and disarms the
error by writing into padding past the filesystem over QMP, so the guest
never writes.
"""
import argparse
import os
import sys
import time

import make_badfs
import ufs_gap_lib as lib

PAD = 65536
DRIVE_ID = "t1"
SITES = {"r1": "superblock", "r2": "csum", "r3": "inode2"}
# the stock IDE driver's 3 retries at 90-100s each can take ~300s before
# ffs_reload sees the error; give it double that before calling it stuck
INJECT_WAIT = 600

BLKDEBUG = """\
[set-state]
state = "1"
event = "write_aio"
new_state = "2"

[set-state]
state = "2"
event = "write_aio"
new_state = "3"

[inject-error]
state = "2"
event = "read_aio"
sector = "%d"
errno = "5"
once = "off"

[inject-error]
state = "3"
event = "read_aio"
sector = "%d"
errno = "5"
once = "off"
"""


def blkdebug_config(target_sector, dummy_sector):
    """blkdebug rules: reads succeed until the first write (arm); then every
    read covering target_sector fails with EIO, driver retries included,
    until the second write (disarm).  A fired once = off rule otherwise stays
    active forever, so state 3 has a rule of its own on dummy_sector, which
    only the host writes and nothing reads; the first read in state 3 makes
    it the active rule and the real error stops."""
    return BLKDEBUG % (target_sector, dummy_sector)


def drive_args(disk, conf=None):
    """QEMU arguments attaching disk as hd1, through blkdebug if conf."""
    disk = os.path.abspath(disk).replace("\\", "/")
    if conf is None:
        return ["-drive",
                "file=%s,format=raw,if=ide,index=1,media=disk,snapshot=off"
                % disk]
    conf = os.path.abspath(conf).replace("\\", "/")
    return ["-drive",
            "file.driver=blkdebug,file.config=%s,file.image.filename=%s,"
            "format=raw,if=ide,index=1,media=disk,id=%s,snapshot=off"
            % (conf, disk, DRIVE_ID)]


def hmp_write(offset):
    """The HMP command writing one zero sector at offset through hd1."""
    return 'qemu-io %s "write -P 0 %d 512"' % (DRIVE_ID, offset)


def make_test_disk(path):
    """A dirty make_badfs image with PAD zero bytes past the filesystem.
    Returns the byte offset where the padding starts."""
    make_badfs.build_good(path, pad=PAD)
    make_badfs.corrupt(path, "fs_clean", 0)
    return os.path.getsize(path) - PAD


def run(name, base, port):
    outdir = os.path.join(lib.WORK, name)
    if os.path.exists(outdir):
        raise SystemExit("%s already exists; evidence is never overwritten"
                         % outdir)
    if not lib.port_free(port):
        raise SystemExit("QMP port %d is in use" % port)
    root = os.path.join(lib.WORK, "r-root", "disk.qcow2")
    if not os.path.exists(root):
        lib.make_overlay(base, root)
    os.makedirs(outdir)
    disk = os.path.join(outdir, "test.img")
    pad_start = make_test_disk(disk)
    notes = []
    if name == "r5":
        maxfs = make_badfs.read_field(disk, "fs_maxfilesize")
        notes.append("on-disk fs_maxfilesize %d" % maxfs)
        if maxfs <= 1 << 32:
            raise SystemExit("fs_maxfilesize %d does not exceed 4 GiB; R5 "
                             "cannot tell fixed from unfixed" % maxfs)
    conf = None
    if name in SITES:
        sector = make_badfs.reload_sectors(disk)[SITES[name]]
        conf = os.path.join(outdir, "blkdebug.conf")
        with open(conf, "w") as f:
            f.write(blkdebug_config(sector, pad_start // 512))
        notes.append("EIO on sector %d (%s); arm at byte %d, disarm at %d"
                     % (sector, SITES[name], pad_start, pad_start + 512))

    gc = lib.load_guest_console()
    g = gc.Guest(outdir, port=port, image=os.path.abspath(root),
                 extra=drive_args(disk, conf))

    def step(cmd, wait, shot):
        g.line(cmd)
        time.sleep(wait)
        g.shot(shot)

    def hmp(offset, what):
        g.cmd("human-monitor-command", **{"command-line": hmp_write(offset)})
        notes.append(what)
        time.sleep(1)

    try:
        lib.single_user(g)
        step("mount -r /dev/hd1a /mnt", 5, "1-ro")
        if name in SITES:
            hmp(pad_start, "armed before the first mount -uw")
            g.line("mount -uw /mnt")
            start = time.time()
            ticks = 0

            def on_tick():
                nonlocal ticks
                ticks += 30
                g.shot("2-armed-%03d" % ticks)

            found = lib.wait_for(g.serial, "ffs: /mnt", INJECT_WAIT, tick=30,
                                 on_tick=on_tick)
            if found:
                notes.append("%s (%ds after arming)"
                             % (lib.ffs_lines(g.serial)[0],
                                int(time.time() - start)))
            else:
                notes.append("no ffs: /mnt line within %ds" % INJECT_WAIT)
            g.shot("2-upgrade-refused")
            hmp(pad_start + 512, "disarmed after it")
            step("ls /mnt; mount", 5, "3-still-ro")
            step("mount -uw /mnt", 10, "4-second-upgrade")
            step("umount /mnt", 8, "5-umount")
            step("mount", 5, "6-mount")
        elif name == "r4":
            step("mount -uw /mnt", 10, "2-upgrade-refused")
            step("umount /mnt", 8, "3-umount")
            step("mount /dev/hd1a /mnt", 8, "4-rw-mount")
            step("mount", 5, "5-mount")
        else:
            step("mount -uw /mnt", 10, "2-upgrade-refused")
            step("fsck -y /dev/hd1a", 60, "3-fsck")
            step("mount -uw /mnt", 10, "4-upgrade")
            step("mount", 5, "5-mount")
            step("dd if=/mach_kernel of=/mnt/below bs=2 count=1 seek=2147483647",
                 15, "6-dd-below")
            step("ls -l /mnt/below", 5, "7-ls-below")
            step("dd if=/mach_kernel of=/mnt/above bs=2 count=1 seek=2147483648",
                 15, "8-dd-above")
            step("ls -l /mnt", 5, "9-ls")
    finally:
        g.close()
    lib.write_result(outdir, notes)


def main(argv):
    p = argparse.ArgumentParser(description="UFS gap 2: change 2 in ffs_reload")
    p.add_argument("run", choices=("r1", "r2", "r3", "r4", "r5"))
    p.add_argument("--base", default=lib.BASE)
    p.add_argument("--port", type=int, default=4493)
    a = p.parse_args(argv[1:])
    run(a.run, a.base, a.port)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
