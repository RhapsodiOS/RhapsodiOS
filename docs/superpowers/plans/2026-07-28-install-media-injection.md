# Install Media Injection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot the Rhapsody DR2 x86 installer under QEMU with the rebuilt i386 kernel and EIDE driver, and complete an install onto an IDE disk that then boots unaided.

**Architecture:** Port the in-tree rcz compressor to Python, extract-and-repackage the two 1.44 MB floppy volumes with a UFS writer that clones the template's geometry, and patch the 630 MB CD in place with the existing `rhap_inject.py` primitives. Design rationale and all measurements are in `docs/superpowers/specs/2026-07-28-install-media-injection-design.md`.

**Tech Stack:** Python 3 standard library only (matching `vm/rhap_image.py`, `vm/rhap_inject.py`, `vm/qemu-shot.py`); `unittest`; QEMU; `plink`/`pscp` to the Rhapsody build guest for the one step that needs `strip`.

## Global Constraints

- Standard library only. No third-party Python packages anywhere in `vm/`.
- `vm/install/rhapsody_dr2_x86.iso`, `vm/install/rhapsody_dr2_x86_InstallationFloppy.img` and `vm/install/rhapsody_dr2_x86_DriverDisk.img` are pristine masters and are **never** written. All output goes to `vm/install/build/`.
- `vm/golden.img` and `vm/rhapsody.vmdk` are never written, as today.
- Run all Python from inside `vm/` (`cd vm`), matching the existing tests.
- On Git Bash, `export MSYS2_ARG_CONV_EXCL='*'` before passing absolute guest paths like `/mach_kernel` as CLI arguments, or MSYS rewrites them into Windows paths.
- Commit messages start with the subsystem, e.g. `vm: `, per `CLAUDE.md`.
- The UFS in these images is little-endian; the NeXT disk label around it and the rcz stream header are big-endian.

## File Structure

| File | Responsibility |
|---|---|
| `vm/rcz.py` | Create. rcz stream codec. No knowledge of UFS or media. |
| `vm/test_rcz.py` | Create. Codec tests, including reproduction of shipped media bytes. |
| `vm/rhap_image.py` | Modify. `Inode` gains `uid`/`gid`; reader gains `readlink`. Stays read-only. |
| `vm/ufs_extract.py` | Create. Image → list of `Node`. Pure read. |
| `vm/test_ufs_extract.py` | Create. |
| `vm/ufs_build.py` | Create. Geometry + cg metadata + volume writer. |
| `vm/test_ufs_build.py` | Create. Table recomputation against real media; identity round-trip. |
| `vm/rhap_inject.py` | Modify. `check_target` gains an allowlist for `vm/install/build/`. |
| `vm/build_media.py` | Create. Orchestrator; the only file that knows what "EIDE" means. |
| `vm/build-i386-kernel-eide.sh` | Modify. Add the driver strip step. |

---

### Task 1: rcz decompressor

**Files:**
- Create: `vm/rcz.py`
- Create: `vm/test_rcz.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `rcz.decompress(data: bytes) -> bytes`; `rcz.RczError`; module constants `MAGIC = 666`, `QLEN = 255`, `F1 = 12`, `F2 = 12`, `ABOVE = 191`, `HEADER = 8`.

Ported from `src/boot-2/gen/rcz/rcz_decompress_mem.c`. The stream is an 8-byte big-endian header (method number, then the original length) followed by groups of one 4-byte big-endian token word and its payload. Each token bit, walked from bit 31 down, selects a 1-byte queue index (bit set) or a 2-byte literal 16-bit word (bit clear). The queue is 255 entries of 16-bit words, initialised to `que[i] = i`.

- [ ] **Step 1: Write the failing test**

Create `vm/test_rcz.py`:

```python
import os
import unittest

import rcz
import rhap_image

HERE = os.path.dirname(os.path.abspath(__file__))
ISO = os.path.join(HERE, "install", "rhapsody_dr2_x86.iso")
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")


def _media_present():
    return os.path.exists(ISO) and os.path.exists(FLOPPY)


class TestDecompress(unittest.TestCase):
    def test_rejects_short_stream(self):
        with self.assertRaises(rcz.RczError):
            rcz.decompress(b"\0\0\0")

    def test_rejects_wrong_method(self):
        with self.assertRaises(rcz.RczError):
            rcz.decompress(b"\0\0\0\1" + b"\0\0\0\0")

    def test_empty_payload(self):
        self.assertEqual(rcz.decompress(b"\0\0\x02\x9a" + b"\0\0\0\0"), b"")

    @unittest.skipUnless(_media_present(), "install media not present")
    def test_reproduces_shipped_kernel(self):
        with rhap_image.Image(FLOPPY) as f:
            stream = f.read_file(f.resolve("/mach_kernel.rcz"))
        with rhap_image.Image(ISO) as i:
            kernel = i.read_file(i.resolve("/mach_kernel"))
        self.assertEqual(rcz.decompress(stream), kernel)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_rcz -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'rcz'`.

- [ ] **Step 3: Write minimal implementation**

Create `vm/rcz.py`:

```python
"""Codec for the rcz executable-compression format.

Ported from src/boot-2/gen/rcz/rcz_compress_mem.c and rcz_decompress_mem.c
(R. E. Crandall, July 1995).  The format is a 16-bit-symbol move-toward-front
queue: every two input bytes form a word which is either found in a 255-entry
queue and emitted as a one-byte index, or missed and emitted as the two-byte
literal.  A 32-bit token word, read from bit 31 down, says which.

The stream header is big-endian, unlike the little-endian UFS filesystem these
files normally live in.
"""

import struct
import sys

MAGIC = 666           # METHOD_17_JUL_95
QLEN = 255
F1 = 12
F2 = 12
ABOVE = (F2 * QLEN) >> 4   # 191
HEADER = 8


class RczError(Exception):
    pass


