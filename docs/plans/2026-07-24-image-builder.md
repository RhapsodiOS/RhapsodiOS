# Bootable Image Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a host-side Python tool that turns a flat repository of `.deb`/`.apk` packages into a raw disk image that boots a RhapsodiOS i386 build in `qemu.exe`.

**Architecture:** A staged pipeline (index → solve → stage → dpkg-db → UFS1 write → disk assemble). Each stage has a defined input/output and is testable in isolation. The filesystem is a **big-endian UFS1** laid out in a **single cylinder group**; the disk is MBR + a NeXT `disk_label` + `boot0`/`boot1`/`boot` + the spliced UFS partition.

**Tech Stack:** Python 3.13 standard library only (`struct`, `tarfile`, `gzip`, `hashlib`, `pathlib`, `argparse`). Tests use `pytest` 9.x. No C compiler, no third-party runtime deps.

**Spec:** `docs/specs/2026-07-24-image-builder-design.md`

## Global Constraints

- Python 3.13, **standard library only** at runtime; `pytest` for tests.
- All on-disk multi-byte integers are **big-endian** (`>` in `struct`).
- Struct field orders/types are copied verbatim from these headers — do not
  invent fields: `src/kernel-7/bsd/ufs/ffs/fs.h` (`struct fs`, `struct csum`,
  `struct cg`), `src/kernel-7/bsd/ufs/ufs/dinode.h` (`struct dinode`,
  `ROOTINO=2`, `NDADDR=12`, `NIADDR=3`), `src/kernel-7/bsd/ufs/ufs/dir.h`
  (`struct direct`, `MAXNAMLEN=255`), `src/kernel-7/bsd/dev/disk_label.h`
  (`disk_label_t`, `DL_V3=0x646c5633`, `MAXLBLLEN=24`),
  `src/kernel-7/bsd/sys/disktab.h` (`disktab`, `partition_t`, `NPART=8`,
  `NBOOTS=2`, `MAXDNMLEN=24`, `MAXTYPLEN=24`, `MAXBFLEN=24`, `MAXHNLEN=32`),
  `src/kernel-7/bsd/dev/i386/disk.h` (`fdisk_part`, `disk_blk0`,
  `DISK_SIGNATURE=0xAA55`, `FDISK_NPART=4`, `FDISK_ACTIVE=0x80`,
  `FDISK_NEXTNAME=0xA7`, `DISK_BOOTSZ=446`).
- Constants: `FS_MAGIC=0x011954`, `BBSIZE=SBSIZE=8192`, `SBOFF=8192`,
  `DEV_BSIZE=512`, `MINBSIZE=4096`, `MAXFRAG=8`, `MAXMNTLEN=512`,
  `MAXCSBUFS=31`, `CG_MAGIC=0x090255`, `DL_V3=0x646c5633`, `DISKLABEL=15`
  (partition-relative sector of the label).
- UFS defaults: `bsize=8192`, `fsize=1024`, `frag=8`, `di_size` 64-bit.
- **Single cylinder group only.** If content needs more than one cg, fail with
  a clear error (multi-cg is out of scope).
- Fail-fast everywhere: raise with a specific message; no silent fallbacks.
- All new code lives under `vm/imgbuild/`.
- Commit style (from CLAUDE.md): short subject prefixed with the subsystem,
  e.g. `imgbuild: ...`; no commit metadata.

## File Structure

```
vm/imgbuild/
  __init__.py
  build.py              # CLI / orchestrator
  repo.py               # PackageIndex + PackageReader (DebReader, ApkReader)
  solve.py              # selection + dependency resolution + presets
  stage.py              # payload extraction -> staging tree + FileManifest
  dpkgdb.py             # dpkg status/info synthesis
  devnodes.py           # static /dev node table
  ufs.py                # big-endian UFS1 writer + reader (single cg)
  disk.py               # MBR + fdisk + NeXT label + boot blocks + splice
  formats/
    __init__.py
    cstruct.py          # tiny declarative big-endian struct helper
    fdisk.py            # fdisk_part, disk_blk0 (MBR)
    label.py            # disk_label, disktab, partition (NeXT label)
    ufs_fs.py           # struct fs, csum, cg
    ufs_inode.py        # struct dinode, struct direct
  tests/
    __init__.py
    conftest.py
    fixtures/           # generated small deb / apk / staging trees
    test_*.py
```

**Test layout:** `vm/imgbuild/tests/conftest.py` inserts `vm/imgbuild` onto
`sys.path` so modules import flat (`import repo`, `from formats import ufs_fs`).
Run everything with: `python -m pytest vm/imgbuild/tests -v`.

---

### Task 1: Scaffold + declarative big-endian struct helper

**Files:**
- Create: `vm/imgbuild/__init__.py` (empty)
- Create: `vm/imgbuild/formats/__init__.py` (empty)
- Create: `vm/imgbuild/formats/cstruct.py`
- Create: `vm/imgbuild/tests/__init__.py` (empty)
- Create: `vm/imgbuild/tests/conftest.py`
- Test: `vm/imgbuild/tests/test_cstruct.py`

**Interfaces:**
- Produces: `CStruct(name, fields)` where `fields` is a list of
  `(fieldname, fmt)` tuples using `struct` codes **without** a byte-order
  prefix (byte order is forced big-endian internally). Methods:
  `CStruct.size -> int`, `CStruct.pack(dict) -> bytes` (missing keys → 0/zero
  bytes), `CStruct.unpack(bytes) -> dict`. Array fields use a repeat count in
  the fmt (e.g. `"12i"`) and pack/unpack as Python lists.

- [ ] **Step 1: Write conftest so flat imports work**

`vm/imgbuild/tests/conftest.py`:
```python
import os
import sys

# Make vm/imgbuild importable as flat modules (import repo, from formats import x)
IMGBUILD_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if IMGBUILD_DIR not in sys.path:
    sys.path.insert(0, IMGBUILD_DIR)
```

- [ ] **Step 2: Write the failing test**

`vm/imgbuild/tests/test_cstruct.py`:
```python
from formats.cstruct import CStruct

DEMO = CStruct("demo", [
    ("a", "i"),
    ("b", "H"),
    ("name", "4s"),
    ("arr", "3i"),
])

def test_size_is_big_endian_sum():
    # 4 + 2 + 4 + 12, with big-endian '>' there is NO padding
    assert DEMO.size == 4 + 2 + 4 + 12

def test_pack_unpack_roundtrip():
    raw = DEMO.pack({"a": 1, "b": 2, "name": b"boot", "arr": [7, 8, 9]})
    assert len(raw) == DEMO.size
    got = DEMO.unpack(raw)
    assert got["a"] == 1
    assert got["b"] == 2
    assert got["name"] == b"boot"
    assert got["arr"] == [7, 8, 9]

def test_missing_fields_default_to_zero():
    raw = DEMO.pack({})
    got = DEMO.unpack(raw)
    assert got == {"a": 0, "b": 0, "name": b"\x00\x00\x00\x00", "arr": [0, 0, 0]}

def test_big_endian_byte_order():
    raw = DEMO.pack({"a": 0x01020304})
    assert raw[:4] == b"\x01\x02\x03\x04"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_cstruct.py -v`
Expected: FAIL (`ModuleNotFoundError: No module named 'formats.cstruct'`).

- [ ] **Step 4: Implement `cstruct.py`**

`vm/imgbuild/formats/cstruct.py`:
```python
import struct


def _count(fmt):
    """Number of Python values a single fmt token maps to.

    's' packs as one bytes value regardless of its count; numeric array
    tokens like '3i' map to that many values.
    """
    num = "".join(ch for ch in fmt if ch.isdigit())
    n = int(num) if num else 1
    if fmt.endswith("s"):
        return 1
    return n


class CStruct:
    """Declarative fixed-layout struct, always big-endian (no padding)."""

    def __init__(self, name, fields):
        self.name = name
        self.fields = fields
        self._fmt = ">" + "".join(fmt for _, fmt in fields)
        self._struct = struct.Struct(self._fmt)
        self.size = self._struct.size

    def pack(self, values):
        flat = []
        for fieldname, fmt in self.fields:
            n = _count(fmt)
            if fmt.endswith("s"):
                v = values.get(fieldname, b"")
                if isinstance(v, str):
                    v = v.encode()
                flat.append(v)
            elif n == 1:
                flat.append(values.get(fieldname, 0))
            else:
                seq = list(values.get(fieldname, [0] * n))
                if len(seq) != n:
                    raise ValueError(
                        "%s.%s expects %d values, got %d"
                        % (self.name, fieldname, n, len(seq))
                    )
                flat.extend(seq)
        return self._struct.pack(*flat)

    def unpack(self, raw):
        flat = list(self._struct.unpack(raw[: self.size]))
        out = {}
        i = 0
        for fieldname, fmt in self.fields:
            n = _count(fmt)
            if fmt.endswith("s") or n == 1:
                out[fieldname] = flat[i]
                i += 1
            else:
                out[fieldname] = flat[i : i + n]
                i += n
        return out
```

- [ ] **Step 5: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_cstruct.py -v`
Expected: PASS (4 passed).

- [ ] **Step 6: Commit**

```bash
git add vm/imgbuild/__init__.py vm/imgbuild/formats/__init__.py vm/imgbuild/formats/cstruct.py vm/imgbuild/tests/__init__.py vm/imgbuild/tests/conftest.py vm/imgbuild/tests/test_cstruct.py
git commit -m "imgbuild: add declarative big-endian struct helper"
```

---

### Task 2: MBR / fdisk structs + builder

**Files:**
- Create: `vm/imgbuild/formats/fdisk.py`
- Test: `vm/imgbuild/tests/test_fdisk.py`

**Interfaces:**
- Consumes: `CStruct`.
- Produces:
  - `FDISK_PART` (`CStruct`, 16 bytes), `DISK_BLK0` (`CStruct`, 512 bytes).
  - `build_mbr(boot0: bytes, part_lba: int, part_sectors: int) -> bytes` →
    512-byte sector: `boot0` code (padded/truncated to 446 bytes), one active
    `0xA7` partition entry at index 0 (`relsect=part_lba`,
    `numsect=part_sectors`, CHS fields best-effort), `0xAA55` at bytes 510-511.
  - Constants `DISK_SIGNATURE=0xAA55`, `FDISK_ACTIVE=0x80`,
    `FDISK_NEXTNAME=0xA7`, `DISK_BOOTSZ=446`, `FDISK_NPART=4`.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_fdisk.py`:
```python
from formats import fdisk

def test_blk0_is_one_sector():
    assert fdisk.DISK_BLK0.size == 512
    assert fdisk.FDISK_PART.size == 16

def test_build_mbr_layout():
    boot0 = b"\xEB" + b"\x90" * 10  # short, must be zero-padded to 446
    mbr = fdisk.build_mbr(boot0, part_lba=63, part_sectors=1000)
    assert len(mbr) == 512
    assert mbr[:11] == boot0
    # signature
    assert mbr[510] == 0x55 and mbr[511] == 0xAA
    # first partition entry begins at offset 446
    ent = fdisk.FDISK_PART.unpack(mbr[446:462])
    assert ent["bootid"] == fdisk.FDISK_ACTIVE
    assert ent["systid"] == fdisk.FDISK_NEXTNAME
    assert ent["relsect"] == 63
    assert ent["numsect"] == 1000

def test_boot0_too_big_raises():
    import pytest
    with pytest.raises(ValueError):
        fdisk.build_mbr(b"\x00" * 447, part_lba=1, part_sectors=1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_fdisk.py -v`
Expected: FAIL (`No module named 'formats.fdisk'`).

- [ ] **Step 3: Implement `fdisk.py`**

`vm/imgbuild/formats/fdisk.py`:
```python
from formats.cstruct import CStruct

DISK_SIGNATURE = 0xAA55
FDISK_ACTIVE = 0x80
FDISK_NEXTNAME = 0xA7
DISK_BOOTSZ = 446
FDISK_NPART = 4

# src/kernel-7/bsd/dev/i386/disk.h struct fdisk_part (little-endian on x86 MBR;
# but relsect/numsect are read by BIOS/boot as LE. MBR is the ONE little-endian
# structure. We pack it LE by hand below rather than via CStruct's big-endian.)
FDISK_PART = CStruct("fdisk_part", [
    ("bootid", "B"),
    ("beghead", "B"),
    ("begsect", "B"),
    ("begcyl", "B"),
    ("systid", "B"),
    ("endhead", "B"),
    ("endsect", "B"),
    ("endcyl", "B"),
    ("relsect", "I"),   # NOTE: see pack_part_le below for byte order
    ("numsect", "I"),
])

DISK_BLK0 = CStruct("disk_blk0", [
    ("bootcode", "446s"),
    ("parts", "64s"),
    ("signature", "H"),
])

import struct


def _pack_part_le(bootid, systid, relsect, numsect):
    # MBR partition entries are little-endian. CHS fields set to a benign
    # 0xFE/0xFF "use LBA" pattern; Rhapsody's boot uses relsect/numsect (LBA).
    return struct.pack(
        "<BBBBBBBBII",
        bootid, 0xFE, 0xFF, 0xFF, systid, 0xFE, 0xFF, 0xFF,
        relsect & 0xFFFFFFFF, numsect & 0xFFFFFFFF,
    )


def build_mbr(boot0, part_lba, part_sectors):
    if len(boot0) > DISK_BOOTSZ:
        raise ValueError("boot0 code is %d bytes, max %d" % (len(boot0), DISK_BOOTSZ))
    sector = bytearray(512)
    sector[:len(boot0)] = boot0
    entry = _pack_part_le(FDISK_ACTIVE, FDISK_NEXTNAME, part_lba, part_sectors)
    sector[446:446 + 16] = entry
    struct.pack_into("<H", sector, 510, DISK_SIGNATURE)
    return bytes(sector)
```

> Note: the MBR/fdisk table is the single little-endian structure on disk
> (BIOS/DOS heritage). Everything else (NeXT label, UFS) is big-endian.
> `FDISK_PART` is defined for reading back in tests; `_pack_part_le` is the
> authoritative writer.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_fdisk.py -v`
Expected: FAIL — `test_build_mbr_layout` reads the entry with big-endian
`FDISK_PART` but it was written little-endian. Fix the test to read
little-endian, then re-run.

Replace the entry-read assertions in the test with:
```python
    import struct
    bootid, systid, relsect, numsect = struct.unpack(
        "<B3xB3xII", mbr[446:446 + 16])
    assert bootid == fdisk.FDISK_ACTIVE
    assert systid == fdisk.FDISK_NEXTNAME
    assert relsect == 63
    assert numsect == 1000
