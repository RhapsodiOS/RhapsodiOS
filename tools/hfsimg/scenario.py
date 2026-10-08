"""The test volumes, the guest scripts that exercise them, and what the
volumes must look like afterwards.

The guest runs a plain /bin/sh script from the results disk mounted at /mnt.
It mounts the HFS volume at /mnt/h and writes everything it has to report
into /mnt/out.txt, /mnt/list.txt and /mnt/sums.txt.
"""

import content

MOUNT_POINT = "/mnt/h"


def base_manifest():
    """The volume every built-image test starts from."""
    man = [("dir", "d1"), ("dir", "d1/sub"),
           ("file", "top.txt", 100),
           ("file", "café.txt", 33),
           ("frag", "frag.bin", 200000, 12),
           ("file", "big.bin", 3000000),
           ("file", "empty", 0)]
    for i in range(120):
        man.append(("file", "d1/f%03d" % i, (i * 37) % 5000))
    for i in range(20):
        man.append(("dir", "d1/sub/dd%02d" % i))
    return man


def tree(manifest):
    """{path: None for a folder, size for a file} for a manifest."""
    out = {}
    for ent in manifest:
        out[ent[1]] = None if ent[0] == "dir" else ent[2]
    return out


# --- the write test ---------------------------------------------------------

NEW_FILES = 150
NEW_DIRS = 20
BIG_SIZE = 20 * 1024 * 1024
# w/ga and w/gb grow in turn, APPEND_CHUNK bytes at a time, so each ends up
# in more extents than its catalog record holds and the kernel has to insert
# extents-overflow records.  APPEND_CHUNK is a multiple of both names' content
# unit (the name and a newline, 5 bytes), so the appended bytes equal
# content.data(name, total).
APPEND_ROUNDS = 40
APPEND_CHUNK = 4095


def new_file_size(i):
    return (i * 1499) % 30000


def expected_after_write(manifest):
    """The tree write_script leaves behind, starting from `manifest`."""
    t = tree(manifest)
    t["w"] = None
    for i in range(NEW_FILES):
        t["w/f%03d" % i] = new_file_size(i)
    for i in range(NEW_DIRS):
        t["w/d%02d" % i] = None
        t["w/d%02d/x" % i] = 100
    t["w/r010"] = t.pop("w/f010")
    t["w/d00/f011"] = t.pop("w/f011")
    for i in range(20, 30):
        del t["w/f%03d" % i]
    del t["w/d19/x"]
    del t["w/d19"]
    t["w/big"] = BIG_SIZE
    t["top.txt"] = 5000
    t["w/ga"] = t["w/gb"] = APPEND_ROUNDS * APPEND_CHUNK
    del t["frag.bin"]
    return t


def content_name(path):
    """The name each file's contents were generated from.  Renamed and moved
    files keep the contents they were written with."""
    return {"w/r010": "w/f010", "w/d00/f011": "w/f011"}.get(path, path)


_PERL = content.GUEST_PERL


def write_script(device):
    lines = [
        "O=/mnt/out.txt",
        "echo BEGIN > $O",
        "/mnt/mount_hfs %s %s >> $O 2>&1; echo \"mount rc=$?\" >> $O" % (device, MOUNT_POINT),
        "cd %s || exit 1" % MOUNT_POINT,
        "P() { %s \"$1\" $2 > \"$1\"; }" % _PERL,
        "mkdir w",
        "i=0",
        _files_loop(),

        "i=0",
        _dirs_loop(),

        "mv w/f010 w/r010",
        "mv w/f011 w/d00/f011",
        "i=20",
        "while [ $i -lt 30 ]; do rm w/f0$i; i=`expr $i + 1`; done",
        "rm w/d19/x",
        "rmdir w/d19",
        "P w/big %d" % BIG_SIZE,
        "P top.txt 5000",
        "A() { %s \"$1\" $2 >> \"$1\"; }" % _PERL,
        "i=0",
        "while [ $i -lt %d ]; do A w/ga %d; A w/gb %d; i=`expr $i + 1`; done"
        % (APPEND_ROUNDS, APPEND_CHUNK, APPEND_CHUNK),
        "rm frag.bin",
        "echo \"ops done\" >> $O",
    ] + _report_lines() + _finish_lines()
    return "\n".join(lines) + "\n"


def _files_loop():
    return ("while [ $i -lt %d ]; do n=`printf %%03d $i`; P w/f$n `expr $i \\* 1499 %% 30000`; "
            "i=`expr $i + 1`; done" % NEW_FILES)


def _dirs_loop():
    return ("while [ $i -lt %d ]; do n=`printf %%02d $i`; mkdir w/d$n; P w/d$n/x 100; "
            "i=`expr $i + 1`; done" % NEW_DIRS)