def decompress(data):
    if len(data) < HEADER:
        raise RczError("stream is %d bytes, shorter than the %d-byte header"
                       % (len(data), HEADER))
    version, length = struct.unpack_from(">II", data, 0)
    if version != MAGIC:
        raise RczError("bad method %d, expected %d" % (version, MAGIC))

    que = list(range(QLEN))
    out = bytearray()
    p = HEADER
    even = 2 * (length // 2)

    while len(out) < even:
        token = struct.unpack_from(">I", data, p)[0]
        p += 4
        c = 1 << 31
        for _ in range(32):
            if token & c:
                jmatch = data[p]
                p += 1
                word = que[jmatch]
                jabove = (F1 * jmatch) >> 4
                que[jabove + 1:jmatch + 1] = que[jabove:jmatch]
                que[jabove] = word
            else:
                word = (data[p] << 8) | data[p + 1]
                p += 2
                que[ABOVE + 1:QLEN] = que[ABOVE:QLEN - 1]
                que[ABOVE] = word
            out.append((word >> 8) & 0xff)
            out.append(word & 0xff)
            if len(out) >= even:
                break
            c >>= 1

    if even != length:
        out.append(data[p])
    return bytes(out)


def main(argv):
    if len(argv) != 4 or argv[1] != "-d":
        print("usage: rcz.py -d <infile> <outfile>", file=sys.stderr)
        return 2
    with open(argv[2], "rb") as f:
        data = f.read()
    with open(argv[3], "wb") as f:
        f.write(decompress(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_rcz -v
```

Expected: PASS, 4 tests. `test_reproduces_shipped_kernel` must produce exactly 1,404,116 bytes; if it raises `IndexError` the queue update or the token walk is wrong, not the header.

- [ ] **Step 5: Commit**

```bash
git add vm/rcz.py vm/test_rcz.py
git commit -m "vm: port the rcz decompressor and verify it against the shipped kernel"
```

---

### Task 2: rcz compressor

**Files:**
- Modify: `vm/rcz.py`
- Modify: `vm/test_rcz.py`

**Interfaces:**
- Consumes: `rcz.decompress`, constants from Task 1.
- Produces: `rcz.compress(data: bytes) -> bytes`.

The algorithm is fully deterministic with no tunable parameters, so `compress` of the CD's kernel must reproduce the shipped `mach_kernel.rcz` byte-for-byte. That equality is what makes Task 3's measurement trustworthy.

Performance note: this is a linear scan of a 255-entry queue per input pair. Use `list.index()` and slice assignment so the inner work happens at C speed; compressing the 1.47 MB kernel still takes on the order of a minute.

- [ ] **Step 1: Write the failing test**

Append to `vm/test_rcz.py`, before the `if __name__` block:

```python
class TestCompress(unittest.TestCase):
    def test_round_trip_edge_cases(self):
        for payload in (b"", b"A", b"AB", b"ABC",
                        bytes(1000), bytes(range(256)) * 4,
                        b"\xff\xfe" * 500):
            self.assertEqual(rcz.decompress(rcz.compress(payload)), payload,
                             "round trip failed for %d bytes" % len(payload))

    def test_header_records_original_length(self):
        stream = rcz.compress(b"hello world")
        self.assertEqual(stream[:8], b"\x00\x00\x02\x9a\x00\x00\x00\x0b")

    @unittest.skipUnless(_media_present(), "install media not present")
    def test_reproduces_shipped_stream_byte_for_byte(self):
        with rhap_image.Image(ISO) as i:
            kernel = i.read_file(i.resolve("/mach_kernel"))
        with rhap_image.Image(FLOPPY) as f:
            shipped = f.read_file(f.resolve("/mach_kernel.rcz"))
        self.assertEqual(rcz.compress(kernel), shipped)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_rcz.TestCompress -v
```

Expected: FAIL with `AttributeError: module 'rcz' has no attribute 'compress'`.

- [ ] **Step 3: Write minimal implementation**

Add to `vm/rcz.py`, after `decompress`:

```python
def _emit_group(token, tokenct, payload, final):
    """Serialise one token word and its payload entries."""
    tok = ((token << (32 - tokenct)) if final else token) & 0xffffffff
    buf = bytearray(struct.pack(">I", tok))
    c = 1 << 31
    for j in range(tokenct):
        if tok & c:
            buf.append(payload[j] & 0xff)
        else:
            buf.append((payload[j] >> 8) & 0xff)
            buf.append(payload[j] & 0xff)
        c >>= 1
    return bytes(buf)


def compress(data):
    out = bytearray(struct.pack(">II", MAGIC, len(data)))
    que = list(range(QLEN))
    token = 0
    tokenct = 0
    payload = []
    word = 0

    for ct in range(len(data)):
        word = ((word << 8) | data[ct]) & 0xffffff
        if ct % 2 == 1:
            word &= 0xffff
            try:
                jmatch = que.index(word)
            except ValueError:
                jmatch = -1
            token = (token << 1) | (1 if jmatch >= 0 else 0)
            if jmatch >= 0:
                c = que[jmatch]
                jabove = (F1 * jmatch) >> 4
                que[jabove + 1:jmatch + 1] = que[jabove:jmatch]
                que[jabove] = c
                payload.append(jmatch)
            else:
                que[ABOVE + 1:QLEN] = que[ABOVE:QLEN - 1]
                que[ABOVE] = word
                payload.append(word)
            tokenct += 1
            if tokenct == 32:
                out += _emit_group(token, tokenct, payload, False)
                token = 0
                tokenct = 0
                del payload[:]

    if tokenct > 0:
        out += _emit_group(token, tokenct, payload, True)
    if len(data) % 2 == 1:
        out.append(word & 0xff)
    return bytes(out)
```

Update `main` to accept `-c` as well:

```python
def main(argv):
    if len(argv) != 4 or argv[1] not in ("-c", "-d"):
        print("usage: rcz.py {-c|-d} <infile> <outfile>", file=sys.stderr)
        return 2
    with open(argv[2], "rb") as f:
        data = f.read()
    result = compress(data) if argv[1] == "-c" else decompress(data)
    with open(argv[3], "wb") as f:
        f.write(result)
    print("%s: %d -> %d bytes" % (argv[2], len(data), len(result)))
    return 0
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_rcz -v
```

Expected: PASS, 7 tests. The byte-for-byte test takes roughly a minute.

If `test_reproduces_shipped_stream_byte_for_byte` fails but the round trips pass, the port is self-consistent but differs from the tool that built the media — record the first differing offset and the two byte values in the commit message, keep going, and treat Task 3's number as valid-but-uncorroborated, per the spec's fallback.

- [ ] **Step 5: Commit**

```bash
git add vm/rcz.py vm/test_rcz.py
git commit -m "vm: port the rcz compressor and reproduce the shipped kernel stream"
```

---

### Task 3: The gate — measure the compressed kernel

**Files:**
- Create: `vm/measure-kernel-fit.py`

**Interfaces:**
- Consumes: `rcz.compress`, `rhap_image.Image`.
- Produces: a printed verdict and exit status 0 (fits) or 1 (does not). No other task depends on its code.

This is the only step that can invalidate the approach, so it runs alone and before any writer is built. It computes the ceiling from the live superblock rather than from a hardcoded number.

Budget derivation, all from the installation floppy's own superblock and inodes:

```
budget_frags = fs_dsize - (sum of di_blocks over every object except /mach_kernel.rcz)
payload_frags = budget_frags - indirect_frags        # indirect_frags = fs_frag, one single-indirect block
ceiling = (payload_frags // fs_frag) * fs_frag * fs_fsize     # whole blocks only
```

- [ ] **Step 1: Write the measurement script**

Create `vm/measure-kernel-fit.py`:

```python
"""Report whether the rebuilt kernel's rcz stream fits the installation floppy.

Prints the ceiling derived from the floppy's own superblock, the measured
compressed size, and the margin.  Exit 0 if it fits, 1 if it does not.
"""

import os
import sys

import rcz
import rhap_image

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")
KERNEL = os.path.join(HERE, "..", "out", "i386", "mach_kernel")
TARGET = "/mach_kernel.rcz"


def used_frags_excluding(img, skip_ino):
    total = 0
    stack = ["/"]
    while stack:
        path = stack.pop()
        for name, ino, dtype in img.listdir(path):
            if name in (".", ".."):
                continue
            child = path.rstrip("/") + "/" + name
            if ino != skip_ino:
                total += img.inode(ino).blocks
            if dtype == 4:
                stack.append(child)
    return total


def main():
    with rhap_image.Image(FLOPPY) as img:
        kernel_ino = img.resolve(TARGET)
        other = used_frags_excluding(img, kernel_ino)
        budget = img.fs_size_data() - other
        payload = budget - img.frag
        ceiling = (payload // img.frag) * img.frag * img.fsize

    with open(KERNEL, "rb") as f:
        raw = f.read()
    stream = rcz.compress(raw)

    print("kernel            %d bytes" % len(raw))
    print("compressed        %d bytes" % len(stream))
    print("other objects     %d frags" % other)
    print("budget            %d frags" % budget)
    print("ceiling           %d bytes" % ceiling)
    print("margin            %+d bytes" % (ceiling - len(stream)))
    if len(stream) <= ceiling:
        print("VERDICT: fits 1.44 MB")
        return 0
    print("VERDICT: does NOT fit; fall through to the 2.88 MB branch (Task 7a)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Add `fs_size_data` to `rhap_image.py`**

`fs_dsize` is not currently parsed. Add it beside the other superblock fields in `_read_superblock` (`vm/rhap_image.py:63-79`), immediately after `self.fs_size = g(36)`:

```python
        self.fs_dsize = g(40)
```

and add this accessor next to `_max_writable` (`vm/rhap_image.py:250`), registering it with the others at `vm/rhap_image.py:261-268`:

```python
def _fs_size_data(self):
    """Fragments available for file data, excluding all filesystem metadata."""
    return self.fs_dsize


Image.fs_size_data = _fs_size_data
```

- [ ] **Step 3: Run the gate**

```bash
cd vm && python measure-kernel-fit.py
```

Expected output shape (the design projects roughly `-5000` for the margin, so a negative number here is the *expected* result, not a bug):

```
kernel            1472800 bytes
compressed        ####### bytes
other objects     184 frags
budget            1079 frags
ceiling           ####### bytes
margin            ±##### bytes
VERDICT: ...
```

- [ ] **Step 4: Record the verdict**

Write the exact printed output into the spec under a new `## Gate result` section at the end of `docs/superpowers/specs/2026-07-28-install-media-injection-design.md`, dated. This is the number the whole design hinges on; it belongs in the record, not just in a terminal.

- [ ] **Step 5: Commit**

```bash
git add vm/measure-kernel-fit.py vm/rhap_image.py docs/superpowers/specs/2026-07-28-install-media-injection-design.md
git commit -m "vm: measure whether the rebuilt kernel's rcz stream fits the install floppy"
```

**Branch point.** If the verdict is "fits", continue at Task 4 and build 1.44 MB media. If it is "does NOT fit", still continue at Task 4 — every remaining task is identical except Task 7a, which resizes the volume. The gate changes one parameter, not the plan.

---

### Task 4: Inode ownership and symlink targets

**Files:**
- Modify: `vm/rhap_image.py:99-114` (the `Inode` class)
- Create: `vm/test_ufs_extract.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `Inode.uid`, `Inode.gid`, `Inode.is_lnk()`, `Image.readlink(ino) -> str`.

The 128-byte dinode's ownership fields sit at offsets 112 and 116, with `di_spare[2]` filling 120..127. Step 1 confirms that empirically rather than trusting the layout, because getting it wrong silently produces media with wrong ownership.

- [ ] **Step 1: Write the discriminating test**

Create `vm/test_ufs_extract.py`:

```python
import os
import struct
import unittest

import rhap_image

HERE = os.path.dirname(os.path.abspath(__file__))
ISO = os.path.join(HERE, "install", "rhapsody_dr2_x86.iso")
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")


def _present(*paths):
    return all(os.path.exists(p) for p in paths)


class TestInodeOwnership(unittest.TestCase):
    @unittest.skipUnless(_present(ISO), "install media not present")
    def test_di_spare_is_zero_across_the_tree(self):
        """Offsets 120..127 are di_spare[2]; if they are always zero, uid/gid
        are at 112/116 and not shifted by four."""
        with rhap_image.Image(ISO) as img:
            seen = 0
            stack = ["/"]
            while stack and seen < 400:
                path = stack.pop()
                for name, ino, dtype in img.listdir(path):
                    if name in (".", ".."):
                        continue
                    frag, entry = rhap_image._inode_location(img, ino)
                    blk = img.read_frag(frag, img.bsize)
                    raw = blk[entry:entry + rhap_image.DINODE_SIZE]
                    self.assertEqual(raw[120:128], b"\0" * 8,
                                     "di_spare nonzero for inode %d" % ino)
                    seen += 1
                    if dtype == 4 and len(stack) < 20:
                        stack.append(path.rstrip("/") + "/" + name)
            self.assertGreater(seen, 100)

    @unittest.skipUnless(_present(ISO), "install media not present")
    def test_root_is_owned_by_root(self):
        with rhap_image.Image(ISO) as img:
            root = img.inode(2)
            self.assertEqual((root.uid, root.gid), (0, 0))

    @unittest.skipUnless(_present(ISO), "install media not present")
    def test_readlink_returns_a_target(self):
        with rhap_image.Image(ISO) as img:
            self.assertTrue(img.readlink(img.resolve("/etc")).endswith("private/etc"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_ufs_extract -v
```

Expected: `test_di_spare_is_zero_across_the_tree` PASSES (it only reads raw bytes), the other two FAIL with `AttributeError` on `uid` and `readlink`.

If `test_di_spare_is_zero_across_the_tree` fails, stop: the dinode layout differs from the assumption and every offset below needs re-deriving before continuing.

- [ ] **Step 3: Write minimal implementation**

In `vm/rhap_image.py`, extend `Inode.__init__` (currently `vm/rhap_image.py:100-107`) by adding after the `self.blocks` line:

```python
        self.uid, self.gid = struct.unpack_from("<2I", buf, 112)
```

and add beside `is_reg` (`vm/rhap_image.py:112-113`):

```python
    def is_lnk(self):
        return (self.mode & 0o170000) == 0o120000
```

Add the reader next to `_max_writable`, and register it with the others at `vm/rhap_image.py:261-268`:

```python
def _readlink(self, ino):
    """Target of a symbolic link.

    Short targets are stored inline in the block-pointer area (a "fast
    symlink", di_size <= fs_maxsymlinklen); longer ones occupy data blocks
    like a regular file.
    """
    inode = self.inode(ino) if isinstance(ino, int) else ino
    if not inode.is_lnk():
        raise ValueError("inode %d is not a symbolic link" % inode.ino)
    if inode.size <= self.maxsymlinklen:
        frag, entry = _inode_location(self, inode.ino)
        blk = self.read_frag(frag, self.bsize)
        raw = blk[entry + 40:entry + 40 + inode.size]
    else:
        raw = self.read_file(inode)
    return raw.decode("ascii", "replace")


Image.readlink = _readlink
```

`maxsymlinklen` is not parsed yet. Add it to `_read_superblock` beside the others:

```python
        self.maxsymlinklen = g(1320)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_ufs_extract -v
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add vm/rhap_image.py vm/test_ufs_extract.py
git commit -m "vm: read inode ownership and symlink targets"
```

---

### Task 5: Tree extraction

**Files:**
- Create: `vm/ufs_extract.py`
- Modify: `vm/test_ufs_extract.py`

**Interfaces:**
- Consumes: `rhap_image.Image`, `Inode.uid`, `Inode.gid`.
- Produces:
  - `ufs_extract.Node` — a `namedtuple("Node", "path kind mode uid gid mtime data")`, where `kind` is one of `"dir"`, `"reg"`, `"lnk"`, `path` is absolute and slash-separated (root is `"/"`), `data` is `bytes` for `"reg"`, the target `str` for `"lnk"`, and `None` for `"dir"`.
  - `ufs_extract.extract(image_path) -> list[Node]` — root first, then every object in directory-entry order, parents always before children.
  - `ufs_extract.UnsupportedNode` — raised for any object that is not a directory, regular file, or symlink.

Directory-entry order is preserved so a rebuild lays entries out the way the original did.

- [ ] **Step 1: Write the failing test**

Append to `vm/test_ufs_extract.py`, before the `if __name__` block:

```python
import ufs_extract


class TestExtract(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_installation_floppy_shape(self):
        nodes = ufs_extract.extract(FLOPPY)
        self.assertEqual(nodes[0].path, "/")
        self.assertEqual(nodes[0].kind, "dir")
        by_path = {n.path: n for n in nodes}
        self.assertEqual(len(nodes), 21)   # root plus the 20 objects
        self.assertEqual(by_path["/mach_kernel.rcz"].kind, "reg")
        self.assertEqual(len(by_path["/mach_kernel.rcz"].data), 1052315)
        self.assertEqual(by_path["/usr/standalone/i386/sarld"].kind, "reg")
        self.assertNotIn("lnk", {n.kind for n in nodes})

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_parents_precede_children(self):
        seen = set()
        for node in ufs_extract.extract(FLOPPY):
            if node.path != "/":
                parent = node.path.rsplit("/", 1)[0] or "/"
                self.assertIn(parent, seen, "%s came before %s" % (node.path, parent))
            seen.add(node.path)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_driver_disk_has_no_links(self):
        disk = os.path.join(HERE, "install", "rhapsody_dr2_x86_DriverDisk.img")
        nodes = ufs_extract.extract(disk)
        self.assertEqual(len(nodes), 111)
        self.assertEqual({n.kind for n in nodes}, {"dir", "reg"})
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_ufs_extract.TestExtract -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'ufs_extract'`.

- [ ] **Step 3: Write minimal implementation**

Create `vm/ufs_extract.py`:

```python
"""Read a NeXT-labelled UFS volume into a plain tree of nodes.

Read-only.  The output is everything ufs_build.py needs to lay the same tree
back down: ordering, ownership, modes, and contents.
"""

import collections

import rhap_image

Node = collections.namedtuple("Node", "path kind mode uid gid mtime data")

KIND = {4: "dir", 8: "reg", 10: "lnk"}


class UnsupportedNode(Exception):
    pass


def _node(img, path, ino, kind):
    inode = img.inode(ino)
    if kind == "reg":
        data = img.read_file(inode)
    elif kind == "lnk":
        data = img.readlink(inode)
    else:
        data = None
    return Node(path, kind, inode.mode, inode.uid, inode.gid, inode.mtime, data)


def extract(image_path):
    with rhap_image.Image(image_path) as img:
        out = [_node(img, "/", 2, "dir")]
        pending = [("/", 2)]
        while pending:
            path, ino = pending.pop(0)
            for name, child, dtype in img.listdir(path):
                if name in (".", ".."):
                    continue
                kind = KIND.get(dtype)
                if kind is None:
                    raise UnsupportedNode(
                        "%s/%s has directory-entry type %d; only directories, "
                        "regular files and symlinks can be repackaged"
                        % (path.rstrip("/"), name, dtype))
                child_path = path.rstrip("/") + "/" + name
                out.append(_node(img, child_path, child, kind))
                if kind == "dir":
                    pending.append((child_path, child))
        return out
```

Note this is breadth-first, which satisfies "parents before children" while keeping each directory's entries contiguous and in on-disk order.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_ufs_extract -v
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_extract.py vm/test_ufs_extract.py
git commit -m "vm: extract a UFS volume into a plain node tree"
```

---

### Task 6: Cylinder-group metadata recomputation

**Files:**
- Create: `vm/ufs_build.py`
- Create: `vm/test_ufs_build.py`

**Interfaces:**
- Consumes: `rhap_image.Image`.
- Produces:
  - `ufs_build.Geometry` — superblock fields as attributes: `sblkno cblkno iblkno dblkno cgoffset cgmask size dsize ncg bsize fsize frag minfree nindir inopb nspf npsect interleave trackskew csaddr cssize cgsize ntrak nsect spc ncyl cpg ipg fpg cpc postblformat nrpos magic maxsymlinklen`.
  - `ufs_build.read_geometry(image_path) -> Geometry`
  - `ufs_build.cbtocylno(g, bno) -> int`
  - `ufs_build.cbtorpos(g, bno) -> int`
  - `ufs_build.bit_is_set(bitmap, i) -> bool`
  - `ufs_build.recompute_cg_tables(g, blksfree) -> CgTables`, a `namedtuple("CgTables", "blktot blks frsum nbfree nffree")` where `blktot` is a list of `cpg` ints, `blks` a list of `cpg * nrpos` ints, `frsum` a list of `frag` ints.

This is the part of a UFS volume that is easy to get subtly wrong, so it is built and validated on its own, before anything writes a byte. The validation is strong: feeding the *original* floppy's own free-fragment bitmap into `recompute_cg_tables` must reproduce the tables that floppy already stores.

The two positional macros come from `src/kernel-7/bsd/ufs/ffs/fs.h:452-457`. C's `*`, `/` and `%` are the same precedence and associate left to right; the parenthesisation below preserves that.

- [ ] **Step 1: Write the failing test**

Create `vm/test_ufs_build.py`:

```python
import os
import struct
import unittest

import rhap_image
import ufs_build

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")
DRIVERS = os.path.join(HERE, "install", "rhapsody_dr2_x86_DriverDisk.img")


def _present(p):
    return os.path.exists(p)


def _read_cg(path):
    """Return (Geometry, cg block bytes, free-fragment bitmap) from a volume."""
    g = ufs_build.read_geometry(path)
    with rhap_image.Image(path) as img:
        cg = img.read_frag(g.cblkno, g.bsize)
    freeoff = struct.unpack_from("<i", cg, 96)[0]
    blksfree = cg[freeoff:freeoff + (g.fpg + 7) // 8]
    return g, cg, blksfree


class TestGeometry(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_reads_known_floppy_geometry(self):
        g = ufs_build.read_geometry(FLOPPY)
        self.assertEqual(g.magic, 0x011954)
        self.assertEqual((g.ncg, g.bsize, g.fsize, g.frag), (1, 8192, 1024, 8))
        self.assertEqual((g.size, g.dsize, g.ipg, g.fpg), (1344, 1263, 384, 2304))
        self.assertEqual((g.nsect, g.spc, g.nrpos, g.cpg), (9, 18, 8, 128))


class TestCgTables(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_reproduces_installation_floppy_tables(self):
        g, cg, blksfree = _read_cg(FLOPPY)
        t = ufs_build.recompute_cg_tables(g, blksfree)

        btotoff, boff = struct.unpack_from("<2i", cg, 84)
        stored_blktot = list(struct.unpack_from("<%di" % g.cpg, cg, btotoff))
        stored_blks = list(struct.unpack_from("<%dh" % (g.cpg * g.nrpos), cg, boff))
        stored_frsum = list(struct.unpack_from("<%di" % g.frag, cg, 52))
        _ndir, stored_nbfree, _nifree, stored_nffree = struct.unpack_from("<4i", cg, 24)

        self.assertEqual(t.blktot, stored_blktot)
        self.assertEqual(t.blks, stored_blks)
        self.assertEqual(t.frsum, stored_frsum)
        self.assertEqual(t.nbfree, stored_nbfree)
        self.assertEqual(t.nffree, stored_nffree)

    @unittest.skipUnless(_present(DRIVERS), "install media not present")
    def test_reproduces_driver_disk_tables(self):
        g, cg, blksfree = _read_cg(DRIVERS)
        t = ufs_build.recompute_cg_tables(g, blksfree)
        _ndir, stored_nbfree, _nifree, stored_nffree = struct.unpack_from("<4i", cg, 24)
        self.assertEqual((t.nbfree, t.nffree), (stored_nbfree, stored_nffree))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_ufs_build -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'ufs_build'`.

- [ ] **Step 3: Write minimal implementation**

Create `vm/ufs_build.py`:

```python
"""Write a NeXT-labelled UFS volume from a node tree.

The geometry is cloned from a template image rather than invented: the disk
label and every geometry field of the superblock are copied verbatim, and only
allocation state is regenerated.  The result is the filesystem newfs would have
produced for this geometry, with our contents in it.

Layout and macros follow src/kernel-7/bsd/ufs/ffs/fs.h.
"""

import collections
import struct

import rhap_image

SB_FIELDS = {
    "sblkno": 8, "cblkno": 12, "iblkno": 16, "dblkno": 20,
    "cgoffset": 24, "cgmask": 28, "size": 36, "dsize": 40, "ncg": 44,
    "bsize": 48, "fsize": 52, "frag": 56, "minfree": 60,
    "nindir": 116, "inopb": 120, "nspf": 124,
    "npsect": 132, "interleave": 136, "trackskew": 140,
    "csaddr": 152, "cssize": 156, "cgsize": 160,
    "ntrak": 164, "nsect": 168, "spc": 172, "ncyl": 176, "cpg": 180,
    "ipg": 184, "fpg": 188,
    "cpc": 856, "maxsymlinklen": 1320, "postblformat": 1356, "nrpos": 1360,
    "magic": 1372,
}

DIRBLKSIZ = 512

Geometry = collections.namedtuple("Geometry", sorted(SB_FIELDS))
CgTables = collections.namedtuple("CgTables", "blktot blks frsum nbfree nffree")


class BuildError(Exception):
    pass


def read_geometry(image_path):
    with rhap_image.Image(image_path) as img:
        sb = img._read_at(img.part_start + rhap_image.SBOFF, rhap_image.SBOFF)
    values = {name: struct.unpack_from("<i", sb, off)[0]
              for name, off in SB_FIELDS.items()}
    if values["magic"] != rhap_image.FS_MAGIC:
        raise BuildError("bad UFS magic 0x%x in %s" % (values["magic"], image_path))
    if values["ncg"] != 1:
        raise BuildError(
            "%s has %d cylinder groups; this writer only handles single-group "
            "volumes (the two install floppies)" % (image_path, values["ncg"]))
    return Geometry(**values)


def cbtocylno(g, bno):
    return bno * g.nspf // g.spc


def cbtorpos(g, bno):
    if g.nrpos <= 1:
        return 0
    if g.npsect <= 0:
        raise BuildError("fs_npsect is %d; cannot compute rotational position"
                         % g.npsect)
    n = bno * g.nspf
    skewed = (n % g.spc // g.nsect * g.trackskew
              + n % g.spc % g.nsect * g.interleave)
    return skewed % g.nsect * g.nrpos // g.npsect


def bit_is_set(bitmap, i):
    return (bitmap[i // 8] >> (i % 8)) & 1


def recompute_cg_tables(g, blksfree):
    """Derive every allocation summary from the free-fragment bitmap.

    A set bit means the fragment is free.  A block counts as free only if all
    fs_frag of its fragments are; otherwise its maximal runs of free fragments
    are accounted individually, and runs never cross a block boundary.
    """
    blktot = [0] * g.cpg
    blks = [0] * (g.cpg * g.nrpos)
    frsum = [0] * g.frag
    nbfree = 0
    nffree = 0

    for base in range(0, g.fpg, g.frag):
        if all(bit_is_set(blksfree, base + i) for i in range(g.frag)):
            nbfree += 1
            cyl = cbtocylno(g, base)
            blktot[cyl] += 1
            blks[cyl * g.nrpos + cbtorpos(g, base)] += 1
            continue
        run = 0
        for i in range(g.frag):
            if bit_is_set(blksfree, base + i):
                run += 1
                continue
            if run:
                frsum[run] += 1
                nffree += run
            run = 0
        if run:
            frsum[run] += 1
            nffree += run

    return CgTables(blktot, blks, frsum, nbfree, nffree)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_ufs_build -v
```

Expected: PASS, 3 tests.

If `test_reproduces_installation_floppy_tables` fails only on `blks`, the discrepancy is in `cbtorpos`; print `[(bno, cbtorpos(g, bno)) for bno in range(0, g.fpg, g.frag)][:32]` and check the operator grouping against `fs.h:454-457` before changing anything else. If it fails on `frsum` or `nffree`, the run accounting is crossing block boundaries.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_build.py vm/test_ufs_build.py
git commit -m "vm: recompute UFS cylinder-group summaries and validate against the shipped floppies"
```

---

### Task 7: Volume writer and identity round-trip

**Files:**
- Modify: `vm/ufs_build.py`
- Modify: `vm/test_ufs_build.py`

**Interfaces:**
- Consumes: everything from Task 6, plus `ufs_extract.Node`.
- Produces: `ufs_build.build(template_path, nodes) -> bytes` — a complete volume image the same length as the template.

Layout rules, all forced by the cloned geometry:

- Fragments 0 through `dblkno - 1` are metadata (boot area, superblock at `sblkno`, cg block at `cblkno`, inode table at `iblkno`); the cylinder summary occupies `cssize` bytes at `csaddr`. Copy all of that region from the template, then overwrite the parts we regenerate.
- Data allocation starts at the first fragment after the cylinder summary and runs upward. Files take whole blocks except for a fragmented tail; directories take whole blocks.
- Inode numbers are assigned in node order starting at 2 (root). Inode 1 is reserved and stays unused-but-marked, as `newfs` leaves it.
- A file needs a single indirect block once it exceeds 12 direct blocks; `nindir` is 2048 here, so one indirect block covers any file these volumes can hold. Double indirect is refused.
- `di_blocks` counts every fragment charged to the inode, indirect blocks included.

- [ ] **Step 1: Write the failing test**

Append to `vm/test_ufs_build.py`, before the `if __name__` block:

```python
import tempfile

import ufs_extract


def _rebuild_to_temp(path):
    nodes = ufs_extract.extract(path)
    image = ufs_build.build(path, nodes)
    fd, out = tempfile.mkstemp(suffix=".img")
    os.close(fd)
    with open(out, "wb") as f:
        f.write(image)
    return out


class TestIdentityRoundTrip(unittest.TestCase):
    def _assert_same_tree(self, original, rebuilt):
        a = ufs_extract.extract(original)
        b = ufs_extract.extract(rebuilt)
        self.assertEqual([n.path for n in a], [n.path for n in b])
        for x, y in zip(a, b):
            self.assertEqual((x.path, x.kind, x.mode, x.uid, x.gid),
                             (y.path, y.kind, y.mode, y.uid, y.gid))
            self.assertEqual(x.data, y.data, "contents differ for %s" % x.path)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_installation_floppy_rebuilds_identically(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            self.assertEqual(os.path.getsize(out), os.path.getsize(FLOPPY))
            self._assert_same_tree(FLOPPY, out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(DRIVERS), "install media not present")
    def test_driver_disk_rebuilds_identically(self):
        out = _rebuild_to_temp(DRIVERS)
        try:
            self._assert_same_tree(DRIVERS, out)
        finally:
            os.unlink(out)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_rebuilt_summaries_are_self_consistent(self):
        out = _rebuild_to_temp(FLOPPY)
        try:
            g, cg, blksfree = _read_cg(out)
            t = ufs_build.recompute_cg_tables(g, blksfree)
            _ndir, nbfree, _nifree, nffree = struct.unpack_from("<4i", cg, 24)
            self.assertEqual((t.nbfree, t.nffree), (nbfree, nffree))
        finally:
            os.unlink(out)


class TestRefusals(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_refuses_symlink(self):
        nodes = ufs_extract.extract(FLOPPY)
        nodes.append(ufs_extract.Node("/link", "lnk", 0o120755, 0, 0, 0, "target"))
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.build(FLOPPY, nodes)

    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_refuses_oversized_tree(self):
        nodes = ufs_extract.extract(FLOPPY)
        nodes = [n._replace(data=b"\0" * 900000) if n.path == "/mach_kernel.rcz" else n
                 for n in nodes]
        nodes.append(ufs_extract.Node("/big", "reg", 0o100644, 0, 0, 0, b"\0" * 900000))
        with self.assertRaises(ufs_build.BuildError):
            ufs_build.build(FLOPPY, nodes)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_ufs_build.TestIdentityRoundTrip -v
```

Expected: FAIL with `AttributeError: module 'ufs_build' has no attribute 'build'`.

- [ ] **Step 3: Write minimal implementation**

Append to `vm/ufs_build.py`:

```python
def _roundup(n, m):
    return (n + m - 1) // m * m


def _dirent(ino, name, kind):
    namlen = len(name)
    reclen = 8 + _roundup(namlen + 1, 4)
    dtype = {"dir": 4, "reg": 8, "lnk": 10}[kind]
    rec = bytearray(struct.pack("<IHBB", ino, reclen, dtype, namlen))
    rec += name.encode("ascii")
    rec += b"\0" * (reclen - 8 - namlen)
    return bytes(rec)


def _dir_block(entries):
    """Pack directory entries into DIRBLKSIZ chunks.

    No entry may straddle a chunk boundary; the last entry in each chunk has
    its record length stretched to the boundary.
    """
    out = bytearray()
    chunk = bytearray()
    for rec in entries:
        if len(chunk) + len(rec) > DIRBLKSIZ:
            struct.pack_into("<H", chunk, len(chunk) - _last_reclen(chunk) + 4,
                             DIRBLKSIZ - (len(chunk) - _last_reclen(chunk)))
            chunk += b"\0" * (DIRBLKSIZ - len(chunk))
            out += chunk
            chunk = bytearray()
        chunk += rec
    if chunk:
        struct.pack_into("<H", chunk, len(chunk) - _last_reclen(chunk) + 4,
                         DIRBLKSIZ - (len(chunk) - _last_reclen(chunk)))
        chunk += b"\0" * (DIRBLKSIZ - len(chunk))
        out += chunk
    return bytes(out)


def _last_reclen(chunk):
    """Record length of the final entry already packed into chunk."""
    p = 0
    last = 0
    while p < len(chunk):
        reclen = struct.unpack_from("<H", chunk, p + 4)[0]
        last = reclen
        p += reclen
    return last


def _dinode(ino_size, db, ib, blocks, mtime, mode, uid, gid, nlink):
    raw = bytearray(rhap_image.DINODE_SIZE)
    struct.pack_into("<Hh", raw, 0, mode, nlink)
    struct.pack_into("<Q", raw, 8, ino_size)
    for off in (16, 24, 32):
        struct.pack_into("<i", raw, off, mtime)
    struct.pack_into("<12i", raw, 40, *db)
    struct.pack_into("<3i", raw, 88, *ib)
    struct.pack_into("<i", raw, 104, blocks)
    struct.pack_into("<2I", raw, 112, uid, gid)
    return bytes(raw)


def build(template_path, nodes, total_frags=None):
    g = read_geometry(template_path)
    if total_frags is not None:
        raise BuildError(
            "resizing is not implemented; apply Task 7a of the plan first")
    with open(template_path, "rb") as f:
        image = bytearray(f.read())
    with rhap_image.Image(template_path) as img:
        part = img.part_start

    for node in nodes:
        if node.kind not in ("dir", "reg"):
            raise BuildError(
                "%s is a %s; this writer handles only directories and regular "
                "files (neither install floppy contains anything else)"
                % (node.path, node.kind))

    ino_of = {}
    for i, node in enumerate(nodes):
        ino_of[node.path] = 2 + i
    if 2 + len(nodes) - 1 >= g.ipg:
        raise BuildError("tree needs %d inodes, volume holds %d"
                         % (len(nodes) + 1, g.ipg))

    children = collections.defaultdict(list)
    for node in nodes[1:]:
        parent = node.path.rsplit("/", 1)[0] or "/"
        children[parent].append(node)

    # Serialise every object's bytes before allocating, so the allocator sees
    # final sizes.
    payload = {}
    for node in nodes:
        if node.kind == "dir":
            if node.path == "/":
                parent = "/"
            else:
                parent = node.path.rsplit("/", 1)[0] or "/"
            entries = [_dirent(ino_of[node.path], ".", "dir"),
                       _dirent(ino_of[parent], "..", "dir")]
            for child in children[node.path]:
                entries.append(_dirent(ino_of[child.path],
                                       child.path.rsplit("/", 1)[1], child.kind))
            payload[node.path] = _dir_block(entries)
        else:
            payload[node.path] = node.data

    # Data begins after the cylinder summary.  Whole blocks must start on a
    # multiple of fs_frag, so allocation starts at the next block boundary; the
    # few fragments before it stay genuinely free rather than being written off.
    first_data = g.csaddr + _roundup(g.cssize, g.fsize) // g.fsize
    next_frag = _roundup(first_data, g.frag)
    limit = g.size

    blksfree = bytearray(b"\xff" * ((g.fpg + 7) // 8))
    for f in range(0, first_data):
        blksfree[f // 8] &= ~(1 << (f % 8)) & 0xff
    for f in range(g.size, g.fpg):
        blksfree[f // 8] &= ~(1 << (f % 8)) & 0xff

    def alloc(nfrags):
        nonlocal next_frag
        start = next_frag
        if start + nfrags > limit:
            raise BuildError(
                "tree does not fit: needed %d more fragments at %d, volume ends "
                "at %d" % (nfrags, start, limit))
        for f in range(start, start + nfrags):
            blksfree[f // 8] &= ~(1 << (f % 8)) & 0xff
        next_frag += nfrags
        return start

    inodes = {}
    for node in nodes:
        data = payload[node.path]
        nfrags = _roundup(len(data), g.fsize) // g.fsize
        whole = nfrags // g.frag
        tail = nfrags % g.frag
        db = [0] * 12
        ib = [0] * 3
        charged = 0
        blocks = []
        for _ in range(whole):
            blocks.append(alloc(g.frag))
            charged += g.frag
        if tail:
            blocks.append(alloc(tail))
            charged += tail
        if len(blocks) > 12 + g.nindir:
            raise BuildError("%s needs double indirect blocks" % node.path)
        for i, b in enumerate(blocks[:12]):
            db[i] = b
        if len(blocks) > 12:
            ind = alloc(g.frag)
            charged += g.frag
            ib[0] = ind
            table = bytearray(g.bsize)
            for i, b in enumerate(blocks[12:]):
                struct.pack_into("<i", table, i * 4, b)
            image[part + ind * g.fsize:part + ind * g.fsize + g.bsize] = table
        off = 0
        for b in blocks:
            chunk = data[off:off + g.bsize]
            image[part + b * g.fsize:part + b * g.fsize + len(chunk)] = chunk
            off += g.bsize
        nlink = 2 + sum(1 for c in children[node.path] if c.kind == "dir") \
            if node.kind == "dir" else 1
        inodes[node.path] = _dinode(len(data), db, ib, charged,
                                    node.mtime, node.mode, node.uid, node.gid,
                                    nlink)

    # Inode table.
    table = bytearray(g.ipg * rhap_image.DINODE_SIZE)
    inosused = bytearray((g.ipg + 7) // 8)
    for i in range(2):
        inosused[i // 8] |= 1 << (i % 8)
    ndir = 0
    for node in nodes:
        ino = ino_of[node.path]
        table[ino * rhap_image.DINODE_SIZE:(ino + 1) * rhap_image.DINODE_SIZE] = \
            inodes[node.path]
        inosused[ino // 8] |= 1 << (ino % 8)
        if node.kind == "dir":
            ndir += 1
    image[part + g.iblkno * g.fsize:
          part + g.iblkno * g.fsize + len(table)] = table

    # Cylinder group.
    cg = bytearray(image[part + g.cblkno * g.fsize:
                         part + g.cblkno * g.fsize + g.bsize])
    btotoff, boff, iusedoff, freeoff = struct.unpack_from("<4i", cg, 84)
    t = recompute_cg_tables(g, blksfree)
    nifree = g.ipg - (len(nodes) + 2)
    struct.pack_into("<4i", cg, 24, ndir, t.nbfree, nifree, t.nffree)
    struct.pack_into("<%di" % g.frag, cg, 52, *t.frsum)
    struct.pack_into("<%di" % g.cpg, cg, btotoff, *t.blktot)
    struct.pack_into("<%dh" % (g.cpg * g.nrpos), cg, boff, *t.blks)
    cg[iusedoff:iusedoff + len(inosused)] = inosused
    cg[freeoff:freeoff + len(blksfree)] = blksfree
    image[part + g.cblkno * g.fsize:
          part + g.cblkno * g.fsize + g.bsize] = cg

    # Superblock counters and the cylinder summary block.
    sb_off = part + rhap_image.SBOFF
    struct.pack_into("<4i", image, sb_off + 192, ndir, t.nbfree, nifree, t.nffree)
    struct.pack_into("<4i", image, part + g.csaddr * g.fsize,
                     ndir, t.nbfree, nifree, t.nffree)

    return bytes(image)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_ufs_build -v
```

Expected: PASS, 8 tests.

The identity round-trip is the one that matters. If contents differ for a directory, the fault is in `_dir_block` chunking; if they differ for a large file, it is the indirect block. If `test_rebuilt_summaries_are_self_consistent` fails, the bitmap written into the cg disagrees with the one the allocator used.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_build.py vm/test_ufs_build.py
git commit -m "vm: write UFS volumes from a node tree and verify the identity round-trip"
```

---

### Task 7a: Resize to 2.88 MB — only if Task 3's gate failed

**Files:**
- Modify: `vm/ufs_build.py`
- Modify: `vm/test_ufs_build.py`

**Interfaces:**
- Produces: `ufs_build.build(template_path, nodes, total_frags=None)` — when `total_frags` is given, the output volume is sized for that many fragments instead of the template's `fs_size`.

**Skip this task entirely if Task 3 printed "VERDICT: fits 1.44 MB".**

A 2.88 MB floppy is 2880 sectors of 512 bytes; with `fs_fsize` 1024 and the label's `front` of 96 sectors, the partition holds 2880 - 96 = 2784 fragments. The geometry fields that must change are `fs_size`, `fs_dsize`, `fs_fpg`, `fs_ncyl`, `fs_cpg`, and the label's `p_size`; `fs_ntrak`, `fs_nsect` and `fs_spc` describe the physical geometry (2 heads, 36 sectors per track, 72 sectors per cylinder).

- [ ] **Step 1: Write the failing test**

Append to `vm/test_ufs_build.py`:

```python
class TestResize(unittest.TestCase):
    @unittest.skipUnless(_present(FLOPPY), "install media not present")
    def test_builds_a_2880k_volume(self):
        nodes = ufs_extract.extract(FLOPPY)
        image = ufs_build.build(FLOPPY, nodes, total_frags=2784)
        self.assertEqual(len(image), 2880 * 512)
        fd, out = tempfile.mkstemp(suffix=".img")
        os.close(fd)
        try:
            with open(out, "wb") as f:
                f.write(image)
            self.assertEqual([n.path for n in ufs_extract.extract(out)],
                             [n.path for n in nodes])
            g = ufs_build.read_geometry(out)
            self.assertEqual(g.size, 2784)
        finally:
            os.unlink(out)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_ufs_build.TestResize -v
```

Expected: FAIL with `TypeError: build() got an unexpected keyword argument 'total_frags'`.

- [ ] **Step 3: Write minimal implementation**

`build` already accepts `total_frags`; Task 7 left it raising `BuildError`. Delete that guard:

```python
    if total_frags is not None:
        raise BuildError(
            "resizing is not implemented; apply Task 7a of the plan first")
```

and, immediately after `image = bytearray(f.read())`, insert:

```python
    if total_frags is not None:
        sectors_per_frag = g.fsize // 512
        image += bytearray((total_frags - g.size) * g.fsize)
        sb_off = part + rhap_image.SBOFF
        struct.pack_into("<i", image, sb_off + 36, total_frags)
        struct.pack_into("<i", image, sb_off + 40,
                         total_frags - (g.dblkno + g.cssize // g.fsize))
        struct.pack_into("<i", image, sb_off + 188, total_frags)
        cyls = total_frags * g.nspf // g.spc
        struct.pack_into("<i", image, sb_off + 176, cyls)
        struct.pack_into("<i", image, sb_off + 180, cyls)
        struct.pack_into("<i", image, sb_off + 164, 2)
        struct.pack_into("<i", image, sb_off + 168, 36)
        struct.pack_into("<i", image, sb_off + 172, 72)
        # NeXT label p_size is big-endian at label_offset + 194.
        with rhap_image.Image(template_path) as probe:
            label_off = probe.label_offset
        struct.pack_into(">i", image, label_off + 194, total_frags)
        g = read_geometry_from_bytes(bytes(image))
```

and add the helper beside `read_geometry`:

```python
def read_geometry_from_bytes(image):
    """Same as read_geometry, for an in-memory volume being constructed."""
    import tempfile
    fd, path = tempfile.mkstemp(suffix=".img")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(image)
        return read_geometry(path)
    finally:
        os.unlink(path)
```

with `import os` added at the top of the module.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_ufs_build -v
```

Expected: PASS, 9 tests. The cylinder group's per-cylinder tables grow with `cpg`; if `struct.error` appears at the `cg_blktot` pack, the cg block can no longer hold the enlarged tables and `fs_cgsize` needs raising too.

- [ ] **Step 5: Commit**

```bash
git add vm/ufs_build.py vm/test_ufs_build.py
git commit -m "vm: build 2.88 MB install floppies when the kernel outgrows 1.44 MB"
```

---

### Task 8: Strip the EIDE driver at build time

**Files:**
- Modify: `vm/build-i386-kernel-eide.sh:75-100`

**Interfaces:**
- Produces: `out/i386/drvEIDE/EIDE.config/EIDE_reloc` at roughly stock size (~121 KB rather than 856 KB).

`out/i386/drvEIDE/EIDE.config/EIDE_reloc` is 856,404 bytes of which 748,208 is symbol table; the shipped driver is 121,056 with the same 108 KB of code. Without this the driver disk cannot hold it: that volume has 483,328 bytes free plus the 84,992 the current `.rcz` occupies, and an rcz stream of the unstripped driver would exceed that.

This step needs the Rhapsody build guest, because a relocatable driver must keep its globals, undefineds and relocations for the kernel loader and `strip -x` is the tool that does that correctly. Guest connection details are in `vm/vm.conf`.

- [ ] **Step 1: Add the strip step**

In `vm/build-i386-kernel-eide.sh`, in the `=== build i386 drvEIDE ===` section, after the `while read d; do ... done < /tmp/eide-found` loop that copies the bundle into `$OUT/drvEIDE/`, add:

```sh
# Drop local symbols. The kernel server loader needs globals, undefineds and
# relocations; it does not need the ~20k local symbols a debug build carries,
# and they do not fit on the 1.44MB driver floppy.
for r in "$OUT"/drvEIDE/EIDE.config/*_reloc; do
	[ -f "$r" ] || continue
	before=`wc -c < "$r"`
	strip -x "$r"
	after=`wc -c < "$r"`
	echo "stripped $r: $before -> $after bytes"
done
```

- [ ] **Step 2: Run the build on the guest**

```bash
cd vm && plink -batch -pw "$(sed -n 's/^Password=//p' vm.conf)" root@"$(sed -n 's/^Host=//p' vm.conf)" 'sh /build/source/src/rbuild-1/build-i386-kernel-eide.sh' 2>&1 | tail -40
```

Expected: a `stripped .../EIDE_reloc: 856404 -> NNNNNN bytes` line with the result under 200,000.

- [ ] **Step 3: Retrieve the stripped driver**

```bash
cd vm && pscp -batch -pw "$(sed -n 's/^Password=//p' vm.conf)" -r root@"$(sed -n 's/^Host=//p' vm.conf)":/build/out/i386/drvEIDE ../out/i386/
```

- [ ] **Step 4: Verify it fits**

```bash
cd vm && python -c "
import os, rcz, rhap_image
p='../out/i386/drvEIDE/EIDE.config/EIDE_reloc'
raw=open(p,'rb').read()
print('stripped   %d bytes' % len(raw))
print('rcz stream %d bytes' % len(rcz.compress(raw)))
with rhap_image.Image('install/rhapsody_dr2_x86.iso') as i:
    print('ISO cap    %d bytes' % i.max_writable(i.resolve('/private/Drivers/i386/EIDE.config/EIDE_reloc')))
"
```

Expected: the stripped size is at or below the ISO cap of 122,880, and the rcz stream is small enough that the driver disk's 483,328 free bytes plus its current 84,992 accommodate it.

- [ ] **Step 5: Commit**

```bash
git add vm/build-i386-kernel-eide.sh
git commit -m "vm: strip local symbols from the built EIDE driver so it fits the install media"
```

---

### Task 9: Build the two floppies

**Files:**
- Create: `vm/build_media.py`

**Interfaces:**
- Consumes: `rcz.compress`, `ufs_extract.extract`, `ufs_build.build`.
- Produces: `build_media.MANIFEST`; `build_media.build_floppy(master, replacements, out_path, total_frags=None) -> None`, where `replacements` maps an absolute path inside the volume to the `bytes` that replace it.

- [ ] **Step 1: Write the failing test**

Create `vm/test_build_media.py`:

```python
import os
import tempfile
import unittest

import build_media
import ufs_extract

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img")


class TestBuildFloppy(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(FLOPPY), "install media not present")
    def test_replaces_a_file_and_keeps_the_rest(self):
        fd, out = tempfile.mkstemp(suffix=".img")
        os.close(fd)
        try:
            build_media.build_floppy(FLOPPY, {"/.hidden": b"replaced\n"}, out)
            nodes = {n.path: n for n in ufs_extract.extract(out)}
            self.assertEqual(nodes["/.hidden"].data, b"replaced\n")
            self.assertEqual(len(nodes["/mach_kernel.rcz"].data), 1052315)
        finally:
            os.unlink(out)

    @unittest.skipUnless(os.path.exists(FLOPPY), "install media not present")
    def test_unknown_path_is_refused(self):
        fd, out = tempfile.mkstemp(suffix=".img")
        os.close(fd)
        try:
            with self.assertRaises(build_media.MediaError):
                build_media.build_floppy(FLOPPY, {"/nope": b""}, out)
        finally:
            os.unlink(out)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_build_media -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'build_media'`.

- [ ] **Step 3: Write minimal implementation**

Create `vm/build_media.py`:

```python
"""Build modified Rhapsody DR2 install media from the pristine masters.

The masters in vm/install are never written; everything lands in
vm/install/build.  See docs/superpowers/specs/2026-07-28-install-media-injection-design.md.
"""

import os
import shutil
import sys

import rcz
import rhap_image
import rhap_inject
import ufs_build
import ufs_extract

HERE = os.path.dirname(os.path.abspath(__file__))
MASTERS = os.path.join(HERE, "install")
BUILD = os.path.join(MASTERS, "build")
ARTIFACTS = os.path.join(HERE, "..", "out", "i386")

KERNEL = os.path.join(ARTIFACTS, "mach_kernel")
EIDE_RELOC = os.path.join(ARTIFACTS, "drvEIDE", "EIDE.config", "EIDE_reloc")

# Which artifact replaces which path on which medium.  Widening the injection
# is an edit here, not a code change.
MANIFEST = {
    "InstallationFloppy": {"/mach_kernel.rcz": (KERNEL, "rcz")},
    "DriverDisk": {
        "/private/Drivers/i386/EIDE.config/EIDE_reloc.rcz": (EIDE_RELOC, "rcz"),
    },
    "ISO": {
        "/private/Drivers/i386/EIDE.config/EIDE_reloc": (EIDE_RELOC, "raw"),
    },
}


class MediaError(Exception):
    pass


def _payload(source, encoding):
    with open(source, "rb") as f:
        raw = f.read()
    return rcz.compress(raw) if encoding == "rcz" else raw


def build_floppy(master, replacements, out_path, total_frags=None):
    nodes = ufs_extract.extract(master)
    known = {n.path for n in nodes}
    for path in replacements:
        if path not in known:
            raise MediaError("%s does not exist in %s; this builder replaces "
                             "files, it does not create them" % (path, master))
    nodes = [n._replace(data=replacements.get(n.path, n.data))
             if n.kind == "reg" else n for n in nodes]
    image = ufs_build.build(master, nodes, total_frags=total_frags)
    with open(out_path, "wb") as f:
        f.write(image)


def resolve(manifest_entry):
    return {path: _payload(src, enc) for path, (src, enc) in manifest_entry.items()}


def main(argv):
    total_frags = None
    if "--2880" in argv:
        total_frags = 2784
    os.makedirs(BUILD, exist_ok=True)
    for name, master_name in (
            ("InstallationFloppy", "rhapsody_dr2_x86_InstallationFloppy.img"),
            ("DriverDisk", "rhapsody_dr2_x86_DriverDisk.img")):
        master = os.path.join(MASTERS, master_name)
        out = os.path.join(BUILD, master_name)
        frags = total_frags if name == "InstallationFloppy" else None
        build_floppy(master, resolve(MANIFEST[name]), out, total_frags=frags)
        print("%s -> %s (%d bytes)" % (name, out, os.path.getsize(out)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_build_media -v
```

Expected: PASS, 2 tests.

Then build the real floppies (add `--2880` only if Task 3's gate failed):

```bash
cd vm && python build_media.py
```

Expected: two lines reporting 1474560-byte outputs in `vm/install/build/`.

- [ ] **Step 5: Commit**

```bash
git add vm/build_media.py vm/test_build_media.py
git commit -m "vm: build install floppies carrying the rebuilt kernel and EIDE driver"
```

---

### Task 10: Patch the CD

**Files:**
- Modify: `vm/rhap_inject.py:23-61` (`check_target`)
- Modify: `vm/build_media.py`

**Interfaces:**
- Consumes: `rhap_inject.write_file`, `rhap_inject.graft_file`, the floppies from Task 9.
- Produces: `build_media.patch_iso(master, out_path, donor_path) -> None`; `build_media.find_donors(image_path, need_bytes) -> list[(path, size)]`.

`check_target` currently refuses every path except `vm/work/test.img`, so it must learn about `vm/install/build/` before it can touch the CD copy. It must keep refusing the masters, `golden.img` and `rhapsody.vmdk`.

The CD's `/mach_kernel` is 1,404,116 bytes against the new kernel's 1,472,800, so it is grafted onto a donor. The donor must be a regular file, hole-free, `nlink == 1`, at least as large as the payload, and not used by the install path.

- [ ] **Step 1: Write the failing test**

Create `vm/test_iso_patch.py`:

```python
import os
import unittest

import rhap_inject

HERE = os.path.dirname(os.path.abspath(__file__))


class TestCheckTarget(unittest.TestCase):
    def test_allows_build_output(self):
        target = os.path.join(HERE, "install", "build", "rhapsody_dr2_x86.iso")
        os.makedirs(os.path.dirname(target), exist_ok=True)
        self.assertTrue(rhap_inject.check_target(target))

    def test_still_allows_work_image(self):
        self.assertTrue(rhap_inject.check_target(
            os.path.join(HERE, "work", "test.img")))

    def test_refuses_the_master_iso(self):
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject.check_target(
                os.path.join(HERE, "install", "rhapsody_dr2_x86.iso"))

    def test_refuses_golden(self):
        with self.assertRaises(rhap_inject.SafetyError):
            rhap_inject.check_target(os.path.join(HERE, "golden.img"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd vm && python -m unittest test_iso_patch -v
```

Expected: `test_allows_build_output` FAILS with `SafetyError`; the other three pass.

- [ ] **Step 3: Widen `check_target`**

Replace the body of `check_target` in `vm/rhap_inject.py` between the docstring and the `for name in ("golden.img", "rhapsody.vmdk")` loop with:

```python
    here = os.path.dirname(os.path.abspath(__file__))
    resolved = os.path.normcase(os.path.realpath(image_path))

    allowed = os.path.normcase(os.path.realpath(os.path.join(here, "work", "test.img")))
    build_dir = os.path.normcase(
        os.path.realpath(os.path.join(here, "install", "build"))) + os.sep

    if resolved != allowed and not resolved.startswith(build_dir):
        raise SafetyError(
            "refusing to write %s; only vm/work/test.img and files under "
            "vm/install/build/ may be modified" % image_path
        )
```

Update the docstring's first line to `"""Refuse to write anything but vm/work/test.img or vm/install/build/*."""` and keep the `golden.img` / `rhapsody.vmdk` same-file check that follows unchanged.

- [ ] **Step 4: Run test to verify it passes**

```bash
cd vm && python -m unittest test_iso_patch test_rhap_inject -v
```

Expected: PASS. `test_rhap_inject` must still pass unchanged — if one of its refusal tests now fails, the allowlist is too wide.

- [ ] **Step 5: Add ISO patching to `build_media.py`**

Append to `vm/build_media.py`, before `main`:

```python
ISO_NAME = "rhapsody_dr2_x86.iso"
DISK_IMAGES = "/System/Installation/DiskImages/"


def find_donors(image_path, need_bytes, limit=10):
    """Regular files big enough to host a grafted payload.

    A donor must be hole-free with exactly one name, so overwriting it cannot
    disturb anything else.  Everything under /System/Installation and
    /private/Drivers is excluded: the installer reads those.
    """
    out = []
    with rhap_image.Image(image_path) as img:
        stack = ["/System/Documentation", "/System/Demos"]
        while stack and len(out) < limit:
            path = stack.pop()
            try:
                entries = img.listdir(path)
            except FileNotFoundError:
                continue
            for name, ino, dtype in entries:
                if name in (".", ".."):
                    continue
                child = path.rstrip("/") + "/" + name
                if dtype == 4:
                    stack.append(child)
                    continue
                inode = img.inode(ino)
                if not inode.is_reg() or inode.nlink != 1:
                    continue
                if inode.size < need_bytes:
                    continue
                if any(f == 0 for f in img.frags(inode)):
                    continue
                out.append((child, inode.size))
    return out


def patch_iso(master, out_path, donor_path):
    shutil.copyfile(master, out_path)
    payloads = resolve(MANIFEST["ISO"])
    with open(KERNEL, "rb") as f:
        kernel = f.read()
    img = rhap_image.Image(out_path, writable=True)
    try:
        for path, data in payloads.items():
            rhap_inject.write_file(img, path, data)
            print("put   %s (%d bytes)" % (path, len(data)))
        for name in ("rhapsody_dr2_x86_InstallationFloppy.img",
                     "rhapsody_dr2_x86_DriverDisk.img"):
            embedded = DISK_IMAGES + ("RhapsodyInstall.image"
                                      if "Installation" in name
                                      else "RhapsodyDrivers.image")
            with open(os.path.join(BUILD, name), "rb") as f:
                rhap_inject.write_file(img, embedded, f.read())
            print("put   %s" % embedded)
        rhap_inject.graft_file(img, "/mach_kernel", donor_path, kernel)
        print("graft /mach_kernel onto %s (%d bytes)" % (donor_path, len(kernel)))
    finally:
        img.close()
```

and extend `main` to run it after the floppies:

```python
    iso_master = os.path.join(MASTERS, ISO_NAME)
    iso_out = os.path.join(BUILD, ISO_NAME)
    with open(KERNEL, "rb") as f:
        need = len(f.read())
    donors = find_donors(iso_master, need)
    if not donors:
        raise MediaError("no donor file of at least %d bytes found on the CD" % need)
    print("donor candidates: %s" % ", ".join("%s (%d)" % d for d in donors[:3]))
    patch_iso(iso_master, iso_out, donors[0][0])
    print("ISO -> %s" % iso_out)
```

- [ ] **Step 6: Build the CD**

```bash
cd vm && python build_media.py
```

Expected: the two floppy lines, a donor candidate list, four `put` lines, one `graft` line, and a 630 MB `vm/install/build/rhapsody_dr2_x86.iso`. Copying 630 MB takes a moment.

Verify the result reads back:

```bash
cd vm && export MSYS2_ARG_CONV_EXCL='*' && python rhap_image.py install/build/rhapsody_dr2_x86.iso stat /mach_kernel
```

Expected: `size 1472800`.

- [ ] **Step 7: Commit**

```bash
git add vm/rhap_inject.py vm/build_media.py vm/test_iso_patch.py
git commit -m "vm: patch the install CD with the rebuilt kernel, driver and floppies"
```

---

### Task 11: Boot the installer and install

**Files:**
- Create: `vm/run-install.py`

**Interfaces:**
- Consumes: the three images in `vm/install/build/`.
- Produces: nothing importable; a QEMU run and its captures.

This is the success criterion from the spec. `qemu-shot.py` boots `vm/work/test.img` specifically, so the installer run needs its own launcher: a blank target disk, the built floppy in drive A, the built CD, and serial captured.

- [ ] **Step 1: Create the blank target disk**

```bash
cd vm && qemu-img create -f raw work/install-target.img 2G
```

Expected: `Formatting 'work/install-target.img', fmt=raw size=2147483648`.

- [ ] **Step 2: Write the launcher**

Create `vm/run-install.py`:

```python
"""Boot the rebuilt install media against a blank IDE disk.

Screenshots land in the output directory alongside the serial log, same
convention as qemu-shot.py.  The floppy has to be swapped for the driver disk
partway through, which the installer prompts for; use the QMP monitor for that
rather than restarting.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "install", "build")


def main(argv):
    outdir = argv[1] if len(argv) > 1 else os.path.join(HERE, "shots-install")
    os.makedirs(outdir, exist_ok=True)
    target = os.path.join(HERE, "work", "install-target.img")
    if not os.path.exists(target):
        print("create the target first: qemu-img create -f raw work/install-target.img 2G",
              file=sys.stderr)
        return 2
    cmd = [
        "qemu-system-i386",
        "-m", "128",
        "-drive", "file=%s,format=raw,if=ide,index=0,media=disk" % target,
        "-drive", "file=%s,format=raw,if=ide,index=2,media=cdrom"
                  % os.path.join(BUILD, "rhapsody_dr2_x86.iso"),
        "-drive", "file=%s,format=raw,if=floppy,index=0"
                  % os.path.join(BUILD, "rhapsody_dr2_x86_InstallationFloppy.img"),
        "-boot", "a",
        "-serial", "null",
        "-serial", "file:%s" % os.path.join(outdir, "serial.log"),
        "-qmp", "tcp:127.0.0.1:4444,server,nowait",
    ]
    print(" ".join(cmd))
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
```

- [ ] **Step 3: Boot and work through the installer**

```bash
cd vm && python run-install.py shots-install
```

Check these in order, and stop at the first that fails:

1. The boot prompt appears and the kernel loads — proves the rebuilt floppy is a valid bootable UFS volume.
2. The kernel reaches driver loading rather than panicking — proves the rcz stream is correct.
3. The installer prompts for the driver disk; swap it in at the QMP monitor with `change floppy0 <path to build/rhapsody_dr2_x86_DriverDisk.img>`.
4. `EIDE` appears in the driver list and attaches. Watch `shots-install/serial.log` for the `Unknown PCI IDE controller` and `interrupt timeout` strings from `docs/drivers/drvEIDE-issues.md`; neither should appear.
5. The installer lists the 2 GB IDE disk as an install target.
6. The install runs to completion.

- [ ] **Step 4: Boot the installed system unaided**

```bash
cd vm && qemu-system-i386 -m 128 -drive file=work/install-target.img,format=raw,if=ide,index=0,media=disk -boot c -serial null -serial stdio
```

Expected: the system boots from IDE to a login prompt with no floppy, no CD, no graft and no `rc.boot` edits. This is the definition of done.

- [ ] **Step 5: Record the outcome and commit**

Add a `## Outcome` section to `docs/superpowers/specs/2026-07-28-install-media-injection-design.md` recording which of the six checks passed, with the relevant serial-log lines for any that did not.

```bash
git add vm/run-install.py docs/superpowers/specs/2026-07-28-install-media-injection-design.md
git commit -m "vm: boot the rebuilt install media and record the install outcome"
```

---

## Notes for the implementer

- `vm/install/build/` should be added to `.gitignore` if it is not already covered; the outputs are 630 MB and are reproducible from the masters.
- `vm/work/install-target.img` is likewise disposable and should not be committed.
- The graft leaves `/private/tftpboot/mach_kernel` on the CD pointing at the stock kernel. That is deliberate — it is the netboot copy and this install path does not use it.
- `RhapsodyNetInstall.image` and `RhapsodyNetDrivers.image` stay stock, so the built CD is internally inconsistent for netboot. Also deliberate, and recorded in the spec's "Out of scope".