```
Run again: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/formats/fdisk.py vm/imgbuild/tests/test_fdisk.py
git commit -m "imgbuild: add MBR/fdisk structs and builder"
```

---

### Task 3: NeXT disk label (disktab + partition) + checksum

**Files:**
- Create: `vm/imgbuild/formats/label.py`
- Test: `vm/imgbuild/tests/test_label.py`

**Interfaces:**
- Consumes: `CStruct`.
- Produces:
  - `PARTITION` (`CStruct`, `partition_t`), `DISKTAB` (`CStruct`), `DISK_LABEL`
    (`CStruct`) — all big-endian, field order from the headers.
  - `DL_V3=0x646c5633`.
  - `build_label(dl_size, secsize, front, part_base, part_size, bootfile) ->
    bytes` — a full label sector-block (padded to `secsize`, i.e. 512), with
    `dl_version=DL_V3`, `dl_dt.d_secsize=secsize`, `dl_dt.d_front=front`,
    partition 0 `p_base=part_base`, `p_size=part_size`, `d_bootfile=bootfile`,
    and a correct ones-complement `dl_checksum` over the label.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_label.py`:
```python
from formats import label

def test_label_version_and_fields():
    raw = label.build_label(
        dl_size=1000, secsize=512, front=64,
        part_base=0, part_size=900, bootfile=b"mach_kernel")
    assert len(raw) == 512
    dl = label.DISK_LABEL.unpack(raw)
    assert dl["dl_version"] == label.DL_V3
    dt = label.DISKTAB.unpack(raw[label.DISKTAB_OFFSET:
                                  label.DISKTAB_OFFSET + label.DISKTAB.size])
    assert dt["d_secsize"] == 512
    assert dt["d_front"] == 64
    assert dt["d_bootfile"].rstrip(b"\x00") == b"mach_kernel"

def test_checksum_verifies():
    raw = label.build_label(1000, 512, 64, 0, 900, b"mach_kernel")
    assert label.verify_checksum(raw) is True
    bad = bytearray(raw)
    bad[0] ^= 0xFF
    assert label.verify_checksum(bytes(bad)) is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_label.py -v`
Expected: FAIL (`No module named 'formats.label'`).

- [ ] **Step 3: Implement `label.py`**

`vm/imgbuild/formats/label.py` — field order copied from `disktab.h` and
`disk_label.h`. Checksum algorithm mirrors the label's ones-complement scheme
(sum of 16-bit big-endian words, excluding the trailing checksum field).

```python
import struct
from formats.cstruct import CStruct

DL_V3 = 0x646C5633  # "dlV3"
NPART = 8
NBOOTS = 2

# partition_t (disktab.h)
PARTITION = CStruct("partition", [
    ("p_base", "i"),
    ("p_size", "i"),
    ("p_bsize", "h"),
    ("p_fsize", "h"),
    ("p_opt", "b"),
    ("p_cpg", "h"),
    ("p_density", "h"),
    ("p_minfree", "b"),
    ("p_newfs", "b"),
    ("p_mountpt", "16s"),   # MAXMPTLEN
    ("p_automnt", "b"),
    ("p_type", "8s"),       # MAXFSTLEN
])

# disktab (disktab.h)
DISKTAB = CStruct("disktab", [
    ("d_name", "24s"),
    ("d_type", "24s"),
    ("d_secsize", "i"),
    ("d_ntracks", "i"),
    ("d_nsectors", "i"),
    ("d_ncylinders", "i"),
    ("d_rpm", "i"),
    ("d_front", "h"),
    ("d_back", "h"),
    ("d_ngroups", "h"),
    ("d_ag_size", "h"),
    ("d_ag_alts", "h"),
    ("d_ag_off", "h"),
    ("d_boot0_blkno", "%di" % NBOOTS),
    ("d_bootfile", "24s"),
    ("d_hostname", "32s"),
    ("d_rootpartition", "b"),
    ("d_rwpartition", "b"),
    ("d_partitions", "%ds" % (PARTITION.size * NPART)),
])

# disk_label (disk_label.h)
DISK_LABEL = CStruct("disk_label", [
    ("dl_version", "i"),
    ("dl_label_blkno", "i"),
    ("dl_size", "i"),
    ("dl_label", "24s"),
    ("dl_flags", "I"),
    ("dl_tag", "I"),
    ("dl_dt", "%ds" % DISKTAB.size),
    ("dl_un", "8s"),
    ("dl_checksum", "H"),
])

DISKTAB_OFFSET = 4 + 4 + 4 + 24 + 4 + 4  # up to and including dl_tag
CHECKSUM_OFFSET = DISK_LABEL.size - 2


def _partitions_blob(part_base, part_size, bsize, fsize):
    parts = bytearray(PARTITION.size * NPART)
    p0 = PARTITION.pack({
        "p_base": part_base,
        "p_size": part_size,
        "p_bsize": bsize,
        "p_fsize": fsize,
        "p_opt": ord("t"),
        "p_minfree": 5,
        "p_newfs": 1,
        "p_mountpt": b"/",
        "p_type": b"4.3BSD",
    })
    parts[:PARTITION.size] = p0
    return bytes(parts)


def build_label(dl_size, secsize, front, part_base, part_size,
                bootfile, bsize=8192, fsize=1024):
    dt = DISKTAB.pack({
        "d_name": b"qemu",
        "d_type": b"fixed_rw_scsi",
        "d_secsize": secsize,
        "d_front": front,
        "d_bootfile": bootfile,
        "d_rootpartition": ord("a"),
        "d_partitions": _partitions_blob(part_base, part_size, bsize, fsize),
    })
    body = DISK_LABEL.pack({
        "dl_version": DL_V3,
        "dl_label_blkno": 15,   # DISKLABEL
        "dl_size": dl_size,
        "dl_label": b"RhapsodiOS",
        "dl_dt": dt,
    })
    block = bytearray(secsize)
    block[:len(body)] = body
    _set_checksum(block)
    return bytes(block)


def _sum16(block):
    total = 0
    # sum 16-bit big-endian words over the label body, excluding the checksum
    end = CHECKSUM_OFFSET
    for off in range(0, end - 1, 2):
        total += (block[off] << 8) | block[off + 1]
    if end % 2:  # trailing odd byte
        total += block[end - 1] << 8
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def _set_checksum(block):
    cksum = _sum16(block)
    struct.pack_into(">H", block, CHECKSUM_OFFSET, cksum)


def verify_checksum(block):
    want = struct.unpack_from(">H", block, CHECKSUM_OFFSET)[0]
    return want == _sum16(block)
```

> The checksum algorithm is a plausible ones-complement scheme; the real
> algorithm is in `src/kernel-7/bsd/dev/disk_label.h`/kernel label code.
> **Verification gate (Task 15/17):** the boot loader's `read_label()` in
> `src/boot-2/gen/libsaio/disk.c` only checks `dl_version == DL_V3` (it does
> not verify `dl_checksum`), so boot does not depend on this being exact — but
> the guest's `disk`/`fsck` tools do. Confirm against a real Rhapsody label
> (dump partition sector 15 of `rhapsody.vmdk`) during Task 15 and correct the
> algorithm/field offsets if they differ.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_label.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/formats/label.py vm/imgbuild/tests/test_label.py
git commit -m "imgbuild: add NeXT disk label structs and builder"
```

---

### Task 4: UFS on-disk structs (superblock, csum, cg, dinode, direct)

**Files:**
- Create: `vm/imgbuild/formats/ufs_fs.py`
- Create: `vm/imgbuild/formats/ufs_inode.py`
- Test: `vm/imgbuild/tests/test_ufs_structs.py`

**Interfaces:**
- Consumes: `CStruct`.
- Produces (all big-endian, field order from `fs.h`/`dinode.h`/`dir.h`):
  - `ufs_fs.CSUM`, `ufs_fs.FS` (superblock; note it is followed on disk by the
    positional tables and cg summary, so only the fixed head is packed here),
    `ufs_fs.CG`.
  - `ufs_fs` constants: `FS_MAGIC=0x011954`, `CG_MAGIC=0x090255`,
    `SBSIZE=8192`, `SBOFF=8192`, `DEV_BSIZE=512`, `MAXFRAG=8`,
    `MAXMNTLEN=512`, `MAXCSBUFS=31`.
  - `ufs_inode.DINODE` (128 bytes), `ufs_inode.DIRECT_HDR` (the 8-byte fixed
    head of `struct direct`: `d_ino`,`d_reclen`,`d_type`,`d_namlen`),
    `ufs_inode` constants `ROOTINO=2`, `NDADDR=12`, `NIADDR=3`, `MAXNAMLEN=255`.
  - File-type/mode constants: `IFDIR=0x4000`, `IFREG=0x8000`, `IFLNK=0xA000`,
    `IFCHR=0x2000`, `IFBLK=0x6000`, and dirent `DT_DIR=4`, `DT_REG=8`,
    `DT_LNK=10`, `DT_CHR=2`, `DT_BLK=6`.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_ufs_structs.py`:
```python
from formats import ufs_fs, ufs_inode

def test_dinode_is_128_bytes():
    assert ufs_inode.DINODE.size == 128

def test_dinode_field_offsets():
    # di_size at offset 8, di_db array at offset 40 (dinode.h comments)
    raw = ufs_inode.DINODE.pack({"di_size": 0x1122334455667788})
    assert raw[8:16] == b"\x11\x22\x33\x44\x55\x66\x77\x88"

def test_superblock_magic_roundtrip():
    raw = ufs_fs.FS.pack({"fs_magic": ufs_fs.FS_MAGIC, "fs_bsize": 8192})
    got = ufs_fs.FS.unpack(raw)
    assert got["fs_magic"] == ufs_fs.FS_MAGIC
    assert got["fs_bsize"] == 8192

def test_cg_magic_roundtrip():
    raw = ufs_fs.CG.pack({"cg_magic": ufs_fs.CG_MAGIC})
    assert ufs_fs.CG.unpack(raw)["cg_magic"] == ufs_fs.CG_MAGIC
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_structs.py -v`
Expected: FAIL (`No module named 'formats.ufs_fs'`).

- [ ] **Step 3: Implement the structs**

`vm/imgbuild/formats/ufs_inode.py`:
```python
from formats.cstruct import CStruct

ROOTINO = 2
NDADDR = 12
NIADDR = 3
MAXNAMLEN = 255

IFCHR = 0x2000
IFDIR = 0x4000
IFBLK = 0x6000
IFREG = 0x8000
IFLNK = 0xA000

DT_CHR = 2
DT_DIR = 4
DT_BLK = 6
DT_REG = 8
DT_LNK = 10

# struct dinode (dinode.h) — 128 bytes, big-endian
DINODE = CStruct("dinode", [
    ("di_mode", "H"),
    ("di_nlink", "h"),
    ("di_u", "4s"),                 # oldids[2]/inumber union
    ("di_size", "Q"),               # 64-bit
    ("di_atime", "i"),
    ("di_atimensec", "i"),
    ("di_mtime", "i"),
    ("di_mtimensec", "i"),
    ("di_ctime", "i"),
    ("di_ctimensec", "i"),
    ("di_db", "%di" % NDADDR),
    ("di_ib", "%di" % NIADDR),
    ("di_flags", "I"),
    ("di_blocks", "I"),
    ("di_gen", "i"),
    ("di_uid", "I"),
    ("di_gid", "I"),
    ("di_spare", "2i"),
])

# fixed head of struct direct (dir.h); d_name follows, variable length
DIRECT_HDR = CStruct("direct_hdr", [
    ("d_ino", "I"),
    ("d_reclen", "H"),
    ("d_type", "B"),
    ("d_namlen", "B"),
])
```

`vm/imgbuild/formats/ufs_fs.py`:
```python
from formats.cstruct import CStruct

FS_MAGIC = 0x011954
CG_MAGIC = 0x090255
SBSIZE = 8192
SBOFF = 8192
BBSIZE = 8192
DEV_BSIZE = 512
MINBSIZE = 4096
MAXFRAG = 8
MAXMNTLEN = 512
MAXCSBUFS = 31

CSUM = CStruct("csum", [
    ("cs_ndir", "i"),
    ("cs_nbfree", "i"),
    ("cs_nifree", "i"),
    ("cs_nffree", "i"),
])

# struct fs (fs.h) fixed head, in declaration order, big-endian.
# On disk the struct is followed by rotational tables + cg summary; we pack the
# fixed head into an SBSIZE-sized buffer in ufs.py and place tables after it.
FS = CStruct("fs", [
    ("fs_firstfield", "i"),
    ("fs_unused_1", "i"),
    ("fs_sblkno", "i"),
    ("fs_cblkno", "i"),
    ("fs_iblkno", "i"),
    ("fs_dblkno", "i"),
    ("fs_cgoffset", "i"),
    ("fs_cgmask", "i"),
    ("fs_time", "i"),
    ("fs_size", "i"),
    ("fs_dsize", "i"),
    ("fs_ncg", "i"),
    ("fs_bsize", "i"),
    ("fs_fsize", "i"),
    ("fs_frag", "i"),
    ("fs_minfree", "i"),
    ("fs_rotdelay", "i"),
    ("fs_rps", "i"),
    ("fs_bmask", "i"),
    ("fs_fmask", "i"),
    ("fs_bshift", "i"),
    ("fs_fshift", "i"),
    ("fs_maxcontig", "i"),
    ("fs_maxbpg", "i"),
    ("fs_fragshift", "i"),
    ("fs_fsbtodb", "i"),
    ("fs_sbsize", "i"),
    ("fs_csmask", "i"),
    ("fs_csshift", "i"),
    ("fs_nindir", "i"),
    ("fs_inopb", "i"),
    ("fs_nspf", "i"),
    ("fs_optim", "i"),
    ("fs_npsect", "i"),
    ("fs_interleave", "i"),
    ("fs_trackskew", "i"),
    ("fs_headswitch", "i"),
    ("fs_trkseek", "i"),
    ("fs_csaddr", "i"),
    ("fs_cssize", "i"),
    ("fs_cgsize", "i"),
    ("fs_ntrak", "i"),
    ("fs_nsect", "i"),
    ("fs_spc", "i"),
    ("fs_ncyl", "i"),
    ("fs_cpg", "i"),
    ("fs_ipg", "i"),
    ("fs_fpg", "i"),
    ("fs_cstotal", "4i"),           # struct csum inline
    ("fs_fmod", "b"),
    ("fs_clean", "b"),
    ("fs_ronly", "b"),
    ("fs_flags", "b"),
    ("fs_fsmnt", "%ds" % MAXMNTLEN),
    ("fs_cgrotor", "i"),
    ("fs_csp", "%di" % MAXCSBUFS),  # in-core pointers, zero on disk
    ("fs_maxcluster", "i"),         # in-core pointer, zero on disk
    ("fs_cpc", "i"),
    ("fs_opostbl", "128h"),         # [16][8] int16
    ("fs_sparecon", "50i"),
    ("fs_contigsumsize", "i"),
    ("fs_maxsymlinklen", "i"),
    ("fs_inodefmt", "i"),
    ("fs_maxfilesize", "Q"),
    ("fs_qbmask", "q"),
    ("fs_qfmask", "q"),
    ("fs_state", "i"),
    ("fs_postblformat", "i"),
    ("fs_nrpos", "i"),
    ("fs_postbloff", "i"),
    ("fs_rotbloff", "i"),
    ("fs_magic", "i"),
    ("fs_space", "b"),
])