def _append_lines():
    return [
        "A() { %s \"$1\" $2 >> \"$1\"; }" % _PERL,
        "i=0",
        "while [ $i -lt %d ]; do A w/ga %d; A w/gb %d; i=`expr $i + 1`; done"
        % (APPEND_ROUNDS, APPEND_CHUNK, APPEND_CHUNK),
    ]


NEWFS_NAME = "NewfsTest"


def fresh_manifest():
    man = [("dir", "w")]
    for i in range(NEW_FILES):
        man.append(("file", "w/f%03d" % i, new_file_size(i)))
    for i in range(NEW_DIRS):
        man.append(("dir", "w/d%02d" % i))
        man.append(("file", "w/d%02d/x" % i, 100))
    man.extend([("file", "w/big", BIG_SIZE),
                ("file", "w/ga", APPEND_ROUNDS * APPEND_CHUNK),
                ("file", "w/gb", APPEND_ROUNDS * APPEND_CHUNK)])
    return man


def newfs_script(device, raw_device, flags):
    lines = [
        "O=/mnt/out.txt", "echo BEGIN > $O", "ln -sf /dev/hd1a /dev/hd1_hfs_a",
        "/mnt/newfs_hfs %s-v %s %s >> $O 2>&1; echo \"newfs rc=$?\" >> $O" %
        (flags, NEWFS_NAME, raw_device),
        "/mnt/mount_hfs %s %s >> $O 2>&1; echo \"mount rc=$?\" >> $O" % (device, MOUNT_POINT),
        "cd %s || exit 1" % MOUNT_POINT,
        "P() { %s \"$1\" $2 > \"$1\"; }" % _PERL,
        "mkdir w", "i=0", _files_loop(), "i=0", _dirs_loop(), "P w/big %d" % BIG_SIZE,
    ] + _append_lines() + ["echo \"ops done\" >> $O"] + _report_lines() + _finish_lines()
    return "\n".join(lines) + "\n"


LABEL_FILE = "/usr/filesystems/hfs.fs/hfs.label"


def probe_script(dev_arg):
    lines = ["O=/mnt/out.txt", "echo BEGIN > $O", "mkdir -p /usr/filesystems/hfs.fs",
             "rm -f %s" % LABEL_FILE,
             "/mnt/hfs.util -p %s removable writable >> $O 2>&1; echo \"probe rc=$?\" >> $O" % dev_arg,
             "cat %s > /mnt/label.txt 2>> $O" % LABEL_FILE,
             "echo \"report done\" >> $O", "sync", "echo END >> $O", "sync"]
    return "\n".join(lines) + "\n"

def read_script(device, read_only=False, sample=None):
    """Mount, list, checksum (every file, or only `sample`), unmount."""
    opt = "-o ro " if read_only else ""
    lines = [
        "O=/mnt/out.txt",
        "echo BEGIN > $O",
        "/mnt/mount_hfs %s%s %s >> $O 2>&1; echo \"mount rc=$?\" >> $O" % (opt, device, MOUNT_POINT),
        "cd %s || exit 1" % MOUNT_POINT,
    ] + _report_lines(sample) + _finish_lines()
    return "\n".join(lines) + "\n"


def _report_lines(sample=None):
    if sample is None:
        sums = "find . -type f -print | sort | while read f; do cksum \"$f\"; done > /mnt/sums.txt"
    else:
        sums = "(" + "; ".join("cksum './%s'" % p.replace("'", "'\\''") for p in sample) + ") > /mnt/sums.txt"
    return [
        "find . -print | sort > /mnt/list.txt",
        sums,
        "echo \"report done\" >> $O",
    ]


def _finish_lines():
    return [
        "cd /",
        "umount %s >> $O 2>&1; echo \"umount rc=$?\" >> $O" % MOUNT_POINT,
        "sync",
        "echo END >> $O",
        "sync",
    ]


# --- reading the guest's report ----------------------------------------------

def parse_list(text):
    """Paths from `find . -print`, without the leading "./", "." dropped."""
    out = set()
    for line in text.splitlines():
        if line in (".", "./", ""):
            continue
        out.add(line[2:] if line.startswith("./") else line)
    return out


def parse_sums(text):
    """{path: (crc, size)} from cksum lines."""
    out = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        crc, size, path = line.split(None, 2)
        if path.startswith("./"):
            path = path[2:]
        out[path] = (int(crc), int(size))
    return out


def expected_sums(t, name_of=lambda p: p):
    """{path: (crc, size)} for every file of a tree of generated contents."""
    return dict((p, (content.cksum(content.data(name_of(p), s)), s))
                for p, s in t.items() if s is not None)