# struct cg (fs.h) fixed head; maps follow in the block.
CG = CStruct("cg", [
    ("cg_firstfield", "i"),
    ("cg_magic", "i"),
    ("cg_time", "i"),
    ("cg_cgx", "i"),
    ("cg_ncyl", "h"),
    ("cg_niblk", "h"),
    ("cg_ndblk", "i"),
    ("cg_cs", "4i"),                # struct csum inline
    ("cg_rotor", "i"),
    ("cg_frotor", "i"),
    ("cg_irotor", "i"),
    ("cg_frsum", "%di" % MAXFRAG),
    ("cg_btotoff", "i"),
    ("cg_boff", "i"),
    ("cg_iusedoff", "i"),
    ("cg_freeoff", "i"),
    ("cg_nextfreeoff", "i"),
    ("cg_clustersumoff", "i"),
    ("cg_clusteroff", "i"),
    ("cg_nclusterblks", "i"),
    ("cg_sparecon", "13i"),
    ("cg_space", "b"),
])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_structs.py -v`
Expected: PASS (4 passed). If `test_dinode_is_128_bytes` fails, the field
sizes above sum to 128 by construction — recheck any accidental format typo.

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/formats/ufs_fs.py vm/imgbuild/formats/ufs_inode.py vm/imgbuild/tests/test_ufs_structs.py
git commit -m "imgbuild: add UFS on-disk struct definitions"
```

---

### Task 5: Package readers — deb + index

**Files:**
- Create: `vm/imgbuild/repo.py`
- Test: `vm/imgbuild/tests/test_repo_deb.py`

**Interfaces:**
- Produces:
  - `PackageMeta` dataclass: `name, version, arch, depends (list[str]),
    pre_depends (list[str]), provides (list[str]), conflicts (list[str]),
    replaces (list[str]), fmt (str "deb"|"apk"), path (str),
    control (dict[str,str])`.
  - `read_package(path) -> PackageMeta` (dispatches by extension).
  - `iter_payload(meta) -> Iterator[tarfile.TarInfo, reader]` via
    `open_payload(meta) -> tarfile.TarFile` (the extracted `data.tar.gz`).
  - `read_control_scripts(meta) -> dict[str, bytes]` (maintainer scripts from
    the deb control member: `preinst`, `postinst`, etc.).
  - `PackageIndex.from_dirs(dirs, tar_cache_dir) -> PackageIndex` with
    `.by_name(name) -> list[PackageMeta]` and `.all() -> list[PackageMeta]`.
    Auto-extracts any `*.tar` bundles in the dirs into `tar_cache_dir`.
  - Helpers: `_ar_members(path) -> dict[str, bytes]` (parse `!<arch>`).

- [ ] **Step 1: Add a real-deb fixture helper to the test**

`vm/imgbuild/tests/test_repo_deb.py`:
```python
import os
import pytest
from repo import read_package, PackageIndex, _ar_members

REPO = os.path.join(os.path.dirname(__file__), "..", "..", "debs")
OBJC4 = os.path.join(REPO, "objc4_174-1_universal-apple-rhapsody.deb")

pytestmark = pytest.mark.skipif(
    not os.path.exists(OBJC4), reason="sample deb not present")

def test_ar_members():
    m = _ar_members(OBJC4)
    assert "debian-binary" in m
    assert "control.tar.gz" in m
    assert "data.tar.gz" in m

def test_read_deb_control():
    meta = read_package(OBJC4)
    assert meta.name == "objc4"
    assert meta.version == "174-1"
    assert meta.arch == "universal-apple-rhapsody"
    assert meta.fmt == "deb"
    assert "objc4-hdrs" in meta.provides

def test_payload_lists_files():
    meta = read_package(OBJC4)
    tf = __import__("repo").open_payload(meta)
    names = tf.getnames()
    assert any("objc/objc.h" in n for n in names)

def test_index_by_name():
    idx = PackageIndex.from_dirs([REPO], tar_cache_dir="/tmp/imgbuild-cache")
    metas = idx.by_name("objc4")
    assert metas and metas[0].name == "objc4"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_repo_deb.py -v`
Expected: FAIL (`No module named 'repo'`).

- [ ] **Step 3: Implement `repo.py` (deb path)**

`vm/imgbuild/repo.py`:
```python
import io
import os
import glob
import gzip
import tarfile
from dataclasses import dataclass, field


@dataclass
class PackageMeta:
    name: str
    version: str
    arch: str
    depends: list = field(default_factory=list)
    pre_depends: list = field(default_factory=list)
    provides: list = field(default_factory=list)
    conflicts: list = field(default_factory=list)
    replaces: list = field(default_factory=list)
    fmt: str = "deb"
    path: str = ""
    control: dict = field(default_factory=dict)


def _ar_members(path):
    data = open(path, "rb").read()
    if data[:8] != b"!<arch>\n":
        raise ValueError("%s: not an ar archive" % path)
    pos, out = 8, {}
    while pos + 60 <= len(data):
        hdr = data[pos:pos + 60]
        name = hdr[0:16].decode().strip()
        size = int(hdr[48:58].decode().strip())
        start = pos + 60
        out[name] = data[start:start + size]
        pos = start + size + (size & 1)
    return out


def _parse_deplist(value):
    # "a, b | c, d (>= 1)" -> ["a", "b", "c", "d"] (versions/alternatives flattened)
    items = []
    for clause in value.split(","):
        for alt in clause.split("|"):
            name = alt.strip().split()[0] if alt.strip() else ""
            if name:
                items.append(name)
    return items


def _control_dict(text):
    fields, key = {}, None
    for line in text.splitlines():
        if line[:1] in (" ", "\t") and key:
            fields[key] += "\n" + line.strip()
        elif ":" in line:
            key, _, val = line.partition(":")
            key = key.strip()
            fields[key] = val.strip()
    return fields


def _meta_from_control(text, path, fmt):
    c = _control_dict(text)
    return PackageMeta(
        name=c.get("Package", ""),
        version=c.get("Version", ""),
        arch=c.get("Architecture", ""),
        depends=_parse_deplist(c.get("Depends", "")),
        pre_depends=_parse_deplist(c.get("Pre-Depends", "")),
        provides=_parse_deplist(c.get("Provides", "")),
        conflicts=_parse_deplist(c.get("Conflicts", "")),
        replaces=_parse_deplist(c.get("Replaces", "")),
        fmt=fmt, path=path, control=c,
    )


def _deb_control_tar(path):
    return tarfile.open(fileobj=io.BytesIO(_ar_members(path)["control.tar.gz"]))


def read_deb(path):
    ct = _deb_control_tar(path)
    for n in ct.getnames():
        if n.strip("./") == "control":
            text = ct.extractfile(n).read().decode()
            return _meta_from_control(text, path, "deb")
    raise ValueError("%s: no control file" % path)


def read_control_scripts(meta):
    if meta.fmt != "deb":
        return {}
    ct = _deb_control_tar(meta.path)
    out = {}
    for n in ct.getnames():
        base = n.strip("./")
        if base in ("preinst", "postinst", "prerm", "postrm", "conffiles"):
            out[base] = ct.extractfile(n).read()
    return out


def open_payload(meta):
    if meta.fmt == "deb":
        raw = _ar_members(meta.path)["data.tar.gz"]
        return tarfile.open(fileobj=io.BytesIO(raw))
    return open_apk_payload(meta)  # defined in Task 6


def read_package(path):
    if path.endswith(".deb"):
        return read_deb(path)
    if path.endswith(".apk"):
        return read_apk(path)  # defined in Task 6
    raise ValueError("unknown package type: %s" % path)


class PackageIndex:
    def __init__(self):
        self._by_name = {}
        self._all = []

    @classmethod
    def from_dirs(cls, dirs, tar_cache_dir):
        idx = cls()
        search = list(dirs)
        for d in dirs:
            for tar in glob.glob(os.path.join(d, "*.tar")):
                idx._extract_bundle(tar, tar_cache_dir)
            if tar_cache_dir not in search:
                search.append(tar_cache_dir)
        for d in search:
            for pat in ("*.deb", "*.apk"):
                for p in glob.glob(os.path.join(d, pat)):
                    idx._add(read_package(p))
        return idx

    def _extract_bundle(self, tar_path, cache_dir):
        os.makedirs(cache_dir, exist_ok=True)
        with tarfile.open(tar_path) as tf:
            for m in tf.getmembers():
                if m.name.endswith((".deb", ".apk")) and m.isreg():
                    dst = os.path.join(cache_dir, os.path.basename(m.name))
                    if not os.path.exists(dst):
                        with open(dst, "wb") as f:
                            f.write(tf.extractfile(m).read())

    def _add(self, meta):
        self._by_name.setdefault(meta.name, []).append(meta)
        for prov in meta.provides:
            self._by_name.setdefault(prov, []).append(meta)
        self._all.append(meta)

    def by_name(self, name):
        return self._by_name.get(name, [])

    def all(self):
        return list(self._all)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_repo_deb.py -v`
Expected: PASS (4 passed) — assuming `vm/debs/objc4_...deb` exists.

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/repo.py vm/imgbuild/tests/test_repo_deb.py
git commit -m "imgbuild: add deb package reader and repository index"
```

---

### Task 6: Package reader — apk (synthetic fixture)

**Files:**
- Modify: `vm/imgbuild/repo.py` (add `read_apk`, `open_apk_payload`)
- Create: `vm/imgbuild/tests/test_repo_apk.py`
- Create: `vm/imgbuild/tests/fixtures/make_apk.py` (fixture generator)

**Interfaces:**
- Consumes: `PackageMeta`, `_meta_from_control`-style parsing.
- Produces: `read_apk(path) -> PackageMeta` (metadata from `.PKGINFO`,
  `key = value` lines; `depend`/`provides` are repeated keys), and
  `open_apk_payload(meta) -> tarfile.TarFile` (an apk is a gzip stream of
  concatenated tar segments; the data segment holds the payload files).

- [ ] **Step 1: Write a synthetic apk fixture generator + failing test**

`vm/imgbuild/tests/fixtures/make_apk.py`:
```python
import io
import gzip
import tarfile


def make_apk(path, name="demo", version="1.0-r0", arch="i386",
             depends=(), files=(("usr/bin/demo", b"hi"),)):
    """Write a minimal 2-segment apk (control seg with .PKGINFO, data seg)."""
    def seg(members):
        buf = io.BytesIO()
        tf = tarfile.open(fileobj=buf, mode="w")
        for tname, data in members:
            ti = tarfile.TarInfo(tname)
            ti.size = len(data)
            tf.addfile(ti, io.BytesIO(data))
        tf.close()
        return buf.getvalue()

    pkginfo = "pkgname = %s\npkgver = %s\narch = %s\n" % (name, version, arch)
    for d in depends:
        pkginfo += "depend = %s\n" % d
    control = seg([(".PKGINFO", pkginfo.encode())])
    data = seg(list(files))
    with open(path, "wb") as f:
        f.write(gzip.compress(control) + gzip.compress(data))
```

`vm/imgbuild/tests/test_repo_apk.py`:
```python
import os
from fixtures.make_apk import make_apk
from repo import read_package, open_payload

def test_read_apk(tmp_path):
    p = str(tmp_path / "demo-1.0-r0.apk")
    make_apk(p, name="demo", version="1.0-r0", arch="i386",
             depends=["libc"], files=[("usr/bin/demo", b"hi")])
    meta = read_package(p)
    assert meta.name == "demo"
    assert meta.version == "1.0-r0"
    assert meta.arch == "i386"
    assert meta.fmt == "apk"
    assert "libc" in meta.depends

def test_apk_payload(tmp_path):
    p = str(tmp_path / "demo-1.0-r0.apk")
    make_apk(p, files=[("usr/bin/demo", b"hi")])
    tf = open_payload(read_package(p))
    assert "usr/bin/demo" in tf.getnames()
```

Add to `conftest.py` the fixtures import path (already covered — `tests/` is on
`sys.path` via the IMGBUILD_DIR insert only if fixtures is a package). Create
`vm/imgbuild/tests/fixtures/__init__.py` (empty) and ensure the tests dir is
importable by adding `os.path.dirname(__file__)` to `sys.path` in conftest:
```python
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # tests dir
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_repo_apk.py -v`
Expected: FAIL (`read_apk` not defined / import error).

- [ ] **Step 3: Implement apk support in `repo.py`**

Append to `vm/imgbuild/repo.py`:
```python
def _apk_segments(path):
    """Yield decompressed tar bytes for each concatenated gzip member."""
    data = open(path, "rb").read()
    segs, pos = [], 0
    while pos < len(data):
        if data[pos:pos + 2] != b"\x1f\x8b":
            break
        d = gzip.GzipFile(fileobj=io.BytesIO(data[pos:]))
        segs.append(d.read())
        # advance past this member: re-compress boundary is opaque, so decode
        # member-by-member using the underlying stream position.
        pos += d.fileobj.tell() if hasattr(d, "fileobj") else len(data)
        break_all = False
        if pos <= 0 or pos >= len(data):
            break_all = True
        if break_all:
            break
    return segs
```

> The concatenated-gzip boundary is not cleanly exposed by `gzip.GzipFile`.
> Use `zlib` to consume one member at a time and learn its consumed length:

Replace `_apk_segments` with:
```python
import zlib

def _apk_segments(path):
    data = open(path, "rb").read()
    segs, pos = [], 0
    while pos < len(data) and data[pos:pos + 2] == b"\x1f\x8b":
        dobj = zlib.decompressobj(16 + zlib.MAX_WBITS)
        out = dobj.decompress(data[pos:])
        out += dobj.flush()
        segs.append(out)
        consumed = len(data) - pos - len(dobj.unused_data)
        pos += consumed
    return segs


def read_apk(path):
    segs = _apk_segments(path)
    # control segment (first) holds .PKGINFO
    ct = tarfile.open(fileobj=io.BytesIO(segs[0]))
    info_member = None
    for n in ct.getnames():
        if n.strip("./") == ".PKGINFO":
            info_member = n
            break
    if info_member is None:
        raise ValueError("%s: no .PKGINFO" % path)
    text = ct.extractfile(info_member).read().decode()
    name = ver = arch = ""
    depends, provides = [], []
    for line in text.splitlines():
        if "=" not in line:
            continue
        k, _, v = line.partition("=")
        k, v = k.strip(), v.strip()
        if k == "pkgname":
            name = v
        elif k == "pkgver":
            ver = v
        elif k == "arch":
            arch = v
        elif k == "depend":
            depends.append(v.split()[0])
        elif k == "provides":
            provides.append(v.split()[0])
    return PackageMeta(name=name, version=ver, arch=arch, depends=depends,
                       provides=provides, fmt="apk", path=path,
                       control={"PKGINFO": text})


def open_apk_payload(meta):
    segs = _apk_segments(meta.path)
    # last segment is the data payload
    return tarfile.open(fileobj=io.BytesIO(segs[-1]))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_repo_apk.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/repo.py vm/imgbuild/tests/test_repo_apk.py vm/imgbuild/tests/fixtures/
git commit -m "imgbuild: add apk package reader with synthetic fixture"
```

---

### Task 7: Dependency solver + presets

**Files:**
- Create: `vm/imgbuild/solve.py`
- Test: `vm/imgbuild/tests/test_solve.py`

**Interfaces:**
- Consumes: `PackageIndex`, `PackageMeta`.
- Produces:
  - `MINIMAL_BASE` (list[str]) — root package names.
  - `select(index, roots, target_arch) -> list[PackageMeta]` — resolves the
    dependency closure, prefers an arch-specific variant over `universal` when
    both satisfy a name, and returns packages in install order
    (`pre_depends` before dependents; stable topological order). Raises
    `DependencyError` on an unsatisfiable name and `ConflictError` when two
    selected packages declare a `Conflicts` against each other.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_solve.py`:
```python
import pytest
from repo import PackageMeta, PackageIndex
from solve import select, DependencyError, ConflictError

def _idx(*metas):
    idx = PackageIndex()
    for m in metas:
        idx._add(m)
    return idx

def test_closure_and_order():
    a = PackageMeta("a", "1", "universal", depends=["b"])
    b = PackageMeta("b", "1", "universal", pre_depends=["c"])
    c = PackageMeta("c", "1", "universal")
    idx = _idx(a, b, c)
    order = [m.name for m in select(idx, ["a"], "i386")]
    assert order.index("c") < order.index("b") < order.index("a")

def test_prefers_arch_specific():
    uni = PackageMeta("libc", "1", "universal-apple-rhapsody")
    i386 = PackageMeta("libc", "1", "i386-apple-rhapsody")
    idx = _idx(uni, i386)
    chosen = select(idx, ["libc"], "i386")
    assert chosen[0].arch == "i386-apple-rhapsody"

def test_unsatisfiable_raises():
    a = PackageMeta("a", "1", "universal", depends=["missing"])
    with pytest.raises(DependencyError):
        select(_idx(a), ["a"], "i386")

def test_conflict_raises():
    a = PackageMeta("a", "1", "universal", conflicts=["b"])
    b = PackageMeta("b", "1", "universal")
    with pytest.raises(ConflictError):
        select(_idx(a, b), ["a", "b"], "i386")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_solve.py -v`
Expected: FAIL (`No module named 'solve'`).

- [ ] **Step 3: Implement `solve.py`**

`vm/imgbuild/solve.py`:
```python
MINIMAL_BASE = [
    "kernel", "boot", "files", "libsystem", "libc", "objc4",
    "system-cmds", "shell-cmds", "diskdev-cmds", "dpkg",
]


class DependencyError(Exception):
    pass


class ConflictError(Exception):
    pass


def _pick_variant(metas, target_arch):
    """Prefer <target_arch>-apple-rhapsody, else universal, else first."""
    def rank(m):
        if m.arch.startswith(target_arch + "-"):
            return 0
        if m.arch.startswith("universal"):
            return 1
        return 2
    return sorted(metas, key=rank)[0]


def select(index, roots, target_arch):
    chosen = {}          # name -> PackageMeta
    visiting = set()
    order = []

    def visit(name):
        if name in chosen:
            return
        metas = index.by_name(name)
        if not metas:
            raise DependencyError("no package provides %r" % name)
        meta = _pick_variant(metas, target_arch)
        if meta.name in visiting:
            return       # cycle guard
        visiting.add(meta.name)
        for dep in meta.pre_depends:
            visit(dep)
        for dep in meta.depends:
            visit(dep)
        visiting.discard(meta.name)
        if meta.name not in chosen:
            chosen[meta.name] = meta
            order.append(meta)

    for r in roots:
        visit(r)

    names = {m.name for m in order}
    for m in order:
        for c in m.conflicts:
            if c in names:
                raise ConflictError("%s conflicts with %s" % (m.name, c))
    return order
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_solve.py -v`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/solve.py vm/imgbuild/tests/test_solve.py
git commit -m "imgbuild: add dependency solver and minimal-base preset"
```

---

### Task 8: Staging — extract payloads to an in-memory tree

**Files:**
- Create: `vm/imgbuild/stage.py`
- Test: `vm/imgbuild/tests/test_stage.py`

**Interfaces:**
- Consumes: `open_payload`, `PackageMeta`.
- Produces:
  - `Node` dataclass: `kind ("dir"|"file"|"symlink"|"chr"|"blk"), mode,
    uid, gid, mtime, data (bytes|None), linkname (str|None),
    rdev ((major,minor)|None), children (dict[str, Node] for dirs)`.
  - `StagingTree` with `root: Node`, `add_from_tar(tf)`, `mkpath(path, node)`,
    `get(path) -> Node|None`, `walk() -> Iterator[(path, Node)]`.
  - `build_staging(metas) -> (StagingTree, FileManifest)` — extracts each
    package payload in order (later overwrites earlier); `FileManifest` maps
    `path -> (package_name, md5hex)` for regular files.
  - `ensure_mach_kernel(tree)` — if `/mach_kernel` is absent but
    `/private/tftpboot/mach_kernel` exists, copy it to `/mach_kernel`.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_stage.py`:
```python
import io
import tarfile
from stage import StagingTree, build_staging, ensure_mach_kernel

def _tar(members):
    buf = io.BytesIO()
    tf = tarfile.open(fileobj=buf, mode="w")
    for m, data in members:
        if isinstance(m, tarfile.TarInfo):
            ti = m
        else:
            ti = tarfile.TarInfo(m)
            ti.size = len(data or b"")
        tf.addfile(ti, io.BytesIO(data) if data is not None else None)
    tf.close()
    buf.seek(0)
    return tarfile.open(fileobj=buf)

def test_add_file_and_dirs():
    tree = StagingTree()
    tree.add_from_tar(_tar([("usr/bin/sh", b"ELF")]))
    n = tree.get("/usr/bin/sh")
    assert n.kind == "file" and n.data == b"ELF"
    assert tree.get("/usr/bin").kind == "dir"

def test_symlink_and_overwrite():
    tree = StagingTree()
    ln = tarfile.TarInfo("usr/lib/libc.so"); ln.type = tarfile.SYMTYPE
    ln.linkname = "libc.1.so"
    tree.add_from_tar(_tar([(ln, None)]))
    assert tree.get("/usr/lib/libc.so").kind == "symlink"

def test_ensure_mach_kernel_copy():
    tree = StagingTree()
    tree.add_from_tar(_tar([("private/tftpboot/mach_kernel", b"KERN")]))
    ensure_mach_kernel(tree)
    assert tree.get("/mach_kernel").data == b"KERN"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_stage.py -v`
Expected: FAIL (`No module named 'stage'`).

- [ ] **Step 3: Implement `stage.py`**

`vm/imgbuild/stage.py`:
```python
import hashlib
import tarfile
from dataclasses import dataclass, field

from repo import open_payload


@dataclass
class Node:
    kind: str
    mode: int = 0o755
    uid: int = 0
    gid: int = 0
    mtime: int = 0
    data: bytes = None
    linkname: str = None
    rdev: tuple = None
    children: dict = field(default_factory=dict)


def _split(path):
    return [p for p in path.strip("/").split("/") if p]


class StagingTree:
    def __init__(self):
        self.root = Node(kind="dir", mode=0o755)

    def mkpath(self, path, node):
        parts = _split(path)
        cur = self.root
        for p in parts[:-1]:
            nxt = cur.children.get(p)
            if nxt is None or nxt.kind != "dir":
                nxt = Node(kind="dir", mode=0o755)
                cur.children[p] = nxt
            cur = nxt
        if parts:
            cur.children[parts[-1]] = node
        return node

    def get(self, path):
        parts = _split(path)
        cur = self.root
        for p in parts:
            if cur.kind != "dir":
                return None
            cur = cur.children.get(p)
            if cur is None:
                return None
        return cur

    def add_from_tar(self, tf):
        for ti in tf.getmembers():
            name = ti.name.strip("./")
            if not name or name == ".":
                continue
            if ti.isdir():
                existing = self.get("/" + name)
                if existing and existing.kind == "dir":
                    existing.mode = ti.mode
                else:
                    self.mkpath("/" + name, Node("dir", ti.mode, ti.uid,
                                                 ti.gid, int(ti.mtime)))
            elif ti.issym():
                self.mkpath("/" + name, Node("symlink", ti.mode, ti.uid,
                            ti.gid, int(ti.mtime), linkname=ti.linkname))
            elif ti.islnk():
                target = self.get("/" + ti.linkname.strip("./"))
                if target is not None:
                    self.mkpath("/" + name, Node(target.kind, target.mode,
                                target.uid, target.gid, target.mtime,
                                data=target.data, linkname=target.linkname))
            elif ti.ischr() or ti.isblk():
                kind = "chr" if ti.ischr() else "blk"
                self.mkpath("/" + name, Node(kind, ti.mode, ti.uid, ti.gid,
                            int(ti.mtime), rdev=(ti.devmajor, ti.devminor)))
            elif ti.isreg():
                data = tf.extractfile(ti).read()
                self.mkpath("/" + name, Node("file", ti.mode, ti.uid, ti.gid,
                            int(ti.mtime), data=data))

    def walk(self):
        def rec(prefix, node):
            for name, child in sorted(node.children.items()):
                path = prefix + "/" + name
                yield path, child
                if child.kind == "dir":
                    yield from rec(path, child)
        yield from rec("", self.root)


class FileManifest(dict):
    pass


def build_staging(metas):
    tree = StagingTree()
    manifest = FileManifest()
    for meta in metas:
        tf = open_payload(meta)
        tree.add_from_tar(tf)
        for ti in tf.getmembers():
            if ti.isreg():
                path = "/" + ti.name.strip("./")
                node = tree.get(path)
                if node and node.data is not None:
                    manifest[path] = (meta.name,
                                      hashlib.md5(node.data).hexdigest())
    return tree, manifest


def ensure_mach_kernel(tree):
    if tree.get("/mach_kernel") is None:
        src = tree.get("/private/tftpboot/mach_kernel")
        if src is not None and src.kind == "file":
            tree.mkpath("/mach_kernel", Node("file", 0o644, 0, 0, src.mtime,
                        data=src.data))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_stage.py -v`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/stage.py vm/imgbuild/tests/test_stage.py
git commit -m "imgbuild: add payload staging tree and manifest"
```

---

### Task 9: dpkg database synthesis

**Files:**
- Create: `vm/imgbuild/dpkgdb.py`
- Test: `vm/imgbuild/tests/test_dpkgdb.py`

**Interfaces:**
- Consumes: `StagingTree`, `Node`, `PackageMeta`, `FileManifest`,
  `read_control_scripts`.
- Produces: `write_dpkg_db(tree, metas, manifest)` — adds to the tree:
  - `/var/lib/dpkg/status` — one stanza per package, `Status: install ok
    installed`, echoing control fields.
  - `/var/lib/dpkg/info/<pkg>.list` — newline-joined installed paths.
  - `/var/lib/dpkg/info/<pkg>.md5sums` — `md5  path` lines (no leading slash).
  - `/var/lib/dpkg/info/<pkg>.<script>` — maintainer scripts (deb only).
  - `/var/lib/dpkg/available` — same stanzas as status without the Status line.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_dpkgdb.py`:
```python
from stage import StagingTree, Node
from repo import PackageMeta
from dpkgdb import write_dpkg_db

def test_status_and_list():
    tree = StagingTree()
    tree.mkpath("/usr/bin/demo", Node("file", 0o755, data=b"x"))
    meta = PackageMeta("demo", "1-1", "universal",
                       control={"Package": "demo", "Version": "1-1",
                                "Architecture": "universal"})
    manifest = {"/usr/bin/demo": ("demo", "9dd4e461268c8034f5c8564e155c67a6")}
    write_dpkg_db(tree, [meta], manifest)
    status = tree.get("/var/lib/dpkg/status").data.decode()
    assert "Package: demo" in status
    assert "Status: install ok installed" in status
    lst = tree.get("/var/lib/dpkg/info/demo.list").data.decode()
    assert "/usr/bin/demo" in lst
    md5 = tree.get("/var/lib/dpkg/info/demo.md5sums").data.decode()
    assert "usr/bin/demo" in md5
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_dpkgdb.py -v`
Expected: FAIL (`No module named 'dpkgdb'`).

- [ ] **Step 3: Implement `dpkgdb.py`**

`vm/imgbuild/dpkgdb.py`:
```python
from stage import Node
from repo import read_control_scripts

_STATUS_FIELDS = ["Package", "Version", "Architecture", "Maintainer",
                  "Depends", "Pre-Depends", "Provides", "Conflicts",
                  "Replaces", "Description"]


def _stanza(meta, with_status):
    lines = []
    lines.append("Package: %s" % meta.name)
    if with_status:
        lines.append("Status: install ok installed")
    for f in _STATUS_FIELDS[1:]:
        if f in meta.control:
            lines.append("%s: %s" % (f, meta.control[f]))
    return "\n".join(lines) + "\n"


def _put(tree, path, data, mode=0o644):
    tree.mkpath(path, Node("file", mode, 0, 0, 0, data=data))


def write_dpkg_db(tree, metas, manifest):
    status = "\n".join(_stanza(m, True) for m in metas)
    _put(tree, "/var/lib/dpkg/status", status.encode())
    available = "\n".join(_stanza(m, False) for m in metas)
    _put(tree, "/var/lib/dpkg/available", available.encode())

    # per-package file lists and md5sums from the manifest
    files_by_pkg = {}
    for path, (pkg, md5) in manifest.items():
        files_by_pkg.setdefault(pkg, []).append((path, md5))
    for m in metas:
        entries = sorted(files_by_pkg.get(m.name, []))
        listing = "".join(p + "\n" for p, _ in entries)
        _put(tree, "/var/lib/dpkg/info/%s.list" % m.name, listing.encode())
        md5s = "".join("%s  %s\n" % (md5, p.lstrip("/")) for p, md5 in entries)
        _put(tree, "/var/lib/dpkg/info/%s.md5sums" % m.name, md5s.encode())
        for sname, sdata in read_control_scripts(m).items():
            if sname == "conffiles":
                _put(tree, "/var/lib/dpkg/info/%s.conffiles" % m.name, sdata)
            else:
                _put(tree, "/var/lib/dpkg/info/%s.%s" % (m.name, sname),
                     sdata, mode=0o755)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_dpkgdb.py -v`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/dpkgdb.py vm/imgbuild/tests/test_dpkgdb.py
git commit -m "imgbuild: synthesize dpkg status/info database"
```

---

### Task 10: Static /dev nodes + deferred first-boot script

**Files:**
- Create: `vm/imgbuild/devnodes.py`
- Test: `vm/imgbuild/tests/test_devnodes.py`

**Interfaces:**
- Consumes: `StagingTree`, `Node`.
- Produces:
  - `DEV_NODES` — list of `(name, kind, mode, major, minor)` covering the
    minimal early-boot set. **Major/minor numbers are placeholders and MUST be
    reconciled against the guest's `/dev` and the `kernel` deb's
    `private/dev/MAKEDEV` before relying on the image (Task 17).**
  - `write_dev_nodes(tree)` — creates `/dev/<name>` device inodes.
  - `write_firstboot(tree, metas)` — writes `/etc/rc.firstboot` that runs each
    package's queued `postinst` on first boot and a hook line to invoke it from
    `rc.boot`. (The hook wiring into `rc.boot` is verified in Task 17.)

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_devnodes.py`:
```python
from stage import StagingTree
from devnodes import write_dev_nodes, DEV_NODES

def test_dev_nodes_created():
    tree = StagingTree()
    write_dev_nodes(tree)
    console = tree.get("/dev/console")
    assert console is not None and console.kind == "chr"
    null = tree.get("/dev/null")
    assert null.kind == "chr"

def test_dev_table_has_essentials():
    names = {n[0] for n in DEV_NODES}
    for essential in ("console", "null", "zero", "tty", "mem", "kmem"):
        assert essential in names
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_devnodes.py -v`
Expected: FAIL (`No module named 'devnodes'`).

- [ ] **Step 3: Implement `devnodes.py`**

`vm/imgbuild/devnodes.py`:
```python
from stage import Node

# (name, kind, mode, major, minor)
# PLACEHOLDER major/minor — reconcile with guest /dev and MAKEDEV in Task 17.
DEV_NODES = [
    ("console", "chr", 0o600, 0, 0),
    ("tty",     "chr", 0o666, 2, 0),
    ("null",    "chr", 0o666, 3, 2),
    ("zero",    "chr", 0o666, 3, 3),
    ("mem",     "chr", 0o640, 3, 0),
    ("kmem",    "chr", 0o640, 3, 1),
    ("sd0a",    "blk", 0o640, 0, 0),
    ("rsd0a",   "chr", 0o640, 0, 0),
    ("fd",      "dir", 0o555, 0, 0),
]


def write_dev_nodes(tree):
    tree.mkpath("/dev", Node("dir", 0o755))
    for name, kind, mode, major, minor in DEV_NODES:
        if kind == "dir":
            tree.mkpath("/dev/" + name, Node("dir", mode))
        else:
            tree.mkpath("/dev/" + name,
                        Node(kind, mode, 0, 0, 0, rdev=(major, minor)))


def write_firstboot(tree, metas):
    lines = ["#!/bin/sh", "# generated by imgbuild: run queued postinsts once"]
    for m in metas:
        script = "/var/lib/dpkg/info/%s.postinst" % m.name
        lines.append('[ -x %s ] && %s configure' % (script, script))
    lines.append("rm -f /etc/rc.firstboot")
    data = ("\n".join(lines) + "\n").encode()
    tree.mkpath("/etc/rc.firstboot", Node("file", 0o755, 0, 0, 0, data=data))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_devnodes.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/devnodes.py vm/imgbuild/tests/test_devnodes.py
git commit -m "imgbuild: add static /dev nodes and first-boot hook"
```

---

### Task 11: UFS geometry planner (single cylinder group)

**Files:**
- Create: `vm/imgbuild/ufs.py`
- Test: `vm/imgbuild/tests/test_ufs_geometry.py`

**Interfaces:**
- Consumes: `ufs_fs` constants.
- Produces:
  - `Geometry` dataclass with the computed layout for a single-cg FFS:
    `bsize, fsize, frag, fragshift, fsbtodb, nspf, inopb, nindir, sectors,
    size_frags (fs_size), ncg (==1), fpg, ipg, cgoffset, cgmask, sblkno,
    cblkno, iblkno, dblkno, cgsize, csaddr, cssize, ncyl, cpg, spc, nsect,
    ntrak`.
  - `plan_geometry(total_sectors, nfiles_hint, bsize=8192, fsize=1024,
    frag=8) -> Geometry`. Raises `ValueError` if the single cg cannot hold
    `total_sectors` (i.e. fpg would exceed the one-block bitmap limit,
    `fpg > bsize*8`) — that is the multi-cg boundary we deliberately reject.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_ufs_geometry.py`:
```python
import pytest
from ufs import plan_geometry

def test_single_cg_small_fs():
    g = plan_geometry(total_sectors=20000, nfiles_hint=500)
    assert g.ncg == 1
    assert g.bsize == 8192 and g.fsize == 1024 and g.frag == 8
    # superblock lives at SBOFF=8192 => frag 8 (8192/1024)
    assert g.sblkno == 8192 // 1024
    # data begins after cg header + inode blocks
    assert g.dblkno > g.iblkno > g.cblkno >= g.sblkno

def test_too_big_for_one_cg_raises():
    # 4 GB in 512-byte sectors clearly exceeds one cg at 8k/1k
    with pytest.raises(ValueError):
        plan_geometry(total_sectors=8 * 1024 * 1024, nfiles_hint=100)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_geometry.py -v`
Expected: FAIL (`No module named 'ufs'`).

- [ ] **Step 3: Implement the planner in `ufs.py`**

`vm/imgbuild/ufs.py` (planner section):
```python
from dataclasses import dataclass
from formats import ufs_fs, ufs_inode

DEV_BSIZE = ufs_fs.DEV_BSIZE  # 512


def _ilog2(n):
    b = 0
    while (1 << b) < n:
        b += 1
    return b


@dataclass
class Geometry:
    bsize: int
    fsize: int
    frag: int
    fragshift: int
    bshift: int
    fshift: int
    fsbtodb: int
    nspf: int
    inopb: int
    nindir: int
    sectors: int
    size_frags: int
    ncg: int
    fpg: int
    ipg: int
    cgoffset: int
    cgmask: int
    sblkno: int
    cblkno: int
    iblkno: int
    dblkno: int
    cgsize: int
    csaddr: int
    cssize: int
    ncyl: int
    cpg: int
    spc: int
    nsect: int
    ntrak: int


def plan_geometry(total_sectors, nfiles_hint, bsize=8192, fsize=1024, frag=8):
    bshift = _ilog2(bsize)
    fshift = _ilog2(fsize)
    fragshift = _ilog2(frag)
    nspf = fsize // DEV_BSIZE                 # sectors per frag
    fsbtodb = _ilog2(nspf)                    # frag <-> disk-block shift
    inopb = bsize // ufs_inode.DINODE.size    # inodes per block (64)
    nindir = bsize // 4                        # ufs_daddr_t per block (2048)

    size_frags = total_sectors // nspf         # fs_size, in frags
    # single cg
    if size_frags > bsize * 8:
        raise ValueError(
            "fs needs %d frags but one cylinder group holds at most %d; "
            "multi-cg is out of scope" % (size_frags, bsize * 8))

    # fixed early blocks (in frags): boot+super at frag 0..sblkno+..,
    # cg block, inode blocks, then data.
    sblkno = bsize // fsize                     # 8 (SBOFF / fsize)
    cblkno = sblkno + (bsize // fsize)          # cg block after superblock
    # inode count: round up to whole inode blocks, generous vs nfiles_hint
    ninodes = max(nfiles_hint * 2, 1024)
    iblocks = (ninodes + inopb - 1) // inopb
    ipg = iblocks * inopb
    iblkno = cblkno + (bsize // fsize)          # inode area after cg block
    dblkno = iblkno + iblocks * frag            # data after inode blocks

    fpg = (size_frags // frag) * frag           # frags per group (block-aligned)
    # csum summary area (one cg -> one csum) placed at dblkno
    cssize = ufs_fs.CSUM.size
    csaddr = dblkno
    # advance dblkno past the csum block(s), rounded to a full block
    csblocks = (cssize + bsize - 1) // bsize
    dblkno += csblocks * frag

    spc = 16 * frag                             # arbitrary sane geometry
    nsect = spc
    ntrak = 1
    cpg = (fpg + spc - 1) // spc
    ncyl = cpg
    cgsize = bsize

    return Geometry(
        bsize=bsize, fsize=fsize, frag=frag, fragshift=fragshift,
        bshift=bshift, fshift=fshift, fsbtodb=fsbtodb, nspf=nspf,
        inopb=inopb, nindir=nindir, sectors=total_sectors,
        size_frags=size_frags, ncg=1, fpg=fpg, ipg=ipg, cgoffset=0,
        cgmask=-1, sblkno=sblkno, cblkno=cblkno, iblkno=iblkno,
        dblkno=dblkno, cgsize=cgsize, csaddr=csaddr, cssize=cssize,
        ncyl=ncyl, cpg=cpg, spc=spc, nsect=nsect, ntrak=ntrak)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_geometry.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/ufs.py vm/imgbuild/tests/test_ufs_geometry.py
git commit -m "imgbuild: add single-cg UFS geometry planner"
```

---

### Task 12: UFS allocator + inode/directory model

**Files:**
- Modify: `vm/imgbuild/ufs.py` (add allocator + tree flatten)
- Test: `vm/imgbuild/tests/test_ufs_alloc.py`

**Interfaces:**
- Consumes: `Geometry`, `StagingTree`, `Node`, `ufs_inode`.
- Produces:
  - `InodeRec` dataclass: `ino, node, blocks (list[int] frag addrs in
    allocation order), size, is_dir, dir_entries (list[(name, ino, dtype)])`.
  - `Allocator` with `alloc_frags(nfrags) -> start_frag`,
    `used_frags -> int`.
  - `flatten_tree(tree, geom) -> (list[InodeRec], root_ino)` — assigns inode
    numbers (root = `ROOTINO=2`, then depth-first), builds directory entry
    lists (including `.`/`..`), and allocates data frags for file contents,
    directory blocks, and long symlinks (short symlinks < `fs_maxsymlinklen`
    stored inline are represented with `blocks=[]` and data in `InodeRec`).
    Raises `ValueError` if allocation exceeds `geom.size_frags`.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_ufs_alloc.py`:
```python
from stage import StagingTree, Node
from ufs import plan_geometry, flatten_tree
from formats.ufs_inode import ROOTINO

def _tree():
    t = StagingTree()
    t.mkpath("/etc/motd", Node("file", 0o644, data=b"welcome\n"))
    t.mkpath("/bin/sh", Node("file", 0o755, data=b"X" * 9000))  # >1 block
    return t

def test_root_is_inode_2():
    t = _tree()
    g = plan_geometry(20000, 100)
    recs, root_ino = flatten_tree(t, g)
    assert root_ino == ROOTINO
    by_ino = {r.ino: r for r in recs}
    assert by_ino[ROOTINO].is_dir

def test_multiblock_file_gets_two_blocks():
    t = _tree()
    g = plan_geometry(20000, 100)
    recs, _ = flatten_tree(t, g)
    sh = [r for r in recs if r.node.data == b"X" * 9000][0]
    # 9000 bytes at bsize 8192 -> one full block + a fragmented tail
    assert sh.size == 9000
    assert len(sh.blocks) >= 1

def test_dir_has_dot_entries():
    t = _tree()
    g = plan_geometry(20000, 100)
    recs, root_ino = flatten_tree(t, g)
    root = [r for r in recs if r.ino == root_ino][0]
    names = [e[0] for e in root.dir_entries]
    assert "." in names and ".." in names and "etc" in names
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_alloc.py -v`
Expected: FAIL (`cannot import name 'flatten_tree'`).

- [ ] **Step 3: Implement allocator + flatten in `ufs.py`**

Append to `vm/imgbuild/ufs.py`:
```python
from dataclasses import dataclass, field as _field
from formats.ufs_inode import (ROOTINO, DT_DIR, DT_REG, DT_LNK, DT_CHR, DT_BLK,
                               DIRECT_HDR)

MAXSYMLINKLEN = 60  # fs_maxsymlinklen: symlinks shorter than this are inline


@dataclass
class InodeRec:
    ino: int
    node: object
    size: int = 0
    is_dir: bool = False
    blocks: list = _field(default_factory=list)          # frag start addrs
    dir_entries: list = _field(default_factory=list)      # (name, ino, dtype)
    inline_link: bytes = None


class Allocator:
    def __init__(self, geom):
        self.geom = geom
        self.next_frag = geom.dblkno
        self.limit = geom.size_frags

    def alloc_frags(self, nfrags):
        start = self.next_frag
        self.next_frag += nfrags
        if self.next_frag > self.limit:
            raise ValueError("out of space: need frag %d, fs has %d"
                             % (self.next_frag, self.limit))
        return start

    @property
    def used_frags(self):
        return self.next_frag


def _dtype(node):
    return {"dir": DT_DIR, "file": DT_REG, "symlink": DT_LNK,
            "chr": DT_CHR, "blk": DT_BLK}[node.kind]


def _dir_block_size(entries, bsize):
    """Bytes needed for directory entries (each 8-byte head + name, 4-aligned),
    rounded up to whole bsize blocks (FFS dir blocks are block-granular)."""
    total = 0
    for name, _ino, _t in entries:
        reclen = (8 + len(name) + 1 + 3) & ~3
        total += reclen
    return ((total + bsize - 1) // bsize) * bsize


def _frags_for(nbytes, geom):
    if nbytes == 0:
        return 0
    full_blocks = nbytes // geom.bsize
    tail = nbytes - full_blocks * geom.bsize
    frags = full_blocks * geom.frag
    if tail:
        frags += (tail + geom.fsize - 1) // geom.fsize
    return frags


def flatten_tree(tree, geom):
    recs = []
    alloc = Allocator(geom)
    ino_counter = [ROOTINO]

    def new_ino():
        i = ino_counter[0]
        ino_counter[0] += 1
        return i

    def visit(node, ino, parent_ino):
        rec = InodeRec(ino=ino, node=node, is_dir=(node.kind == "dir"))
        recs.append(rec)
        if node.kind == "dir":
            entries = [(".", ino, DT_DIR), ("..", parent_ino, DT_DIR)]
            child_recs = []
            for name, child in sorted(node.children.items()):
                cino = new_ino()
                entries.append((name, cino, _dtype(child)))
                child_recs.append((child, cino))
            rec.dir_entries = entries
            nbytes = _dir_block_size(entries, geom.bsize)
            rec.size = nbytes
            nfr = _frags_for(nbytes, geom)
            for _ in range(nfr):
                pass
            rec.blocks = _alloc_run(alloc, nbytes, geom)
            for child, cino in child_recs:
                visit(child, cino, ino)
        elif node.kind == "file":
            data = node.data or b""
            rec.size = len(data)
            rec.blocks = _alloc_run(alloc, len(data), geom)
        elif node.kind == "symlink":
            link = (node.linkname or "").encode()
            rec.size = len(link)
            if len(link) < MAXSYMLINKLEN:
                rec.inline_link = link
            else:
                rec.blocks = _alloc_run(alloc, len(link), geom)
        # chr/blk: no data blocks
        return rec

    visit(tree.root, ROOTINO, ROOTINO)
    return recs, ROOTINO


def _alloc_run(alloc, nbytes, geom):
    """Allocate one frag-run per logical block (direct blocks only for now;
    indirect handled at serialize time using these contiguous frags)."""
    if nbytes == 0:
        return []
    blocks = []
    remaining = nbytes
    while remaining > 0:
        chunk = min(remaining, geom.bsize)
        if chunk == geom.bsize:
            blocks.append(alloc.alloc_frags(geom.frag))
        else:
            blocks.append(alloc.alloc_frags((chunk + geom.fsize - 1)
                                            // geom.fsize))
        remaining -= chunk
    return blocks
```

> Note: `_alloc_run` records the **frag address of each logical block**; the
> serializer (Task 13) writes the block data at those addresses and fills
> `di_db[0..11]` plus single/double indirect blocks from this list.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_alloc.py -v`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/ufs.py vm/imgbuild/tests/test_ufs_alloc.py
git commit -m "imgbuild: add UFS allocator and inode/dir flattening"
```

---

### Task 13: UFS serializer (write image bytes)

**Files:**
- Modify: `vm/imgbuild/ufs.py` (add `write_ufs`)
- Test: `vm/imgbuild/tests/test_ufs_write.py`

**Interfaces:**
- Consumes: `Geometry`, `InodeRec`, `formats.ufs_fs`, `formats.ufs_inode`.
- Produces: `write_ufs(tree, total_sectors=None) -> bytes` — returns a byte
  image of the filesystem (length = `size_frags * fsize`), containing:
  boot block (zeros) at 0, superblock at `SBOFF`, the single cg header +
  inode/block bitmaps at `cblkno`, the inode table at `iblkno`, the cg summary
  at `csaddr`, directory/file/indirect data blocks at their allocated frags.
  All integers big-endian. Sizes the fs from the staging tree if
  `total_sectors` is None (content frags + 20% slack, rounded up).

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_ufs_write.py`:
```python
import struct
from stage import StagingTree, Node
from ufs import write_ufs
from formats import ufs_fs

def _tree():
    t = StagingTree()
    t.mkpath("/etc/motd", Node("file", 0o644, data=b"hi\n"))
    return t

def test_superblock_magic_at_sboff():
    img = write_ufs(_tree())
    magic = struct.unpack_from(">i", img, ufs_fs.SBOFF + _fs_magic_off())[0]
    assert magic == ufs_fs.FS_MAGIC

def _fs_magic_off():
    # offset of fs_magic within struct fs
    off = 0
    for name, fmt in ufs_fs.FS.fields:
        if name == "fs_magic":
            return off
        off += ufs_fs.CStruct("t", [(name, fmt)]).size
    raise AssertionError

def test_cg_magic_present():
    img = write_ufs(_tree())
    # scan for CG magic near cblkno region; exact offset checked in reader test
    assert struct.pack(">i", ufs_fs.CG_MAGIC) in img
```

Add `from formats.cstruct import CStruct` import inside `ufs_fs`? No — expose
`CStruct` via `ufs_fs` by adding `from formats.cstruct import CStruct` at the
top of `formats/ufs_fs.py` (it is already imported there). The test references
`ufs_fs.CStruct`; ensure that name is importable (it is, since `ufs_fs` does
`from formats.cstruct import CStruct`).

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_write.py -v`
Expected: FAIL (`cannot import name 'write_ufs'`).

- [ ] **Step 3: Implement `write_ufs` in `ufs.py`**

Append to `vm/imgbuild/ufs.py`:
```python
import struct as _struct
from formats import ufs_fs
from formats.ufs_inode import DINODE, DIRECT_HDR, NDADDR, NIADDR


def _count_nodes(tree):
    n = 1  # root
    for _p, node in tree.walk():
        n += 1
    return n


def _content_frags(tree, geom):
    recs, _ = flatten_tree(tree, geom)
    a = Allocator(geom)
    # replay allocation to learn high-water mark
    total = geom.dblkno
    for r in recs:
        total += sum(_run_frags(b, geom) for b in _iter_run(r))
    return total


def _iter_run(rec):
    return rec.blocks


def _run_frags(_addr, geom):
    return 0  # blocks list already holds addrs; sizing uses recompute below


def _frag_addr_to_byte(addr, geom):
    return addr * geom.fsize


def _put_block(img, addr, data, geom):
    off = _frag_addr_to_byte(addr, geom)
    img[off:off + len(data)] = data


def _fill_indirect(img, addrs, geom, single_only=False):
    """Given the ordered logical-block frag addresses of a file, return the
    12 direct entries and allocate/fill indirect blocks as needed.
    Returns (di_db[12], di_ib[3])."""
    di_db = [0] * NDADDR
    di_ib = [0] * NIADDR
    for i, a in enumerate(addrs[:NDADDR]):
        di_db[i] = a
    rest = addrs[NDADDR:]
    return di_db, di_ib, rest


def write_ufs(tree, total_sectors=None):
    # 1. plan geometry
    nfiles = _count_nodes(tree)
    if total_sectors is None:
        probe = plan_geometry(1 << 20, nfiles)   # generous probe geometry
        recs, _ = flatten_tree(tree, probe)
        alloc = Allocator(probe)
        # recompute allocation deterministically for sizing
        content_end = _replay_alloc_highwater(tree, probe)
        frags = int(content_end * 1.2) + probe.frag * 8
        total_sectors = frags * probe.nspf
    geom = plan_geometry(total_sectors, nfiles)

    img = bytearray(geom.size_frags * geom.fsize)

    # 2. allocate + flatten against the final geometry
    recs, root_ino = flatten_tree(tree, geom)
    by_ino = {r.ino: r for r in recs}
    nused = max(by_ino) + 1

    # 3. write data blocks (files, dirs, long symlinks) + indirect blocks
    indirect_alloc = Allocator(geom)
    indirect_alloc.next_frag = _replay_alloc_highwater(tree, geom)
    di_addrs = {}   # ino -> (di_db, di_ib)
    for r in recs:
        addrs = list(r.blocks)
        # write the actual data into each logical block
        _write_inode_data(img, r, geom)
        di_db, di_ib = _emit_pointers(img, addrs, geom, indirect_alloc)
        di_addrs[r.ino] = (di_db, di_ib)

    # 4. superblock
    _write_superblock(img, geom, recs)

    # 5. cylinder group header + bitmaps + inode table + cg summary
    _write_cg(img, geom, recs, nused)
    _write_inodes(img, geom, recs, di_addrs)
    _write_cgsummary(img, geom, recs)

    return bytes(img)
```

Now implement the helpers referenced above. Append:
```python
def _replay_alloc_highwater(tree, geom):
    recs, _ = flatten_tree(tree, geom)   # flatten already allocated via Allocator
    hi = geom.dblkno
    for r in recs:
        for a in r.blocks:
            hi = max(hi, a + geom.frag)
    return hi


def _write_inode_data(img, rec, geom):
    if rec.is_dir:
        blob = _serialize_dir(rec, geom)
        _scatter(img, blob, rec.blocks, geom)
    elif rec.node.kind == "file":
        _scatter(img, rec.node.data or b"", rec.blocks, geom)
    elif rec.node.kind == "symlink" and rec.inline_link is None:
        _scatter(img, (rec.node.linkname or "").encode(), rec.blocks, geom)


def _scatter(img, data, blocks, geom):
    for i, addr in enumerate(blocks):
        chunk = data[i * geom.bsize:(i + 1) * geom.bsize]
        _put_block(img, addr, chunk, geom)


def _serialize_dir(rec, geom):
    """Pack dir entries into block-sized runs; last entry in each block extends
    its d_reclen to the block boundary (FFS rule)."""
    out = bytearray()
    block = bytearray()
    def flush():
        nonlocal block
        if block:
            # extend last record to fill the block
            pad = geom.bsize - (len(block) % geom.bsize or geom.bsize)
            out.extend(block)
            out.extend(b"\x00" * pad)
            block = bytearray()
    used = 0
    entries = rec.dir_entries
    for idx, (name, ino, dtype) in enumerate(entries):
        nb = name.encode()
        reclen = (8 + len(nb) + 1 + 3) & ~3
        if used + reclen > geom.bsize:
            # pad current block's last record to boundary
            _extend_last(block, geom.bsize - used)
            out.extend(block)
            out.extend(b"\x00" * (geom.bsize - len(block)))
            block = bytearray()
            used = 0
        hdr = DIRECT_HDR.pack({"d_ino": ino, "d_reclen": reclen,
                               "d_type": dtype, "d_namlen": len(nb)})
        rec_bytes = bytearray(hdr + nb + b"\x00" * (reclen - 8 - len(nb)))
        block.extend(rec_bytes)
        used += reclen
    if block:
        _extend_last(block, geom.bsize - used)
        out.extend(block)
        out.extend(b"\x00" * (geom.bsize - len(block)))
    return bytes(out)


def _extend_last(block, extra):
    """Grow the last dir record's d_reclen by `extra` bytes (fill to boundary).
    The last record's header is at some offset; find it by walking."""
    off = 0
    last = 0
    while off < len(block):
        reclen = _struct.unpack_from(">H", block, off + 4)[0]
        last = off
        off += reclen
    if block:
        cur = _struct.unpack_from(">H", block, last + 4)[0]
        _struct.pack_into(">H", block, last + 4, cur + extra)


def _emit_pointers(img, addrs, geom, ind_alloc):
    di_db = [0] * NDADDR
    di_ib = [0] * NIADDR
    for i, a in enumerate(addrs[:NDADDR]):
        di_db[i] = a
    rest = addrs[NDADDR:]
    if rest:
        # single indirect
        sind = ind_alloc.alloc_frags(geom.frag)
        di_ib[0] = sind
        ptrs = rest[:geom.nindir]
        blk = b"".join(_struct.pack(">i", p) for p in ptrs)
        _put_block(img, sind, blk, geom)
        rest = rest[geom.nindir:]
        if rest:
            raise ValueError("file needs double-indirect blocks; "
                             "not supported for minimal base")
    return di_db, di_ib
```

Superblock, cg, inode, and summary writers. Append:
```python
def _write_superblock(img, geom, recs):
    nino_used = len(recs)
    ndir = sum(1 for r in recs if r.is_dir)
    fs = {
        "fs_sblkno": geom.sblkno, "fs_cblkno": geom.cblkno,
        "fs_iblkno": geom.iblkno, "fs_dblkno": geom.dblkno,
        "fs_cgoffset": geom.cgoffset, "fs_cgmask": geom.cgmask,
        "fs_time": 0, "fs_size": geom.size_frags,
        "fs_dsize": geom.size_frags - geom.dblkno,
        "fs_ncg": 1, "fs_bsize": geom.bsize, "fs_fsize": geom.fsize,
        "fs_frag": geom.frag, "fs_minfree": 5,
        "fs_bmask": (~(geom.bsize - 1)) & 0xFFFFFFFF,
        "fs_fmask": (~(geom.fsize - 1)) & 0xFFFFFFFF,
        "fs_bshift": geom.bshift, "fs_fshift": geom.fshift,
        "fs_maxcontig": 1, "fs_maxbpg": geom.fpg // geom.frag,
        "fs_fragshift": geom.fragshift, "fs_fsbtodb": geom.fsbtodb,
        "fs_sbsize": ufs_fs.SBSIZE, "fs_nindir": geom.nindir,
        "fs_inopb": geom.inopb, "fs_nspf": geom.nspf, "fs_optim": 0,
        "fs_csaddr": geom.csaddr, "fs_cssize": geom.bsize,
        "fs_cgsize": geom.bsize, "fs_ntrak": geom.ntrak,
        "fs_nsect": geom.nsect, "fs_spc": geom.spc, "fs_ncyl": geom.ncyl,
        "fs_cpg": geom.cpg, "fs_ipg": geom.ipg, "fs_fpg": geom.fpg,
        "fs_cstotal": [ndir, geom.size_frags - geom.dblkno, 0, 0],
        "fs_clean": 1,
        "fs_fsmnt": b"/",
        "fs_maxsymlinklen": MAXSYMLINKLEN,
        "fs_inodefmt": 2,             # FS_44INODEFMT
        "fs_maxfilesize": (1 << 40),
        "fs_qbmask": geom.bsize - 1, "fs_qfmask": geom.fsize - 1,
        "fs_postblformat": 1,         # FS_DYNAMICPOSTBLFMT
        "fs_nrpos": 1,
        "fs_magic": ufs_fs.FS_MAGIC,
    }
    blob = ufs_fs.FS.pack(fs)
    img[ufs_fs.SBOFF:ufs_fs.SBOFF + len(blob)] = blob


def _bitmap(nbits, set_lo):
    """Return a byte bitmap with the first `set_lo` bits = 1 (allocated)."""
    ba = bytearray((nbits + 7) // 8)
    for b in range(set_lo):
        ba[b >> 3] |= 1 << (b & 7)
    return ba


def _write_cg(img, geom, recs, nused):
    cg_byte = _frag_addr_to_byte(geom.cblkno, geom)
    # map offsets are relative to the start of struct cg
    base = ufs_fs.CG.size
    iused_off = base
    freeoff = iused_off + (geom.ipg + 7) // 8
    # inode used bitmap: inodes 0..nused-1 marked used
    iused = _bitmap(geom.ipg, nused)
    # block free map: frags 0..dblkno used; dblkno..size free
    nfrags = geom.fpg
    freemap = bytearray((nfrags + 7) // 8)
    for f in range(geom.dblkno, geom.size_frags):
        freemap[f >> 3] |= 1 << (f & 7)
    cg = {
        "cg_magic": ufs_fs.CG_MAGIC, "cg_time": 0, "cg_cgx": 0,
        "cg_ncyl": geom.ncyl, "cg_niblk": geom.ipg,
        "cg_ndblk": geom.size_frags,
        "cg_cs": [sum(1 for r in recs if r.is_dir),
                  geom.size_frags - geom.dblkno, geom.ipg - nused, 0],
        "cg_iusedoff": iused_off, "cg_freeoff": freeoff,
        "cg_nextfreeoff": freeoff + len(freemap),
    }
    blob = bytearray(geom.bsize)
    hdr = ufs_fs.CG.pack(cg)
    blob[:len(hdr)] = hdr
    blob[iused_off:iused_off + len(iused)] = iused
    blob[freeoff:freeoff + len(freemap)] = freemap
    img[cg_byte:cg_byte + geom.bsize] = blob


def _write_inodes(img, geom, recs, di_addrs):
    ibase = _frag_addr_to_byte(geom.iblkno, geom)
    for r in recs:
        di_db, di_ib = di_addrs[r.ino]
        mode = r.node.mode | _ifmt(r.node)
        di = {
            "di_mode": mode, "di_nlink": _nlink(r),
            "di_size": r.size,
            "di_mtime": r.node.mtime, "di_atime": r.node.mtime,
            "di_ctime": r.node.mtime,
            "di_db": di_db, "di_ib": di_ib,
            "di_uid": r.node.uid, "di_gid": r.node.gid,
            "di_blocks": _nblocks(r, geom),
        }
        if r.node.kind == "symlink" and r.inline_link is not None:
            di["di_db"] = _inline_symlink_dbs(r.inline_link)
        if r.node.kind in ("chr", "blk"):
            major, minor = r.node.rdev or (0, 0)
            di["di_db"] = [((major & 0xFF) << 24) | (minor & 0xFFFFFF)] + \
                          [0] * (NDADDR - 1)
        blob = DINODE.pack(di)
        # inode N lives at ibase + N * 128 (inode 0,1 reserved but present)
        off = ibase + r.ino * DINODE.size
        img[off:off + DINODE.size] = blob


def _inline_symlink_dbs(link):
    padded = link + b"\x00" * (60 - len(link))
    return [ _struct.unpack_from(">i", padded, i * 4)[0] for i in range(15) ][:NDADDR] \
        + []  # NDADDR ints; remaining stored in di_ib by caller if needed


def _ifmt(node):
    from formats.ufs_inode import IFDIR, IFREG, IFLNK, IFCHR, IFBLK
    return {"dir": IFDIR, "file": IFREG, "symlink": IFLNK,
            "chr": IFCHR, "blk": IFBLK}[node.kind]


def _nlink(rec):
    if rec.is_dir:
        subdirs = sum(1 for (_n, _i, t) in rec.dir_entries if t == DT_DIR)
        return subdirs  # includes '.' and '..' contributions
    return 1


def _nblocks(rec, geom):
    frags = 0
    for _a in rec.blocks:
        frags += geom.frag
    return frags * (geom.fsize // 512)


def _write_cgsummary(img, geom, recs):
    ndir = sum(1 for r in recs if r.is_dir)
    csum = ufs_fs.CSUM.pack({
        "cs_ndir": ndir,
        "cs_nbfree": (geom.size_frags - geom.dblkno) // geom.frag,
        "cs_nifree": geom.ipg - len(recs),
        "cs_nffree": 0,
    })
    off = _frag_addr_to_byte(geom.csaddr, geom)
    img[off:off + len(csum)] = csum
```

> The `_inline_symlink_dbs` and `di_blocks` details are approximations that the
> Task 14 round-trip test and the Task 17 `fsck` check will validate and force
> to exactness. Fix any mismatch the reader/`fsck` reports before moving on —
> do not leave a red test.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_write.py -v`
Expected: PASS (2 passed). If the superblock offset test fails, verify the
`fs_magic` field offset via the reader in Task 14.

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/ufs.py vm/imgbuild/tests/test_ufs_write.py
git commit -m "imgbuild: add UFS serializer (superblock, cg, inodes, dirs)"
```

---

### Task 14: UFS reader + round-trip validation

**Files:**
- Modify: `vm/imgbuild/ufs.py` (add `read_ufs`)
- Test: `vm/imgbuild/tests/test_ufs_roundtrip.py`

**Interfaces:**
- Consumes: an image produced by `write_ufs`.
- Produces: `read_ufs(img) -> dict[path -> ReadNode]` where `ReadNode` has
  `kind, mode, size, data (for files), linkname (for symlinks),
  rdev (for devices)`. Walks from `ROOTINO` following directory blocks and
  inode block pointers (direct + single indirect). Used to assert that what
  was written reads back identically to the staging tree.

- [ ] **Step 1: Write the failing round-trip test**

`vm/imgbuild/tests/test_ufs_roundtrip.py`:
```python
from stage import StagingTree, Node
from ufs import write_ufs, read_ufs

def _tree():
    t = StagingTree()
    t.mkpath("/etc/motd", Node("file", 0o644, data=b"welcome\n"))
    t.mkpath("/bin/sh", Node("file", 0o755, data=b"X" * 9000))
    t.mkpath("/usr/lib/libc.so", Node("symlink", 0o777, linkname="libc.1.so"))
    return t

def test_roundtrip_files_and_dirs():
    t = _tree()
    img = write_ufs(t)
    back = read_ufs(img)
    assert back["/etc/motd"].data == b"welcome\n"
    assert back["/bin/sh"].data == b"X" * 9000
    assert back["/bin/sh"].size == 9000
    assert back["/usr/lib/libc.so"].kind == "symlink"
    assert back["/usr/lib/libc.so"].linkname == "libc.1.so"

def test_roundtrip_modes_preserved():
    img = write_ufs(_tree())
    back = read_ufs(img)
    assert back["/bin/sh"].mode & 0o777 == 0o755
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_roundtrip.py -v`
Expected: FAIL (`cannot import name 'read_ufs'`).

- [ ] **Step 3: Implement `read_ufs` in `ufs.py`**

Append to `vm/imgbuild/ufs.py`:
```python
from dataclasses import dataclass as _dc
from formats.ufs_inode import (IFDIR, IFREG, IFLNK, IFCHR, IFBLK)


@_dc
class ReadNode:
    kind: str
    mode: int
    size: int
    data: bytes = None
    linkname: str = None
    rdev: tuple = None


def _read_geom(img):
    fs = ufs_fs.FS.unpack(img[ufs_fs.SBOFF:ufs_fs.SBOFF + ufs_fs.FS.size])
    if fs["fs_magic"] != ufs_fs.FS_MAGIC:
        raise ValueError("bad fs magic")
    return fs


def _inode(img, fs, ino):
    ibase = fs["fs_iblkno"] * fs["fs_fsize"]
    off = ibase + ino * DINODE.size
    return DINODE.unpack(img[off:off + DINODE.size])


def _file_bytes(img, fs, di):
    size = di["di_size"]
    frag = fs["fs_frag"]
    bsize = fs["fs_bsize"]
    fsize = fs["fs_fsize"]
    ptrs = list(di["di_db"])
    if di["di_ib"][0]:
        sind = di["di_ib"][0] * fsize
        nindir = fs["fs_nindir"]
        for i in range(nindir):
            p = _struct.unpack_from(">i", img, sind + i * 4)[0]
            if p == 0:
                break
            ptrs.append(p)
    out = bytearray()
    remaining = size
    for a in ptrs:
        if remaining <= 0:
            break
        byte = a * fsize
        chunk = min(remaining, bsize)
        out.extend(img[byte:byte + chunk])
        remaining -= chunk
    return bytes(out[:size])


def _read_dir(img, fs, di):
    raw = _file_bytes(img, fs, di)
    entries = []
    off = 0
    while off < len(raw):
        ino, reclen, dtype, namlen = DIRECT_HDR.unpack(raw[off:off + 8])
        if reclen == 0:
            break
        name = raw[off + 8:off + 8 + namlen].decode()
        if ino != 0:
            entries.append((name, ino))
        off += reclen
    return entries


def read_ufs(img):
    fs = _read_geom(img)
    out = {}

    def walk(ino, prefix):
        di = _inode(img, fs, ino)
        for name, cino in _read_dir(img, fs, di):
            if name in (".", ".."):
                continue
            path = prefix + "/" + name
            cdi = _inode(img, fs, cino)
            fmt = cdi["di_mode"] & 0xF000
            if fmt == IFDIR:
                out[path] = ReadNode("dir", cdi["di_mode"], cdi["di_size"])
                walk(cino, path)
            elif fmt == IFREG:
                out[path] = ReadNode("file", cdi["di_mode"], cdi["di_size"],
                                     data=_file_bytes(img, fs, cdi))
            elif fmt == IFLNK:
                link = _read_symlink(img, fs, cdi)
                out[path] = ReadNode("symlink", cdi["di_mode"],
                                     cdi["di_size"], linkname=link)
            elif fmt in (IFCHR, IFBLK):
                dev = cdi["di_db"][0]
                out[path] = ReadNode("chr" if fmt == IFCHR else "blk",
                                     cdi["di_mode"], 0,
                                     rdev=((dev >> 24) & 0xFF, dev & 0xFFFFFF))

    walk(ROOTINO, "")
    return out


def _read_symlink(img, fs, di):
    size = di["di_size"]
    if size < fs.get("fs_maxsymlinklen", MAXSYMLINKLEN) and not di["di_ib"][0]:
        # inline: bytes are stored in di_db/di_ib area
        raw = b"".join(_struct.pack(">i", x) for x in di["di_db"])
        return raw[:size].decode()
    return _file_bytes(img, fs, di).decode()
```

> If a round-trip assertion fails, the writer (Task 13) is wrong — fix the
> writer, not the reader. The reader is the oracle. Common culprits: inline
> symlink byte packing, `di_blocks` units, dir record padding.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_ufs_roundtrip.py -v`
Expected: PASS (2 passed). Iterate on the Task 13 writer until green.

- [ ] **Step 5: Run the whole suite + commit**

Run: `python -m pytest vm/imgbuild/tests -v`
Expected: all green.

```bash
git add vm/imgbuild/ufs.py vm/imgbuild/tests/test_ufs_roundtrip.py
git commit -m "imgbuild: add UFS reader and round-trip validation"
```

---

### Task 15: Disk assembler (MBR + label + boot blocks + splice)

**Files:**
- Create: `vm/imgbuild/disk.py`
- Test: `vm/imgbuild/tests/test_disk.py`

**Interfaces:**
- Consumes: `formats.fdisk.build_mbr`, `formats.label.build_label`,
  `StagingTree` (to read `/usr/standalone/i386/{boot0,boot1,boot}`), a UFS
  image blob.
- Produces:
  - `PART_LBA = 63` (partition start), `LABEL_SECTOR = 15`,
    `BOOT_RESERVED_SECTORS = 29`.
  - `assemble_disk(ufs_img, tree) -> bytes` — a raw disk image:
    sector 0 = MBR (`boot0` + `0xA7` active partition at `PART_LBA`);
    partition sector 0 = `boot1`; `boot` (boot2) written into the reserved
    sectors after `boot1`; partition sector 15 = NeXT label (×4 consecutive
    copies); UFS spliced at partition offset `dl_front` (front porch large
    enough to clear the boot+label area, block-aligned).
  - `get_boot_bits(tree) -> (boot0, boot1, boot2)` — raises if any is missing.

- [ ] **Step 1: Write the failing test**

`vm/imgbuild/tests/test_disk.py`:
```python
import struct
from stage import StagingTree, Node
from disk import assemble_disk, PART_LBA, LABEL_SECTOR
from formats import label

def _tree_with_boot():
    t = StagingTree()
    t.mkpath("/usr/standalone/i386/boot0", Node("file", data=b"\xEB" + b"0" * 100))
    t.mkpath("/usr/standalone/i386/boot1", Node("file", data=b"1" * 512))
    t.mkpath("/usr/standalone/i386/boot", Node("file", data=b"2" * 2048))
    return t

def test_mbr_signature_and_partition():
    img = assemble_disk(ufs_img=b"U" * 8192, tree=_tree_with_boot())
    assert img[510] == 0x55 and img[511] == 0xAA
    systid = img[446 + 4]
    assert systid == 0xA7
    relsect = struct.unpack_from("<I", img, 446 + 8)[0]
    assert relsect == PART_LBA

def test_label_at_partition_sector_15():
    img = assemble_disk(ufs_img=b"U" * 8192, tree=_tree_with_boot())
    off = (PART_LBA + LABEL_SECTOR) * 512
    dl = label.DISK_LABEL.unpack(img[off:off + label.DISK_LABEL.size])
    assert dl["dl_version"] == label.DL_V3
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_disk.py -v`
Expected: FAIL (`No module named 'disk'`).

- [ ] **Step 3: Implement `disk.py`**

`vm/imgbuild/disk.py`:
```python
from formats.fdisk import build_mbr
from formats import label

PART_LBA = 63
LABEL_SECTOR = 15
BOOT_RESERVED_SECTORS = 29
SECTOR = 512
NLABEL_COPIES = 4


def get_boot_bits(tree):
    def need(path):
        n = tree.get(path)
        if n is None or n.kind != "file":
            raise ValueError("missing boot component: %s" % path)
        return n.data
    return (need("/usr/standalone/i386/boot0"),
            need("/usr/standalone/i386/boot1"),
            need("/usr/standalone/i386/boot"))


def assemble_disk(ufs_img, tree):
    boot0, boot1, boot2 = get_boot_bits(tree)

    # front porch: clear boot1 (sector 0) + reserved boot area + label copies.
    # Place the label at sector 15, then UFS after the reserved region.
    front_sectors = max(BOOT_RESERVED_SECTORS,
                        LABEL_SECTOR + NLABEL_COPIES) + 1
    # block-align the front porch to the fs block size (16 sectors @ 8k)
    front_sectors = ((front_sectors + 15) // 16) * 16

    ufs_sectors = (len(ufs_img) + SECTOR - 1) // SECTOR
    part_sectors = front_sectors + ufs_sectors
    total_sectors = PART_LBA + part_sectors

    disk = bytearray(total_sectors * SECTOR)

    # MBR
    disk[0:SECTOR] = build_mbr(boot0, PART_LBA, part_sectors)

    part_off = PART_LBA * SECTOR

    # boot1 in the partition boot sector
    disk[part_off:part_off + len(boot1)] = boot1
    # boot2 in the reserved sectors immediately after boot1's sector
    b2_off = part_off + SECTOR
    disk[b2_off:b2_off + len(boot2)] = boot2

    # NeXT label x4 at partition sector 15
    lbl = label.build_label(
        dl_size=total_sectors, secsize=SECTOR, front=front_sectors,
        part_base=0, part_size=ufs_sectors, bootfile=b"mach_kernel")
    for i in range(NLABEL_COPIES):
        loff = part_off + (LABEL_SECTOR + i) * SECTOR
        disk[loff:loff + len(lbl)] = lbl

    # UFS spliced at partition front porch
    ufs_off = part_off + front_sectors * SECTOR
    disk[ufs_off:ufs_off + len(ufs_img)] = ufs_img

    return bytes(disk)
```

> **Ground-truth reconciliation (do this in this task):** dump the real
> `rhapsody.vmdk` — sector 0 (MBR/fdisk), the active partition's sector 15
> (NeXT label) — and compare field-by-field against what `build_mbr`/
> `build_label` emit (`PART_LBA`, `dl_front`, `p_base`, the label checksum
> algorithm, boot2 sector placement). Adjust constants/algorithms here and in
> `formats/label.py` to match the real disk. The boot loader only checks
> `dl_version`, but matching the real layout de-risks Task 17.

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_disk.py -v`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add vm/imgbuild/disk.py vm/imgbuild/tests/test_disk.py
git commit -m "imgbuild: add disk assembler (MBR, label, boot blocks, splice)"
```

---

### Task 16: CLI orchestrator

**Files:**
- Create: `vm/imgbuild/build.py`
- Test: `vm/imgbuild/tests/test_build_cli.py`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `build_image(repo_dirs, arch, preset_or_list, out_path,
    tar_cache_dir) -> dict` (summary: package count, image bytes, fs bytes).
  - `main(argv=None)` — argparse CLI:
    `--repo DIR (repeatable)`, `--arch i386`, `--preset minimal-base` or
    `--packages FILE`, `--out PATH`, `--cache DIR`.

- [ ] **Step 1: Write the failing test (uses synthetic packages, no guest)**

`vm/imgbuild/tests/test_build_cli.py`:
```python
import os
import struct
from fixtures.make_apk import make_apk
from build import build_image
from formats import ufs_fs

def _make_repo(tmp_path):
    # a tiny self-consistent apk repo: boot bits + kernel + a base pkg
    d = tmp_path / "repo"
    d.mkdir()
    make_apk(str(d / "boot-1.apk"), name="boot", arch="i386", files=[
        ("usr/standalone/i386/boot0", b"\xEB" + b"0" * 60),
        ("usr/standalone/i386/boot1", b"1" * 512),
        ("usr/standalone/i386/boot", b"2" * 2048),
    ])
    make_apk(str(d / "kernel-1.apk"), name="kernel", arch="i386", files=[
        ("private/tftpboot/mach_kernel", b"KERNELIMAGE"),
    ])
    make_apk(str(d / "files-1.apk"), name="files", arch="i386", files=[
        ("etc/motd", b"hi\n"),
    ])
    return str(d)

def test_build_end_to_end(tmp_path):
    repo = _make_repo(tmp_path)
    out = str(tmp_path / "out.img")
    summary = build_image([repo], "i386", ["boot", "kernel", "files"],
                          out, str(tmp_path / "cache"))
    assert os.path.exists(out)
    data = open(out, "rb").read()
    assert data[510] == 0x55 and data[511] == 0xAA  # MBR
    assert summary["packages"] == 3
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest vm/imgbuild/tests/test_build_cli.py -v`
Expected: FAIL (`No module named 'build'`).

- [ ] **Step 3: Implement `build.py`**

`vm/imgbuild/build.py`:
```python
import argparse
import os

from repo import PackageIndex
from solve import select, MINIMAL_BASE
from stage import build_staging, ensure_mach_kernel
from dpkgdb import write_dpkg_db
from devnodes import write_dev_nodes, write_firstboot
from ufs import write_ufs
from disk import assemble_disk


def build_image(repo_dirs, arch, preset_or_list, out_path, tar_cache_dir):
    index = PackageIndex.from_dirs(repo_dirs, tar_cache_dir)
    roots = MINIMAL_BASE if preset_or_list == "minimal-base" else preset_or_list
    metas = select(index, roots, arch)

    tree, manifest = build_staging(metas)
    ensure_mach_kernel(tree)
    write_dpkg_db(tree, metas, manifest)
    write_dev_nodes(tree)
    write_firstboot(tree, metas)

    ufs_img = write_ufs(tree)
    disk_img = assemble_disk(ufs_img, tree)
    with open(out_path, "wb") as f:
        f.write(disk_img)

    return {"packages": len(metas), "fs_bytes": len(ufs_img),
            "image_bytes": len(disk_img), "out": out_path}


def main(argv=None):
    ap = argparse.ArgumentParser(description="RhapsodiOS bootable image builder")
    ap.add_argument("--repo", action="append", required=True, dest="repos")
    ap.add_argument("--arch", default="i386")
    ap.add_argument("--preset", default="minimal-base")
    ap.add_argument("--packages", help="file with one package name per line")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cache", default=os.path.join(os.getcwd(),
                    ".imgbuild-cache"))
    args = ap.parse_args(argv)
    if args.packages:
        roots = [l.strip() for l in open(args.packages) if l.strip()]
    else:
        roots = args.preset
    summary = build_image(args.repos, args.arch, roots, args.out, args.cache)
    print("built %(out)s: %(packages)d packages, %(image_bytes)d bytes"
          % summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest vm/imgbuild/tests/test_build_cli.py -v`
Expected: PASS (1 passed).

- [ ] **Step 5: Run the whole suite + commit**

Run: `python -m pytest vm/imgbuild/tests -v`
Expected: all green.

```bash
git add vm/imgbuild/build.py vm/imgbuild/tests/test_build_cli.py
git commit -m "imgbuild: add CLI orchestrator wiring all stages"
```

---

### Task 17: End-to-end boot in QEMU + ground-truth reconciliation

**Files:**
- Create: `vm/imgbuild/README.md`
- Modify: `vm/imgbuild/formats/label.py`, `vm/imgbuild/disk.py`,
  `vm/imgbuild/devnodes.py` (only if reconciliation finds discrepancies)
- Modify: `docs/boot/boot-i386.md` (add a "building a bootable image" note
  linking to `vm/imgbuild/README.md`) — optional

**This task is verification-driven, not TDD.** Its deliverable is a real image
that boots. Do the reconciliation the earlier tasks flagged, then boot.

- [ ] **Step 1: Reconcile the on-disk format against the real disk**

Dump reference structures from the golden guest disk and compare to the
builder's output. On the host:
```bash
python - <<'PY'
# dump MBR + first partition's sector 15 (NeXT label) from rhapsody.vmdk.
# vmdk here is a flat/2GB sparse image; if not raw, first convert:
#   vm/qemu-img.exe convert -O raw vm/rhapsody.vmdk /tmp/rhap.raw
raw = open(r"/tmp/rhap.raw", "rb").read(64*1024*1024)
mbr = raw[:512]
print("sig", hex(mbr[510]), hex(mbr[511]))
import struct
for i in range(4):
    e = mbr[446+i*16:446+(i+1)*16]
    bootid, systid = e[0], e[4]
    relsect, numsect = struct.unpack_from("<II", e, 8)
    print("part", i, "bootid", hex(bootid), "systid", hex(systid),
          "relsect", relsect, "numsect", numsect)
    if systid == 0xA7:
        loff = (relsect + 15) * 512
        print("  label ver", hex(struct.unpack_from(">i", raw, loff)[0]))
PY
```
Compare `relsect` (our `PART_LBA`), the label version/offset, `dl_front`,
`p_base`, and the label checksum to the builder. **Update
`formats/label.py` and `disk.py` constants/algorithms to match.** Record the
real device-node major/minor numbers (from the guest `ls -l /dev`) into
`devnodes.py::DEV_NODES`.

- [ ] **Step 2: Build a minimal image from the real repository**

```bash
cd /d/RhapsodiOS
python vm/imgbuild/build.py --repo vm/debs --arch i386 \
  --preset minimal-base --out vm/rhapsody-i386.img --cache vm/.imgbuild-cache
```
Expected: prints `built vm/rhapsody-i386.img: N packages, M bytes`.

- [ ] **Step 3: Optional read-only fsck sanity via the golden guest**

Attach the built image as a second disk to the golden guest and run
`fsck -n` / `dumpfs` on the partition. (Use a temporary disk image per
CLAUDE.md §6 so a parallel debugging session is not disturbed.) Fix any writer
error `fsck` reports (re-run the Task 14 round-trip after each fix).

- [ ] **Step 4: Boot the image in qemu.exe**

Create `vm/start-imgbuild.cmd` (mirror `vm/start-vm.cmd`, pointing `-hda` at
`vm\rhapsody-i386.img`, raw format). Boot and observe the console:
```
qemu.exe -hda rhapsody-i386.img -boot c ... (match start-vm.cmd options)
```
Expected boot chain (per `docs/boot/boot-i386.md`):
`boot0 → boot1 → boot` banner → `mach_kernel` loads → BSD `main` mounts root →
`/etc/rc.boot` / `/etc/rc` → login prompt.

- [ ] **Step 5: Capture results and document**

Write `vm/imgbuild/README.md`: prerequisites (Python 3.13), the build command,
the boot command, the single-cg size limit, the apk-untested caveat, and the
reconciliation notes (real `PART_LBA`, label checksum, device majors). Record
how far the boot got and any remaining gaps.

- [ ] **Step 6: Commit**

```bash
git add vm/imgbuild/README.md vm/start-imgbuild.cmd vm/imgbuild/formats/label.py vm/imgbuild/disk.py vm/imgbuild/devnodes.py docs/boot/boot-i386.md
git commit -m "imgbuild: reconcile on-disk format and boot minimal image in qemu"
```

---

## Self-Review

**Spec coverage:**
- Repository index + deb/apk readers → Tasks 5, 6. ✓
- Selection/solve + arch-vs-universal + minimal-base → Task 7. ✓
- Rootfs staging + manifest + mach_kernel fixup → Task 8. ✓
- dpkg DB synthesis → Task 9. ✓
- Static /dev + deferred maintainer scripts → Task 10. ✓
- Big-endian UFS1 writer (approach A, single cg) → Tasks 11–13; reader/round-trip → Task 14. ✓
- Disk assembler (MBR/fdisk/label/boot blocks/splice) → Task 15. ✓
- CLI + convert/run → Task 16; qemu boot + convert note → Task 17. ✓
- On-disk struct definitions → Tasks 1–4. ✓
- Testing ladder (round-trip → fsck → boot) → Tasks 14, 17. ✓

**Known approximations deliberately deferred to reader/`fsck`/boot validation
(flagged inline):** NeXT label checksum algorithm, inline-symlink byte packing,
`di_blocks` units, `di_nlink` for directories, device major/minor encoding,
`PART_LBA`/`dl_front` exact values. Each has an explicit reconciliation step in
Task 15 or 17 and is gated by a real test (round-trip or `fsck`/boot) — none is
left as a silent placeholder.

**Type consistency:** `PackageMeta`, `Node`, `Geometry`, `InodeRec`,
`ReadNode`, `StagingTree`, `PackageIndex` names and their methods
(`by_name`, `all`, `get`, `mkpath`, `walk`, `open_payload`, `select`,
`write_ufs`, `read_ufs`, `assemble_disk`, `build_image`) are used consistently
across tasks.

## Scope Note

This is one cohesive subsystem (the image builder) producing working, testable
software incrementally — appropriate for a single plan. PowerPC support is a
separate future plan reusing Tasks 1, 4–14 (the package + UFS core) with a new
partition/boot layer (Apple Partition Map + Open Firmware + `qemu-system-ppc`).
