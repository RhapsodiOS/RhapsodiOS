# Install media phase 1: partitioned-disk boot — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Boot a single MBR disk that holds an ESP and a `0xA7` Rhapsody
partition under both SeaBIOS and IA32 UEFI, all driven from this Windows host.

**Architecture:** The booters and the kernel already handle fdisk disks, as
long as the label inside the partition holds absolute addresses, which is how
`disk -i -b` writes it. So the test disk builder has to write that correctly:
boot0, an active entry, LBA-assisted CHS, and labels rebased from the
whole-disk image being copied in. The UEFI loader gains two things: choosing
the disk it was loaded from, and honouring `Kernel Flags`. A pure-Python FAT32
writer and a Python QEMU runner make the whole loop work on Windows without
mtools or `sh` path-conversion problems.

**Tech Stack:**
- Python 3.13, standard library only, with `unittest`
- C gnu89 for `bootefi`, built with LLVM 22 (`clang`, `lld-link`) at
  `C:\Program Files\LLVM\bin`
- GNU make (scoop shim)
- QEMU 11.1 at `C:\Program Files\qemu`, using its bundled SeaBIOS and
  `share/edk2-i386-*.fd`

**Spec:** `docs/superpowers/specs/2026-09-22-install-media-design.md`,
phase 1. Read *Labels on fdisk disks* before starting.

## Global Constraints

- **Worktree.** Work in a git worktree, not the shared checkout:
  `git worktree add -b install-media-p1 .claude/worktrees/install-media-p1 HEAD`.
  Parallel sessions share the main checkout's git index.
- **Images live in the main checkout.** They are gitignored and don't come with
  the worktree. The source image is `/d/RhapsodiOS/vm/work/test.img`, and it is
  only ever *read*. Its `/mach_kernel` must match
  `/d/RhapsodiOS/vm/install/mach_kernel` (SHA-256 prefix `9916e7c0bdac2d4e`).
- **Two path spellings.** Shell tools (`cp`, `make`) take `/d/RhapsodiOS/...`.
  Python on Windows needs `D:/RhapsodiOS/...`: a `/d/...` path given to Python
  names nothing, and a test guarded by `os.path.exists` then skips silently.
- **Never boot or write `vm/golden.img` or `vm/rhapsody.vmdk`.** Every QEMU
  boot uses `-snapshot` on a throwaway copy under the worktree's `vm/work/`
  (CLAUDE.md §6).
- **Python:** standard library only. No `pip install`, no mtools.
- **`src/boot-2` stays byte-for-byte unchanged.** `bootefi` compiles those
  sources in place, and they must keep building with the Rhapsody toolchain.
- **`bootefi` C:** `-std=gnu89 -ffreestanding` for the loader. Host tests are
  pure C built with `-std=gnu89 -Wall -Werror`.
- **LLVM on PATH.** Every shell that runs `make` in `src/bootefi-1` first runs
  `export PATH="/c/Program Files/LLVM/bin:$PATH"`, so the Makefiles' default
  `CC=clang` and `LINK=lld-link` resolve.
- **QEMU paths come from Python.** Git Bash doesn't convert
  `-serial file:/d/...` for native QEMU, so every QEMU run goes through
  `vm/qemu_boot.py`.
- **Commits:** one or two short lines starting with the subsystem (`vm:`,
  `bootefi:`, `docs:`), saying what changed. No trailers or other metadata
  (CLAUDE.md §5).
- **Root-mount evidence:** a kernel log (COM2) containing `rootdev 300` and
  none of `cannot mount root`, `panic`, `root device?`,
  `Label in wrong location`, plus a final screenshot that shows userland
  rather than the kernel console.

## File structure

| File | Status | Responsibility |
|---|---|---|
| `vm/fat32.py` | create | Write and read small FAT32 volumes (ESP only: 8.3 names, one cluster per directory) |
| `vm/test_fat32.py` | create | Unit tests for `fat32` |
| `vm/build_uefi_image.py` | modify | Hybrid and ESP-only disks: FAT via `fat32`, boot0, active entry, LBA-assisted CHS, label rebase |
| `vm/test_build_uefi_image.py` | modify | Tests for the above, including a round-trip through `rhap_image` on real DR2 media |
| `vm/rhap_image.py` | modify | Find the label inside the first `0xA7` fdisk partition |
| `vm/qemu_boot.py` | create | Boot an image with SeaBIOS or IA32 edk2, capture both consoles and screenshots |
| `vm/test_qemu_boot.py` | create | Unit tests for the QEMU argument builder and safety check |
| `vm/check_rootmount.py` | create | Judge a kernel log for root-mount evidence |
| `vm/test_check_rootmount.py` | create | Unit tests for that judgement |
| `src/bootefi-1/Makefile` | modify | Stage the symlinked include directories on checkouts without symlinks; add the new sources |
| `src/bootefi-1/efi.h` | modify | `LOADED_IMAGE` and `DEVICE_PATH` protocol declarations |
| `src/bootefi-1/efi_disk_select.{h,c}` | create | Pure helpers: fdisk-aware label LBA, device-path parent test |
| `src/bootefi-1/efi_disk.c` | modify | Use them: prefer the disk the loader was read from |
| `src/bootefi-1/efi_bootargs.{h,c}` | create | Pure helper: append `Kernel Flags` to the boot string |
| `src/bootefi-1/efi_main.c` | modify | Call it after `loadSystemConfig()` |
| `src/bootefi-1/tests/efi_disk_select_test.c` | create | Host test |
| `src/bootefi-1/tests/efi_bootargs_test.c` | create | Host test |
| `src/bootefi-1/tests/Makefile` | modify | `test-disk-select`, `test-bootargs` targets |
| `docs/boot/partitioned-disk-boot.md` | create | The label convention and the phase 1 boot evidence |

---

### Task 1: FAT32 writer and reader

**Files:**
- Create: `vm/fat32.py`
- Test: `vm/test_fat32.py`

**Interfaces:**
- Produces: `fat32.build(total_sectors: int, files: dict[str, bytes], label: str = "RHAPEFI", hidden_sectors: int = 0) -> bytes`,
  `fat32.read_file(image: bytes, path: str) -> bytes`, `fat32.FatError`,
  `fat32.FAT32_MIN_CLUSTERS = 65525`. Paths look like `"EFI/BOOT/BOOTIA32.EFI"`.

- [ ] **Step 1: Write the failing tests**

Create `vm/test_fat32.py`:

```python
import struct
import unittest

import fat32

SECTORS = 131072            # 64 MB, the ESP size build_uefi_image uses
APP_PATH = "EFI/BOOT/BOOTIA32.EFI"


def _payload(n):
    return bytes((i * 131 + 7) & 0xFF for i in range(n))


class TestFat32(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = _payload(70001)
        cls.image = fat32.build(SECTORS, {APP_PATH: cls.app},
                                hidden_sectors=2048)

    def test_size_is_exact(self):
        self.assertEqual(len(self.image), SECTORS * 512)

    def test_boot_sector_describes_fat32(self):
        img = self.image
        self.assertEqual(img[510:512], b"\x55\xaa")
        self.assertEqual(img[82:90], b"FAT32   ")
        self.assertEqual(struct.unpack_from("<HBHB", img, 11), (512, 1, 32, 2))
        self.assertEqual(struct.unpack_from("<I", img, 28)[0], 2048)
        self.assertEqual(struct.unpack_from("<I", img, 32)[0], SECTORS)
        self.assertEqual(struct.unpack_from("<I", img, 44)[0], 2)

    def test_backup_boot_sector_matches(self):
        self.assertEqual(self.image[6 * 512:7 * 512], self.image[0:512])

    def test_fsinfo_signatures(self):
        fsi = self.image[512:1024]
        self.assertEqual(struct.unpack_from("<I", fsi, 0)[0], 0x41615252)
        self.assertEqual(struct.unpack_from("<I", fsi, 484)[0], 0x61417272)
        self.assertEqual(struct.unpack_from("<I", fsi, 508)[0], 0xAA550000)

    def test_cluster_count_is_in_fat32_range(self):
        fatsz = struct.unpack_from("<I", self.image, 36)[0]
        clusters = SECTORS - 32 - 2 * fatsz
        self.assertGreaterEqual(clusters, fat32.FAT32_MIN_CLUSTERS)
        self.assertGreaterEqual(fatsz * 512 // 4, clusters + 2)

    def test_both_fats_are_identical(self):
        fatsz = struct.unpack_from("<I", self.image, 36)[0]
        first = self.image[32 * 512:(32 + fatsz) * 512]
        second = self.image[(32 + fatsz) * 512:(32 + 2 * fatsz) * 512]
        self.assertEqual(first, second)

    def test_file_reads_back(self):
        self.assertEqual(fat32.read_file(self.image, APP_PATH), self.app)

    def test_build_is_deterministic(self):
        again = fat32.build(SECTORS, {APP_PATH: self.app}, hidden_sectors=2048)
        self.assertEqual(again, self.image)

    def test_missing_file_raises(self):
        with self.assertRaises(fat32.FatError):
            fat32.read_file(self.image, "EFI/BOOT/BOOTX64.EFI")


class TestFat32Refusals(unittest.TestCase):
    def test_empty_file_reads_back_empty(self):
        image = fat32.build(SECTORS, {"EMPTY.TXT": b""})
        self.assertEqual(fat32.read_file(image, "EMPTY.TXT"), b"")

    def test_lower_case_name_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(SECTORS, {"EFI/BOOT/bootia32.efi": b"x"})

    def test_long_name_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(SECTORS, {"EFI/BOOT/LONGFILENAME.EFI": b"x"})

    def test_too_few_clusters_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(32768, {APP_PATH: b"x"})

    def test_overfull_volume_rejected(self):
        with self.assertRaises(fat32.FatError):
            fat32.build(70000, {"BIG.BIN": b"\0" * (70000 * 512)})

    def test_directory_needing_two_clusters_rejected(self):
        files = dict(("D/F%02d.BIN" % i, b"x") for i in range(20))
        with self.assertRaises(fat32.FatError):
            fat32.build(SECTORS, files)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd vm && python -m unittest test_fat32 -v`
Expected: ERROR, `ModuleNotFoundError: No module named 'fat32'`.

- [ ] **Step 3: Write the implementation**

Create `vm/fat32.py`:

```python
"""Write and read small FAT32 volumes with the standard library only.

Enough FAT32 for an EFI System Partition, and deliberately no more: 8.3
names, one sector per cluster, one cluster per directory, files stored
contiguously.  build() raises FatError for anything outside that instead of
producing a volume the firmware would misread.

Layout follows Microsoft's FAT specification (fatgen103): 32 reserved
sectors with FSInfo at sector 1 and a backup boot sector at 6, two FATs, and
the root directory at cluster 2.
"""
import struct

SECTOR = 512
RESERVED = 32
NUM_FATS = 2
ROOT_CLUSTER = 2
FAT32_MIN_CLUSTERS = 65525      # below this the firmware reads it as FAT16
EOC = 0x0FFFFFFF
ATTR_VOLUME_ID = 0x08
ATTR_DIRECTORY = 0x10
ATTR_ARCHIVE = 0x20
DIRENT = 32
ENTRIES_PER_DIR = SECTOR // DIRENT
# A fixed timestamp (1999-06-01 00:00) keeps builds byte-for-byte repeatable.
DOS_DATE = ((1999 - 1980) << 9) | (6 << 5) | 1
DOS_TIME = 0
VOLUME_ID = 0x52484150          # "RHAP"
_NAME_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-~!#$%&'()@^{}")


class FatError(Exception):
    pass


def short_name(component):
    """The 11-byte directory-entry name for an upper-case 8.3 component."""
    base, _, ext = component.partition(".")
    if (not base or len(base) > 8 or len(ext) > 3 or "." in ext
            or not set(base + ext) <= _NAME_CHARS):
        raise FatError("%r is not an upper-case 8.3 name" % component)
    return (base.ljust(8) + ext.ljust(3)).encode("ascii")


def fat_sectors(total_sectors):
    """FATSz32 for one sector per cluster (fatgen103, "FAT Volume
    Initialization")."""
    tmp1 = total_sectors - RESERVED
    tmp2 = (256 * 1 + NUM_FATS) // 2
    return (tmp1 + tmp2 - 1) // tmp2


def _dirent(name11, attr, cluster, size):
    e = bytearray(DIRENT)
    e[0:11] = name11
    e[11] = attr
    struct.pack_into("<HHH", e, 14, DOS_TIME, DOS_DATE, DOS_DATE)
    struct.pack_into("<HHHHI", e, 20, cluster >> 16, DOS_TIME, DOS_DATE,
                     cluster & 0xFFFF, size)
    return bytes(e)


def _tree(files):
    """{dir path: {name11: ("dir", child path) | ("file", data)}}"""
    dirs = {"": {}}
    for path in sorted(files):
        parts = path.split("/")
        parent = ""
        for comp in parts[:-1]:
            name11 = short_name(comp)
            child = comp if not parent else parent + "/" + comp
            kind = dirs[parent].setdefault(name11, ("dir", child))[0]
            if kind != "dir":
                raise FatError("%s is both a file and a directory" % child)
            dirs.setdefault(child, {})
            parent = child
        name11 = short_name(parts[-1])
        if name11 in dirs[parent]:
            raise FatError("%s appears twice" % path)
        dirs[parent][name11] = ("file", files[path])
    return dirs


def build(total_sectors, files, label="RHAPEFI", hidden_sectors=0):
    """Return a FAT32 volume of total_sectors as bytes.

    files maps "DIR/SUB/NAME.EXT" paths to contents; parent directories are
    created as needed.  hidden_sectors is the partition's starting LBA,
    recorded in the BPB as the specification asks.
    """
    if len(label) > 11:
        raise FatError("volume label %r is longer than 11 characters" % label)
    label11 = label.upper().ljust(11).encode("ascii")
    fatsz = fat_sectors(total_sectors)
    data_start = RESERVED + NUM_FATS * fatsz
    clusters = total_sectors - data_start
    if clusters < FAT32_MIN_CLUSTERS:
        raise FatError("%d sectors give %d clusters; FAT32 needs at least %d"
                       % (total_sectors, clusters, FAT32_MIN_CLUSTERS))

    dirs = _tree(files)
    # Root first, then the other directories shallowest first, then data.
    order = sorted(dirs, key=lambda d: (d.count("/") if d else -1, d))
    dir_cluster = dict((d, ROOT_CLUSTER + i) for i, d in enumerate(order))
    next_cluster = ROOT_CLUSTER + len(order)
    fat = [0] * (clusters + 2)
    fat[0] = 0x0FFFFFF8
    fat[1] = EOC
    for d in order:
        fat[dir_cluster[d]] = EOC

    image = bytearray(total_sectors * SECTOR)
    file_cluster = {}
    for d in order:
        for name11, (kind, value) in sorted(dirs[d].items()):
            if kind != "file":
                continue
            if not value:
                file_cluster[(d, name11)] = 0
                continue
            n = (len(value) + SECTOR - 1) // SECTOR
            if next_cluster + n > clusters + 2:
                raise FatError("contents do not fit in %d sectors"
                               % total_sectors)
            for c in range(next_cluster, next_cluster + n - 1):
                fat[c] = c + 1
            fat[next_cluster + n - 1] = EOC
            off = (data_start + next_cluster - 2) * SECTOR
            image[off:off + len(value)] = value
            file_cluster[(d, name11)] = next_cluster
            next_cluster += n

    for d in order:
        if d:
            parent = d.rpartition("/")[0]
            entries = [
                _dirent(b".          ", ATTR_DIRECTORY, dir_cluster[d], 0),
                _dirent(b"..         ", ATTR_DIRECTORY,
                        dir_cluster[parent] if parent else 0, 0),
            ]
        else:
            entries = [_dirent(label11, ATTR_VOLUME_ID, 0, 0)]
        for name11, (kind, value) in sorted(dirs[d].items()):
            if kind == "dir":
                entries.append(_dirent(name11, ATTR_DIRECTORY,
                                       dir_cluster[value], 0))
            else:
                entries.append(_dirent(name11, ATTR_ARCHIVE,
                                       file_cluster[(d, name11)], len(value)))
        if len(entries) > ENTRIES_PER_DIR:
            raise FatError("directory %r needs more than one cluster"
                           % (d or "/"))
        off = (data_start + dir_cluster[d] - 2) * SECTOR
        image[off:off + DIRENT * len(entries)] = b"".join(entries)

    fat_bytes = struct.pack("<%dI" % len(fat), *fat)
    for i in range(NUM_FATS):
        off = (RESERVED + i * fatsz) * SECTOR
        image[off:off + len(fat_bytes)] = fat_bytes

    boot = bytearray(SECTOR)
    boot[0:3] = b"\xeb\x58\x90"
    boot[3:11] = b"RHAPSODI"
    struct.pack_into("<HBHBHHBHHHII", boot, 11, SECTOR, 1, RESERVED,
                     NUM_FATS, 0, 0, 0xF8, 0, 63, 255, hidden_sectors,
                     total_sectors)
    struct.pack_into("<IHHIHH", boot, 36, fatsz, 0, 0, ROOT_CLUSTER, 1, 6)
    boot[64] = 0x80
    boot[66] = 0x29
    struct.pack_into("<I", boot, 67, VOLUME_ID)
    boot[71:82] = label11
    boot[82:90] = b"FAT32   "
    boot[510:512] = b"\x55\xaa"

    fsinfo = bytearray(SECTOR)
    struct.pack_into("<I", fsinfo, 0, 0x41615252)
    struct.pack_into("<III", fsinfo, 484, 0x61417272,
                     clusters + 2 - next_cluster, next_cluster)
    struct.pack_into("<I", fsinfo, 508, 0xAA550000)

    for sector, block in ((0, boot), (1, fsinfo), (6, boot), (7, fsinfo)):
        image[sector * SECTOR:(sector + 1) * SECTOR] = block
    return bytes(image)


def _layout(image):
    bps, spc, rsvd, nfats = struct.unpack_from("<HBHB", image, 11)
    fatsz, = struct.unpack_from("<I", image, 36)
    root, = struct.unpack_from("<I", image, 44)
    if bps != SECTOR or spc != 1 or image[82:90] != b"FAT32   ":
        raise FatError("not a volume this module writes")
    return rsvd, rsvd + nfats * fatsz, root


def _chain(image, rsvd, first):
    clusters = []
    c = first
    while 2 <= c < 0x0FFFFFF8:
        clusters.append(c)
        c = struct.unpack_from("<I", image, rsvd * SECTOR + 4 * c)[0] & EOC
    return clusters


def read_file(image, path):
    """The contents of path in a volume build() produced."""
    rsvd, data_start, cluster = _layout(image)
    parts = path.split("/")
    for i, comp in enumerate(parts):
        want = short_name(comp)
        raw = b"".join(
            image[(data_start + c - 2) * SECTOR:(data_start + c - 1) * SECTOR]
            for c in _chain(image, rsvd, cluster))
        for off in range(0, len(raw), DIRENT):
            e = raw[off:off + DIRENT]
            if e[0] == 0:
                break
            if e[0:11] == want:
                break
        else:
            e = b"\0"
        if e[0] == 0:
            raise FatError("%s: no such file or directory" % path)
        is_dir = bool(e[11] & ATTR_DIRECTORY)
        first = (struct.unpack_from("<H", e, 20)[0] << 16
                 | struct.unpack_from("<H", e, 26)[0])
        if i < len(parts) - 1:
            if not is_dir:
                raise FatError("%s: %s is not a directory" % (path, comp))
            cluster = first
        else:
            if is_dir:
                raise FatError("%s is a directory" % path)
            size, = struct.unpack_from("<I", e, 28)
            data = b"".join(
                image[(data_start + c - 2) * SECTOR:
                      (data_start + c - 1) * SECTOR]
                for c in _chain(image, rsvd, first))
            return data[:size]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd vm && python -m unittest test_fat32 -v`
Expected: 15 tests, all `ok`.

- [ ] **Step 5: Commit**

```bash
git add vm/fat32.py vm/test_fat32.py
git commit -m "vm: write and read FAT32 ESP volumes in pure Python"
```

---

### Task 2: Build the ESP with `fat32` instead of mtools

**Files:**
- Modify: `vm/build_uefi_image.py` (whole file shown)
- Test: `vm/test_build_uefi_image.py` (whole file shown)

**Interfaces:**
- Consumes: `fat32.build`, `fat32.read_file` (Task 1).
- Produces: `build_uefi_image._esp_image(efi_app: str, esp_sectors: int) -> bytes`
  and `build_uefi_image.ESP_BOOT_PATH = "EFI/BOOT/BOOTIA32.EFI"`. The public
  `build()` and `build_esp()` signatures don't change in this task.

- [ ] **Step 1: Rewrite the tests without mtools**

Replace `vm/test_build_uefi_image.py` with:

```python
import os
import shutil
import struct
import tempfile
import unittest

import build_uefi_image
import fat32

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
EFI_APP = b"MZ" + b"\0" * 1022


def _part(mbr, n):
    """Unpack MBR partition entry n as (systid, lba_start, nsectors)."""
    off = MBR_PART_OFFSET + n * 16
    entry = mbr[off:off + 16]
    systid = entry[4]
    lba, count = struct.unpack("<II", entry[8:16])
    return systid, lba, count


def _esp_volume(path, lba, count):
    with open(path, "rb") as f:
        f.seek(lba * SECTOR)
        return f.read(count * SECTOR)


class TestBuildUefiImage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.rhapsody = os.path.join(self.tmp, "rhapsody.img")
        with open(self.rhapsody, "wb") as f:
            f.write(b"RHAP" * (4 * 1024 * 1024 // 4))
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(EFI_APP)
        self.out = os.path.join(self.tmp, "hybrid.img")

    def test_mbr_has_esp_and_rhapsody_partitions(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(mbr[510:512], b"\x55\xaa")
        self.assertEqual(_part(mbr, 0)[0], EFI_SYSTEM)
        self.assertEqual(_part(mbr, 1)[0], FDISK_NEXTNAME)

    def test_esp_contains_the_efi_app_at_the_removable_media_path(self):
        build_uefi_image.build(self.rhapsody, self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        _, lba, count = _part(mbr, 0)
        esp = _esp_volume(self.out, lba, count)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"), EFI_APP)

    def test_missing_rhapsody_image_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(os.path.join(self.tmp, "nope.img"),
                                   self.efi, self.out, esp_mb=64)


class TestBuildEspOnly(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-esp-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        with open(self.efi, "wb") as f:
            f.write(EFI_APP)
        self.out = os.path.join(self.tmp, "esp.img")

    def test_partition_1_is_esp_at_lba_2048(self):
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(mbr[510:512], b"\x55\xaa")
        self.assertEqual(_part(mbr, 0),
                         (EFI_SYSTEM, 2048, 64 * 1024 * 1024 // SECTOR))

    def test_no_second_partition(self):
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        self.assertEqual(_part(mbr, 1), (0, 0, 0))

    def test_efi_app_present_at_boot_path(self):
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            mbr = f.read(SECTOR)
        _, lba, count = _part(mbr, 0)
        esp = _esp_volume(self.out, lba, count)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"), EFI_APP)

    def test_missing_efi_app_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build_esp(os.path.join(self.tmp, "nope.efi"),
                                       self.out, esp_mb=64)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd vm && python -m unittest test_build_uefi_image -v`
Expected: the builds raise
`RuntimeError: missing mtools binaries: mformat, mmd, mcopy`, so the ESP and
MBR tests ERROR. The two "missing file" tests pass.

- [ ] **Step 3: Switch `build_uefi_image.py` to `fat32`**

Replace `vm/build_uefi_image.py` with:

```python
"""Build a hybrid MBR disk: a FAT32 EFI System Partition holding the UEFI
loader, followed by an existing Rhapsody partition copied verbatim.

MBR rather than GPT, so read_label() in boot-2's disk.c keeps finding the
Rhapsody partition by its 0xA7 system id.
"""

import os
import shutil
import struct
import sys

import fat32

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
ESP_LBA = 2048  # 1 MB in, the conventional alignment
CHS_OUT_OF_RANGE = b"\xfe\xff\xff"
ESP_BOOT_PATH = "EFI/BOOT/BOOTIA32.EFI"


def _part_entry(systid, lba_start, nsectors):
    return (b"\x00" + CHS_OUT_OF_RANGE + bytes([systid]) + CHS_OUT_OF_RANGE
            + struct.pack("<II", lba_start, nsectors))


def _esp_image(efi_app, esp_sectors):
    """A FAT32 volume of esp_sectors holding the EFI app at the removable-
    media path OVMF boots from."""
    with open(efi_app, "rb") as f:
        app = f.read()
    return fat32.build(esp_sectors, {ESP_BOOT_PATH: app}, label="RHAPEFI",
                       hidden_sectors=ESP_LBA)


def build(rhapsody_image, efi_app, out_path, esp_mb=64):
    """Write a hybrid MBR disk to out_path."""
    for path in (rhapsody_image, efi_app):
        if not os.path.exists(path):
            raise RuntimeError("no such file: %s" % path)

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    rhapsody_bytes = os.path.getsize(rhapsody_image)
    if rhapsody_bytes % SECTOR:
        raise RuntimeError("%s is not a whole number of %d-byte sectors"
                           % (rhapsody_image, SECTOR))
    rhapsody_sectors = rhapsody_bytes // SECTOR
    rhapsody_lba = ESP_LBA + esp_sectors
    total_sectors = rhapsody_lba + rhapsody_sectors

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        entries = (_part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors)
                   + _part_entry(FDISK_NEXTNAME, rhapsody_lba,
                                 rhapsody_sectors))
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(ESP_LBA * SECTOR)
        out.write(_esp_image(efi_app, esp_sectors))

        out.seek(rhapsody_lba * SECTOR)
        with open(rhapsody_image, "rb") as src:
            shutil.copyfileobj(src, out, length=1024 * 1024)


def build_esp(efi_app, out_path, esp_mb=64):
    """Write an ESP-only MBR disk to out_path: a single 0xEF/FAT32 partition
    at ESP_LBA containing the EFI app, no second partition.

    This is disk 1 in the two-disk layout: boot-2's read_label() applies
    part_offset asymmetrically (added when reading label-relative sectors,
    omitted from the label's own p_base), so a Rhapsody filesystem embedded
    at a nonzero LBA reads short. Keeping the Rhapsody filesystem on its own
    whole-disk image (part_offset == 0) avoids the bug; this disk exists only
    to give OVMF something to boot the loader from.
    """
    if not os.path.exists(efi_app):
        raise RuntimeError("no such file: %s" % efi_app)

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    total_sectors = ESP_LBA + esp_sectors

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        entries = _part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors)
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(ESP_LBA * SECTOR)
        out.write(_esp_image(efi_app, esp_sectors))


def main(argv):
    # A 16 MiB FAT32 volume has too few clusters to be structurally valid;
    # EDK2's FAT driver silently declines to mount it (no error, it just
    # never binds), and BDS reports "unable to boot". 64 MiB is comfortably
    # above the FAT32 minimum. (Task 3 finding.)
    if len(argv) >= 2 and argv[1] == "--esp-only":
        rest = argv[2:]
        if len(rest) not in (2, 3):
            sys.stderr.write(
                "usage: %s --esp-only EFI_APP OUT_PATH [ESP_MB]\n" % argv[0])
            return 2
        esp_mb = int(rest[2]) if len(rest) == 3 else 64
        build_esp(rest[0], rest[1], esp_mb=esp_mb)
        return 0

    if len(argv) not in (4, 5):
        sys.stderr.write(
            "usage: %s RHAPSODY_IMAGE EFI_APP OUT_PATH [ESP_MB]\n"
            "       %s --esp-only EFI_APP OUT_PATH [ESP_MB]\n"
            % (argv[0], argv[0]))
        return 2
    esp_mb = int(argv[4]) if len(argv) == 5 else 64
    build(argv[1], argv[2], argv[3], esp_mb=esp_mb)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd vm && python -m unittest test_build_uefi_image test_fat32 -v`
Expected: all `ok`, none skipped.

- [ ] **Step 5: Commit**

```bash
git add vm/build_uefi_image.py vm/test_build_uefi_image.py
git commit -m "vm: build the ESP with fat32.py so UEFI images need no mtools"
```

---

### Task 3: A hybrid disk that actually boots, and a reader that finds it

**Files:**
- Modify: `vm/rhap_image.py:15-60` (the `_read_label` search)
- Modify: `vm/build_uefi_image.py` (whole file shown)
- Test: `vm/test_build_uefi_image.py` (whole file shown)

**Interfaces:**
- Consumes: `fat32.build`, `fat32.read_file`; `ufs_build.label_checksum(label: bytes) -> int`,
  `ufs_build.LABEL_CHECKSUM = 0x22e`, `ufs_build.LABEL_SUM_SHORTS = 280`.
- Produces:
  - `build_uefi_image.build(rhapsody_image, efi_app, out_path, esp_mb=64, boot0=None)`
  - `build_uefi_image.lba_assist_geometry(total_sectors: int) -> (heads, spt)`
  - `build_uefi_image.chs(lba: int, heads: int, spt: int) -> bytes` (3 bytes)
  - `build_uefi_image.rebase_labels(head: bytearray, relsect: int) -> int` (the number of copies rebased)
  - `rhap_image.Image` opens a disk whose first `0xA7` fdisk partition holds the
    label. Phase 4's `hdimage.py` reuses the MBR and CHS helpers and the rebase
    rules.

The background, from the spec's *Labels on fdisk disks*: inside a `0xA7`
partition the label holds absolute addresses. `check_label` also requires
`dl_label_blkno` to equal the physical block each copy is read from. So
rebasing a whole-disk image into a partition at LBA `relsect` means:
- `dl_label_blkno` becomes `relsect + s` for the copy at sector `s`
- `p_base` and `d_boot0_blkno[]` grow by `relsect / (secsize / 512)`
- each copy's checksum is recomputed

The `d_front` field stays as it is.

- [ ] **Step 1: Write the failing tests**

Replace `vm/test_build_uefi_image.py` with:

```python
import os
import shutil
import struct
import tempfile
import unittest

import build_uefi_image
import fat32
import rhap_image
import ufs_build

HERE = os.path.dirname(os.path.abspath(__file__))
FLOPPY = os.environ.get(
    "RHAPSODY_FLOPPY",
    os.path.join(HERE, "install", "rhapsody_dr2_x86_InstallationFloppy.img"))

SECTOR = 512
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
EFI_APP = b"MZ" + b"\0" * 1022
BOOT0 = b"\xfa\x33\xc0" + bytes(range(256)) + b"\x90" * 253
SOURCE_SECTORS = 4 * 1024 * 1024 // SECTOR
ESP_SECTORS = 64 * 1024 * 1024 // SECTOR


def _part(mbr, n):
    """MBR entry n as (bootid, start_chs, systid, lba_start, nsectors)."""
    off = MBR_PART_OFFSET + n * 16
    e = mbr[off:off + 16]
    lba, count = struct.unpack("<II", e[8:16])
    return e[0], bytes(e[1:4]), e[4], lba, count


def _label(sector, secsize=1024, front=160):
    """A whole-disk NeXT label copy, two sectors long, as disk -i writes one
    on a disk with no fdisk table."""
    lab = bytearray(2 * SECTOR)
    lab[0:4] = b"dlV3"
    struct.pack_into(">i", lab, 4, sector)
    struct.pack_into(">i", lab, 92, secsize)
    struct.pack_into(">h", lab, 112, front)
    struct.pack_into(">ii", lab, 124, 32 * 1024 // secsize,
                     96 * 1024 // secsize)
    struct.pack_into(">ii", lab, 190, 0, 4096)
    for i in range(1, 8):
        struct.pack_into(">i", lab, 190 + 46 * i, -1)
    struct.pack_into(">H", lab, ufs_build.LABEL_CHECKSUM,
                     ufs_build.label_checksum(
                         lab[:ufs_build.LABEL_SUM_SHORTS * 2]))
    return lab


def _whole_disk(path, secsize=1024):
    """A 4 MB stand-in whole-disk image: boot1 in sector 0, label copies at
    sectors 15, 30 and 45, recognisable filler everywhere else."""
    image = bytearray(b"RHAP" * (SOURCE_SECTORS * SECTOR // 4))
    image[0:SECTOR] = b"BOOT1" + b"\0" * (SECTOR - 7) + b"\x55\xaa"
    for s in (15, 30, 45):
        image[s * SECTOR:(s + 2) * SECTOR] = _label(s, secsize)
    with open(path, "wb") as f:
        f.write(image)
    return bytes(image)


def _write(path, data):
    with open(path, "wb") as f:
        f.write(data)


class TestHybrid(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        cls.rhapsody = os.path.join(cls.tmp, "rhapsody.img")
        cls.source = _whole_disk(cls.rhapsody)
        cls.efi = os.path.join(cls.tmp, "BOOTIA32.EFI")
        _write(cls.efi, EFI_APP)
        cls.out = os.path.join(cls.tmp, "hybrid.img")
        build_uefi_image.build(cls.rhapsody, cls.efi, cls.out, esp_mb=64,
                               boot0=BOOT0)
        with open(cls.out, "rb") as f:
            cls.mbr = f.read(SECTOR)
        cls.lba = _part(cls.mbr, 1)[3]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def _partition(self, sector, count=1):
        with open(self.out, "rb") as f:
            f.seek((self.lba + sector) * SECTOR)
            return f.read(count * SECTOR)

    def test_mbr_carries_boot0_code_and_signature(self):
        self.assertEqual(self.mbr[:446], BOOT0[:446])
        self.assertEqual(self.mbr[510:512], b"\x55\xaa")

    def test_esp_is_first_and_inactive(self):
        bootid, _, systid, lba, count = _part(self.mbr, 0)
        self.assertEqual((bootid, systid, lba, count),
                         (0x00, EFI_SYSTEM, 2048, ESP_SECTORS))

    def test_rhapsody_partition_is_active_after_the_esp(self):
        bootid, _, systid, lba, count = _part(self.mbr, 1)
        self.assertEqual((bootid, systid, lba, count),
                         (0x80, FDISK_NEXTNAME, 2048 + ESP_SECTORS,
                          SOURCE_SECTORS))

    def test_start_chs_uses_lba_assisted_geometry(self):
        heads, spt = build_uefi_image.lba_assist_geometry(
            self.lba + SOURCE_SECTORS)
        self.assertEqual(_part(self.mbr, 1)[1],
                         build_uefi_image.chs(self.lba, heads, spt))

    def test_every_label_copy_is_rebased(self):
        delta = self.lba // 2                    # secsize 1024
        for s in (15, 30, 45):
            lab = self._partition(s, 2)
            self.assertEqual(struct.unpack_from(">i", lab, 4)[0],
                             self.lba + s)
            self.assertEqual(struct.unpack_from(">i", lab, 190)[0], delta)
            self.assertEqual(struct.unpack_from(">ii", lab, 124),
                             (32 + delta, 96 + delta))
            self.assertEqual(struct.unpack_from(">i", lab, 190 + 46)[0], -1)
            self.assertEqual(struct.unpack_from(">h", lab, 112)[0], 160)
            self.assertEqual(
                struct.unpack_from(">H", lab, ufs_build.LABEL_CHECKSUM)[0],
                ufs_build.label_checksum(
                    lab[:ufs_build.LABEL_SUM_SHORTS * 2]))

    def test_boot1_and_data_are_copied_verbatim(self):
        self.assertEqual(self._partition(0), self.source[:SECTOR])
        self.assertEqual(self._partition(100),
                         self.source[100 * SECTOR:101 * SECTOR])

    def test_esp_holds_the_loader(self):
        with open(self.out, "rb") as f:
            f.seek(2048 * SECTOR)
            esp = f.read(ESP_SECTORS * SECTOR)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"),
                         EFI_APP)


class TestBuildRefusals(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        _write(self.efi, EFI_APP)
        self.out = os.path.join(self.tmp, "hybrid.img")

    def test_missing_rhapsody_image_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(os.path.join(self.tmp, "nope.img"),
                                   self.efi, self.out, boot0=BOOT0)

    def test_unlabelled_source_raises(self):
        src = os.path.join(self.tmp, "plain.img")
        _write(src, b"RHAP" * (SOURCE_SECTORS * SECTOR // 4))
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(src, self.efi, self.out, boot0=BOOT0)

    def test_already_partitioned_source_raises(self):
        src = os.path.join(self.tmp, "parted.img")
        image = bytearray(_whole_disk(src))
        image[MBR_PART_OFFSET + 4] = FDISK_NEXTNAME
        _write(src, image)
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(src, self.efi, self.out, boot0=BOOT0)

    def test_source_without_readable_boot0_asks_for_the_option(self):
        src = os.path.join(self.tmp, "whole.img")
        _whole_disk(src)
        with self.assertRaises(RuntimeError):
            build_uefi_image.build(src, self.efi, self.out)

    def test_rebase_refuses_an_unrepresentable_offset(self):
        head = bytearray(64 * SECTOR)
        head[15 * SECTOR:17 * SECTOR] = _label(15, secsize=1024)
        with self.assertRaises(RuntimeError):
            build_uefi_image.rebase_labels(head, 133121)


class TestGeometry(unittest.TestCase):
    def test_large_disk_gets_255_heads(self):
        self.assertEqual(build_uefi_image.lba_assist_geometry(16910336),
                         (255, 63))

    def test_one_gigabyte_disk_gets_32_heads(self):
        self.assertEqual(build_uefi_image.lba_assist_geometry(2097152),
                         (32, 63))

    def test_small_disk_gets_16_heads(self):
        self.assertEqual(build_uefi_image.lba_assist_geometry(204800),
                         (16, 63))

    def test_chs_of_sector_zero(self):
        self.assertEqual(build_uefi_image.chs(0, 255, 63), b"\x00\x01\x00")

    def test_chs_of_the_hybrid_partition_start(self):
        # 133120 = cylinder 8 (8 * 16065 = 128520), head 73, sector 2
        self.assertEqual(build_uefi_image.chs(133120, 255, 63),
                         bytes([73, 2, 8]))

    def test_chs_past_cylinder_1023(self):
        self.assertEqual(build_uefi_image.chs(1024 * 255 * 63, 255, 63),
                         b"\xfe\xff\xff")


@unittest.skipUnless(os.path.exists(FLOPPY),
                     "set RHAPSODY_FLOPPY to the DR2 installation floppy")
class TestRealMedia(unittest.TestCase):
    def test_rhap_image_reads_a_file_back_out_of_the_partition(self):
        tmp = tempfile.mkdtemp(prefix="uefi-image-test-")
        self.addCleanup(shutil.rmtree, tmp)
        efi = os.path.join(tmp, "BOOTIA32.EFI")
        _write(efi, EFI_APP)
        out = os.path.join(tmp, "hybrid.img")
        build_uefi_image.build(FLOPPY, efi, out, esp_mb=64, boot0=BOOT0)
        with rhap_image.Image(FLOPPY) as img:
            want = img.read_file(img.resolve("/mach_kernel.rcz"))
        with rhap_image.Image(out) as img:
            got = img.read_file(img.resolve("/mach_kernel.rcz"))
            self.assertEqual(img.part_start,
                             (2048 + ESP_SECTORS) * SECTOR
                             + img.label["front"] * img.label["secsize"])
        self.assertEqual(got, want)


class TestBuildEspOnly(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uefi-esp-test-")
        self.addCleanup(shutil.rmtree, self.tmp)
        self.efi = os.path.join(self.tmp, "BOOTIA32.EFI")
        _write(self.efi, EFI_APP)
        self.out = os.path.join(self.tmp, "esp.img")
        build_uefi_image.build_esp(self.efi, self.out, esp_mb=64)
        with open(self.out, "rb") as f:
            self.mbr = f.read(SECTOR)

    def test_partition_1_is_esp_at_lba_2048(self):
        self.assertEqual(self.mbr[510:512], b"\x55\xaa")
        _, _, systid, lba, count = _part(self.mbr, 0)
        self.assertEqual((systid, lba, count), (EFI_SYSTEM, 2048, ESP_SECTORS))

    def test_no_second_partition(self):
        self.assertEqual(_part(self.mbr, 1), (0, b"\0\0\0", 0, 0, 0))

    def test_efi_app_present_at_boot_path(self):
        with open(self.out, "rb") as f:
            f.seek(2048 * SECTOR)
            esp = f.read(ESP_SECTORS * SECTOR)
        self.assertEqual(fat32.read_file(esp, "EFI/BOOT/BOOTIA32.EFI"),
                         EFI_APP)

    def test_missing_efi_app_raises(self):
        with self.assertRaises(RuntimeError):
            build_uefi_image.build_esp(os.path.join(self.tmp, "nope.efi"),
                                       self.out, esp_mb=64)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd vm && RHAPSODY_FLOPPY=D:/RhapsodiOS/vm/install/rhapsody_dr2_x86_InstallationFloppy.img python -m unittest test_build_uefi_image -v`
Expected: `TypeError: build() got an unexpected keyword argument 'boot0'` in
`TestHybrid.setUpClass` and the refusal tests, and `AttributeError` for
`lba_assist_geometry`, `chs` and `rebase_labels`.

- [ ] **Step 3: Teach `rhap_image` to find a label inside an fdisk partition**

In `vm/rhap_image.py`, add after `LABEL_MAGIC = b"dlV3"`:

```python
MBR_PART_OFFSET = 446
FDISK_NEXTNAME = 0xA7
```

Replace the `_read_label` method with:

```python
    def _fdisk_base(self):
        """Byte offset of the first 0xA7 fdisk partition, or 0 when sector 0
        has none (a whole-disk label, like golden.img's).

        Only the label's own location moves.  Inside an fdisk partition the
        label's p_base is already absolute -- disk -i -b adds the partition
        base when it writes it, and IODiskPartition uses it as-is -- so
        part_start needs no further offset."""
        mbr = self._read_at(0, 512)
        if len(mbr) < 512 or mbr[510:512] != b"\x55\xaa":
            return 0
        for n in range(4):
            entry = mbr[MBR_PART_OFFSET + 16 * n:MBR_PART_OFFSET + 16 * n + 16]
            if entry[4] == FDISK_NEXTNAME:
                return struct.unpack_from("<I", entry, 8)[0] * 512
        return 0

    def _read_label(self):
        base = self._fdisk_base()
        for off in LABEL_OFFSETS:
            buf = self._read_at(base + off, 1024)
            if buf[:4] == LABEL_MAGIC:
                self.label_offset = base + off
                return {
                    "blkno": struct.unpack_from(">i", buf, 4)[0],
                    "secsize": struct.unpack_from(">i", buf, 92)[0],
                    "front": struct.unpack_from(">h", buf, 112)[0],
                    "bootfile": _cstr(buf[132:156]),
                    "rootpartition": chr(buf[188]),
                    "p_base": struct.unpack_from(">i", buf, 190)[0],
                    "p_size": struct.unpack_from(">i", buf, 194)[0],
                }
        raise ValueError("no NeXT disk label found in %s" % self.path)
```

- [ ] **Step 4: Rewrite `build_uefi_image.py` for a bootable hybrid**

Replace `vm/build_uefi_image.py` with:

```python
"""Build MBR disks for the UEFI loader.

build() writes the single-disk layout: boot0 and the fdisk table, a FAT32
EFI System Partition holding the loader, then a whole-disk Rhapsody image as
the active 0xA7 partition.  build_esp() writes an ESP-only disk for the
older two-disk layout, where the Rhapsody image is attached whole as a
second disk.

MBR rather than GPT, because boot0, boot1, boot2 and the kernel all find
the Rhapsody partition by its 0xA7 system id.
"""

import os
import shutil
import struct
import sys

import fat32
import rhap_image
import ufs_build

SECTOR = 512
MBR_PART_OFFSET = 446
DISK_BOOTSZ = 446               # boot0's code, ahead of the fdisk table
FDISK_NEXTNAME = 0xA7
EFI_SYSTEM = 0xEF
ESP_LBA = 2048  # 1 MB in, the conventional alignment
ESP_BOOT_PATH = "EFI/BOOT/BOOTIA32.EFI"
BOOT0_PATH = "/usr/standalone/i386/boot0"
LABEL_MAGIC = b"dlV3"
LABEL_SCAN_SECTORS = 64         # the copies sit at sectors 15, 30 and 45
# Offsets into the big-endian, m68k-packed disk_label_t the kernel reads
# (src/kernel-7/bsd/dev/disk_label.h, bsd/sys/disktab.h).
DL_LABEL_BLKNO = 4
DL_SECSIZE = 92
DL_BOOT0_BLKNO = 124            # int[NBOOTS]
DL_PARTITIONS = 190             # partition_t[NPART], p_base first
PARTITION_SIZE = 46
NPART = 8
NBOOTS = 2


def lba_assist_geometry(total_sectors):
    """(heads, sectors per track) as SeaBIOS's TRANSLATION_LBA picks them
    (src/block.c): the LBA-assisted translation most BIOSes use above
    504 MB.  boot0 reads the active partition's boot sector by the CHS
    fields in its fdisk entry, so those fields must use this geometry."""
    spt = 63
    if total_sectors > 63 * 255 * 1024:
        return 255, spt
    heads = (total_sectors // spt) // 1024
    for limit, chosen in ((128, 255), (64, 128), (32, 64), (16, 32)):
        if heads > limit:
            return chosen, spt
    return 16, spt


def chs(lba, heads, spt):
    """The 3-byte CHS field for lba, or 1023/254/63 past cylinder 1023."""
    cyl = lba // (heads * spt)
    if cyl > 1023:
        return b"\xfe\xff\xff"
    head = (lba // spt) % heads
    sec = lba % spt + 1
    return bytes([head, ((cyl >> 2) & 0xC0) | sec, cyl & 0xFF])


def _part_entry(systid, lba_start, nsectors, geometry, active=False):
    heads, spt = geometry
    return (bytes([0x80 if active else 0x00]) + chs(lba_start, heads, spt)
            + bytes([systid]) + chs(lba_start + nsectors - 1, heads, spt)
            + struct.pack("<II", lba_start, nsectors))


def _esp_image(efi_app, esp_sectors):
    """A FAT32 volume of esp_sectors holding the EFI app at the removable-
    media path OVMF boots from."""
    with open(efi_app, "rb") as f:
        app = f.read()
    return fat32.build(esp_sectors, {ESP_BOOT_PATH: app}, label="RHAPEFI",
                       hidden_sectors=ESP_LBA)


def rebase_labels(head, relsect):
    """Rewrite every NeXT label copy in head, the first sectors of a
    whole-disk Rhapsody image, for a partition that starts at LBA relsect.
    Returns how many copies were rewritten.

    Inside an fdisk partition a label holds absolute addresses: disk -i -b
    adds the partition base to p_base and d_boot0_blkno
    (diskdev_cmds/disk.tproj/hd.c), boot1 loads boot2 from the absolute
    d_boot0_blkno, and IODiskPartition uses p_base as-is.  check_label also
    rejects a copy whose dl_label_blkno isn't the physical block it came
    from.  A whole-disk image has none of that, so copied verbatim into a
    partition it cannot boot or mount.
    """
    found = 0
    for sector in range(len(head) // SECTOR):
        off = sector * SECTOR
        if head[off:off + len(LABEL_MAGIC)] != LABEL_MAGIC:
            continue
        secsize = struct.unpack_from(">i", head, off + DL_SECSIZE)[0]
        if (secsize < SECTOR or secsize % SECTOR
                or relsect % (secsize // SECTOR)):
            raise RuntimeError(
                "label at sector %d has secsize %d, which cannot express a "
                "partition at LBA %d" % (sector, secsize, relsect))
        delta = relsect // (secsize // SECTOR)
        struct.pack_into(">i", head, off + DL_LABEL_BLKNO, relsect + sector)
        for i in range(NBOOTS):
            field = off + DL_BOOT0_BLKNO + 4 * i
            blkno = struct.unpack_from(">i", head, field)[0]
            if blkno >= 0:
                struct.pack_into(">i", head, field, blkno + delta)
        for i in range(NPART):
            field = off + DL_PARTITIONS + PARTITION_SIZE * i
            base = struct.unpack_from(">i", head, field)[0]
            if base >= 0:
                struct.pack_into(">i", head, field, base + delta)
        struct.pack_into(
            ">H", head, off + ufs_build.LABEL_CHECKSUM,
            ufs_build.label_checksum(
                head[off:off + ufs_build.LABEL_SUM_SHORTS * 2]))
        found += 1
    if not found:
        raise RuntimeError("no NeXT disk label in the first %d sectors"
                           % (len(head) // SECTOR))
    return found


def _require_whole_disk(head, path):
    if head[510:512] != b"\x55\xaa":
        return
    for n in range(4):
        if head[MBR_PART_OFFSET + 16 * n + 4] == FDISK_NEXTNAME:
            raise RuntimeError("%s already has an fdisk table with a 0xA7 "
                               "partition; build() needs a whole-disk image"
                               % path)


def _boot0_from(image_path):
    # Raise after the except clause, not inside it: a chained traceback
    # would keep the half-built Image's open file alive, and Windows then
    # refuses to delete the image.
    try:
        with rhap_image.Image(image_path) as img:
            ino = img.resolve(BOOT0_PATH)
            if ino is not None:
                return img.read_file(ino)
            problem = "it has no %s" % BOOT0_PATH
    except (ValueError, struct.error, IndexError) as e:
        problem = str(e)
    raise RuntimeError("cannot read boot0 from %s (%s); pass --boot0"
                       % (image_path, problem))


def build(rhapsody_image, efi_app, out_path, esp_mb=64, boot0=None):
    """Write the single-disk layout to out_path.

    rhapsody_image must be a whole-disk image (no 0xA7 fdisk entry of its
    own).  boot0 is the MBR code; by default it is read from the image's
    own /usr/standalone/i386/boot0."""
    for path in (rhapsody_image, efi_app):
        if not os.path.exists(path):
            raise RuntimeError("no such file: %s" % path)
    rhapsody_bytes = os.path.getsize(rhapsody_image)
    if rhapsody_bytes % SECTOR:
        raise RuntimeError("%s is not a whole number of %d-byte sectors"
                           % (rhapsody_image, SECTOR))
    with open(rhapsody_image, "rb") as src:
        head = bytearray(src.read(LABEL_SCAN_SECTORS * SECTOR))
    _require_whole_disk(head, rhapsody_image)

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    rhapsody_sectors = rhapsody_bytes // SECTOR
    rhapsody_lba = ESP_LBA + esp_sectors
    total_sectors = rhapsody_lba + rhapsody_sectors
    geometry = lba_assist_geometry(total_sectors)
    rebase_labels(head, rhapsody_lba)
    if boot0 is None:
        boot0 = _boot0_from(rhapsody_image)
    if len(boot0) < DISK_BOOTSZ:
        raise RuntimeError("boot0 is %d bytes; need at least %d"
                           % (len(boot0), DISK_BOOTSZ))

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        mbr[:DISK_BOOTSZ] = boot0[:DISK_BOOTSZ]
        entries = (_part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors, geometry)
                   + _part_entry(FDISK_NEXTNAME, rhapsody_lba,
                                 rhapsody_sectors, geometry, active=True))
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(ESP_LBA * SECTOR)
        out.write(_esp_image(efi_app, esp_sectors))

        out.seek(rhapsody_lba * SECTOR)
        out.write(head)
        with open(rhapsody_image, "rb") as src:
            src.seek(len(head))
            shutil.copyfileobj(src, out, length=1024 * 1024)


def build_esp(efi_app, out_path, esp_mb=64):
    """Write an ESP-only MBR disk to out_path: a single 0xEF/FAT32 partition
    at ESP_LBA containing the EFI app, no second partition.

    This is the loader's disk in the two-disk layout, where the Rhapsody
    image is attached whole as the other disk; the loader falls back to the
    first labelled disk when the disk it was read from has no label.
    """
    if not os.path.exists(efi_app):
        raise RuntimeError("no such file: %s" % efi_app)

    esp_sectors = esp_mb * 1024 * 1024 // SECTOR
    total_sectors = ESP_LBA + esp_sectors
    geometry = lba_assist_geometry(total_sectors)

    with open(out_path, "wb") as out:
        out.truncate(total_sectors * SECTOR)

        mbr = bytearray(SECTOR)
        entries = _part_entry(EFI_SYSTEM, ESP_LBA, esp_sectors, geometry)
        mbr[MBR_PART_OFFSET:MBR_PART_OFFSET + len(entries)] = entries
        mbr[510:512] = b"\x55\xaa"
        out.seek(0)
        out.write(mbr)

        out.seek(ESP_LBA * SECTOR)
        out.write(_esp_image(efi_app, esp_sectors))


def main(argv):
    # A 16 MiB FAT32 volume has too few clusters to be structurally valid;
    # EDK2's FAT driver silently declines to mount it (no error, it just
    # never binds), and BDS reports "unable to boot". 64 MiB is comfortably
    # above the FAT32 minimum. (Task 3 finding.)
    argv = list(argv)
    boot0 = None
    if "--boot0" in argv:
        i = argv.index("--boot0")
        with open(argv[i + 1], "rb") as f:
            boot0 = f.read()
        del argv[i:i + 2]

    if len(argv) >= 2 and argv[1] == "--esp-only":
        rest = argv[2:]
        if len(rest) not in (2, 3):
            sys.stderr.write(
                "usage: %s --esp-only EFI_APP OUT_PATH [ESP_MB]\n" % argv[0])
            return 2
        esp_mb = int(rest[2]) if len(rest) == 3 else 64
        build_esp(rest[0], rest[1], esp_mb=esp_mb)
        return 0

    if len(argv) not in (4, 5):
        sys.stderr.write(
            "usage: %s [--boot0 FILE] RHAPSODY_IMAGE EFI_APP OUT_PATH [ESP_MB]\n"
            "       %s --esp-only EFI_APP OUT_PATH [ESP_MB]\n"
            % (argv[0], argv[0]))
        return 2
    esp_mb = int(argv[4]) if len(argv) == 5 else 64
    build(argv[1], argv[2], argv[3], esp_mb=esp_mb, boot0=boot0)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd vm && RHAPSODY_FLOPPY=D:/RhapsodiOS/vm/install/rhapsody_dr2_x86_InstallationFloppy.img python -m unittest test_build_uefi_image test_fat32 test_rhap_image -v`
Expected: all `ok`, with `TestRealMedia` **not** skipped. If it says skipped,
the floppy path is wrong. `test_rhap_image` skips in the worktree, which has no
`golden.img`, so also confirm that a whole-disk image still opens, read-only,
through the new reader:

```bash
python - <<'EOF'
import sys
sys.path.insert(0, "vm")
import rhap_image
with rhap_image.Image("D:/RhapsodiOS/vm/golden.img") as img:
    k = img.read_file(img.resolve("/mach_kernel"))
    print(img.part_start, img.label_offset, len(k))
EOF
```
Expected: `163840 7680 1459520`.

- [ ] **Step 6: Commit**

```bash
git add vm/rhap_image.py vm/build_uefi_image.py vm/test_build_uefi_image.py
git commit -m "vm: rebase the copied label and write boot0 and CHS so the hybrid disk can boot"
```

---

### Task 4: Build `bootefi` on this Windows host

**Files:**
- Modify: `src/bootefi-1/Makefile`

**Interfaces:**
- Produces: `src/bootefi-1/BUILD/BOOTIA32.EFI`, built by
  `make -C src/bootefi-1` with LLVM on `PATH`. Tasks 5 and 8 boot it.

With `core.symlinks=false`, `vendor_includes/architecture` and
`vendor_includes/driverkit` are checked out as small text files containing
`../../architecture-1` and `../../driverkit-3/driverkit`, so
`<architecture/byte_order.h>` can't be found.

- [ ] **Step 1: See the build fail**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1 2>&1 | grep -m1 -E "error|Error"
```
Expected: a `fatal error: 'architecture/...' file not found` (or a
`driverkit/...` equivalent) from the first object that includes one.

- [ ] **Step 2: Stage the linked directories when the links are not real**

In `src/bootefi-1/Makefile`, directly after the `SYS_CFLAGS := $(CFLAGS) -D__LITTLE_ENDIAN__=0` line, add:

```make
# vendor_includes/architecture and vendor_includes/driverkit are symlinks.
# A checkout without symlink support (Windows with core.symlinks=false) turns
# them into small text files naming their targets, so copy the real
# directories under BUILD/ and search there as well.  A real symlink makes
# the wildcard match and none of this applies.
VENDOR_STAGE := $(BUILD)/vendor_includes
ifeq ($(wildcard vendor_includes/architecture/.),)
CFLAGS     += -I$(VENDOR_STAGE)
SYS_CFLAGS += -I$(VENDOR_STAGE)
STAGED_VENDOR := $(VENDOR_STAGE)/architecture $(VENDOR_STAGE)/driverkit
endif
```

Change the three object rules to depend on the staged copies (order-only):

```make
$(BUILD)/sys.obj: $(BOOT2)/libsaio/sys.c | $(BUILD) $(STAGED_VENDOR)
	$(CC) $(SYS_CFLAGS) -c -o $@ $<

$(BUILD)/%.obj: %.c | $(BUILD) $(STAGED_VENDOR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILD)/handoff_tramp.obj: handoff.S | $(BUILD) $(STAGED_VENDOR)
	$(CC) $(CFLAGS) -c -o $@ handoff.S
```

and add the staging rules after the `$(BUILD):` rule:

```make
$(VENDOR_STAGE)/architecture: | $(BUILD)
	mkdir -p $(VENDOR_STAGE)
	cp -R ../architecture-1 $@

$(VENDOR_STAGE)/driverkit: | $(BUILD)
	mkdir -p $(VENDOR_STAGE)
	cp -R ../driverkit-3/driverkit $@
```

- [ ] **Step 3: Build**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1 2>&1 | tail -5
```
Expected: the last line is the `lld-link ... /out:BUILD/BOOTIA32.EFI ...`
command, with no `error:` lines.

If LLVM 22 rejects code that the Mac's clang 15 accepted, the only allowed
remedy is compiler flags; **do not edit `src/boot-2`**. If the errors are
`-Wincompatible-function-pointer-types`, `-Wint-conversion` or
`-Wincompatible-pointer-types`, append this to the `CFLAGS :=` definition and
rebuild:

```make
          -Wno-error=incompatible-function-pointer-types \
          -Wno-error=int-conversion -Wno-error=incompatible-pointer-types \
```

These are warnings that newer clang promotes to errors by default. Any other
error: stop and report it with the full diagnostic.

- [ ] **Step 4: Check the output is an IA32 EFI application**

Run:
```bash
python - <<'EOF'
import struct
d = open("src/bootefi-1/BUILD/BOOTIA32.EFI", "rb").read()
pe = struct.unpack_from("<I", d, 0x3c)[0]
assert d[:2] == b"MZ" and d[pe:pe + 4] == b"PE\0\0", "not a PE image"
machine = struct.unpack_from("<H", d, pe + 4)[0]
subsystem = struct.unpack_from("<H", d, pe + 24 + 68)[0]
print("machine %#x subsystem %d size %d" % (machine, subsystem, len(d)))
assert machine == 0x14c and subsystem == 10
EOF
```
Expected: `machine 0x14c subsystem 10 size ...` (i386, EFI application).

- [ ] **Step 5: Check the existing host test builds here too**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1/tests test-acpi 2>&1 | tail -3
```
Expected: `ok` lines and no `FAIL`. This proves pure-C host tests build and
run on this host, which Tasks 6 and 7 depend on.

- [ ] **Step 6: Commit**

```bash
git add src/bootefi-1/Makefile
git commit -m "bootefi: stage the linked include directories so the loader builds on Windows checkouts"
```

(Include the `CFLAGS` addition from Step 3 in this commit if it was needed.)

---

### Task 5: QEMU runner, root-mount check, and the baseline boots

**Files:**
- Create: `vm/qemu_boot.py`, `vm/test_qemu_boot.py`
- Create: `vm/check_rootmount.py`, `vm/test_check_rootmount.py`

**Interfaces:**
- Consumes: `qemu-shot.py`'s `QMP`, `parse_ppm`, `write_png`,
  `find_free_port`, `fmt_seconds`, `RTC_BASE` (loaded with `importlib`,
  because the filename has a dash); `BUILD/BOOTIA32.EFI` (Task 4);
  `build_uefi_image.build_esp` (Task 3).
- Produces:
  - `python vm/qemu_boot.py {bios,uefi} IMAGE OUTDIR [--esp ESP] [--at 60,120,...] [--firmware-dir DIR]`,
    which writes `OUTDIR/console.log`, `OUTDIR/kernel.log` and `OUTDIR/shot-<N>s.png`
  - `qemu_boot.build_args(mode, image, outdir, qmp_port, firmware_dir, esp=None, qemu="qemu-system-i386") -> list`
  - `qemu_boot.refuse_masters(path)`
  - `python vm/check_rootmount.py KERNEL_LOG`, which exits 0 on root-mount
    evidence and prints what's missing otherwise
  - `check_rootmount.problems(text: str) -> list[str]`

- [ ] **Step 1: Write the failing tests**

Create `vm/test_check_rootmount.py`:

```python
import unittest

import check_rootmount

GOOD = "hc0: drive 0\nrootdev 300, howto 40000\nsomething later\n"


class TestProblems(unittest.TestCase):
    def test_clean_log_has_no_problems(self):
        self.assertEqual(check_rootmount.problems(GOOD), [])

    def test_missing_rootdev_line_is_a_problem(self):
        self.assertEqual(check_rootmount.problems("hc0: drive 0\n"),
                         ["no 'rootdev 300' line"])

    def test_wrong_root_device_is_a_problem(self):
        self.assertEqual(check_rootmount.problems("rootdev 600, howto 0\n"),
                         ["no 'rootdev 300' line"])

    def test_each_failure_marker_is_reported(self):
        for marker in ("cannot mount root, errno = 5", "panic: oops",
                       "root device? ", "Label in wrong location"):
            found = check_rootmount.problems(GOOD + marker + "\n")
            self.assertEqual(len(found), 1, marker)


if __name__ == "__main__":
    unittest.main()
```

Create `vm/test_qemu_boot.py`:

```python
import os
import tempfile
import unittest
import unittest.mock as mock

import qemu_boot


class TestBuildArgs(unittest.TestCase):
    def test_bios_boots_seabios_without_pflash(self):
        args = qemu_boot.build_args("bios", "D:/w/disk.img", "D:/out", 4444,
                                    "D:/fw")
        joined = " ".join(args)
        self.assertNotIn("if=pflash", joined)
        self.assertIn("-snapshot", args)
        self.assertIn("file=D:/w/disk.img,format=raw,if=ide,index=0,media=disk",
                      args)
        self.assertIn("file:%s" % os.path.join("D:/out", "console.log"), args)
        self.assertIn("file:%s" % os.path.join("D:/out", "kernel.log"), args)

    def test_uefi_boots_edk2_i386_with_its_vars_copy_in_outdir(self):
        joined = " ".join(qemu_boot.build_args("uefi", "D:/w/disk.img",
                                               "D:/out", 4444, "D:/fw"))
        self.assertIn("readonly=on,file=%s"
                      % os.path.join("D:/fw", "edk2-i386-code.fd"), joined)
        self.assertIn("unit=1,file=%s"
                      % os.path.join("D:/out", "edk2-i386-vars.fd"), joined)
        self.assertIn("-cpu Nehalem", joined)
        self.assertIn("PIIX4_PM.disable_s3=1", joined)
        self.assertIn("-m 256", joined)

    def test_esp_adds_a_virtio_disk(self):
        args = qemu_boot.build_args("bios", "a.img", "o", 1, "fw",
                                    esp="esp.img")
        self.assertIn("id=esp,file=esp.img,format=raw,if=none", args)
        self.assertIn("virtio-blk-pci,drive=esp", args)

    def test_unknown_mode_raises(self):
        with self.assertRaises(ValueError):
            qemu_boot.build_args("efi", "a.img", "o", 1, "fw")


class TestSafety(unittest.TestCase):
    def test_golden_image_is_refused(self):
        golden = os.path.join(qemu_boot._HERE, "golden.img")
        if not os.path.exists(golden):
            self.skipTest("no vm/golden.img in this checkout")
        with self.assertRaises(SystemExit):
            qemu_boot.refuse_masters(golden)

    def test_other_images_are_allowed(self):
        fd, path = tempfile.mkstemp()
        os.close(fd)
        try:
            qemu_boot.refuse_masters(path)
        finally:
            os.unlink(path)

    def test_default_firmware_dir_is_qemus_share_directory(self):
        with mock.patch("shutil.which",
                        return_value="C:/q/qemu-system-i386.exe"), \
             mock.patch("os.path.realpath", side_effect=lambda p: p):
            self.assertEqual(
                qemu_boot.default_firmware_dir("qemu-system-i386"),
                os.path.join("C:/q", "share"))


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd vm && python -m unittest test_check_rootmount test_qemu_boot -v`
Expected: `ModuleNotFoundError` for both modules.

- [ ] **Step 3: Write `check_rootmount.py`**

```python
"""Judge a kernel serial log (COM2) for evidence the root filesystem
mounted on hd0a.

    python vm/check_rootmount.py KERNEL_LOG

setconf() prints "rootdev 300, howto ..." once it has chosen hd0a
(machdep/i386/swapgeneric.m); the failure lines are the kernel's own
(bsd/kern/init_main.c, subr_prf.c, swapgeneric.m) and check_label's
(driverkit-3/libDriver/label_subr.c).  A clean log is necessary, not
sufficient: pair it with a screenshot showing userland.
"""
import re
import sys

FAILURES = ("cannot mount root", "panic", "root device?",
            "Label in wrong location")


def problems(text):
    found = []
    if not re.search(r"^rootdev 300\b", text, re.MULTILINE):
        found.append("no 'rootdev 300' line")
    for marker in FAILURES:
        if marker in text:
            found.append("found %r" % marker)
    return found


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: %s KERNEL_LOG\n" % argv[0])
        return 2
    with open(argv[1], "rb") as f:
        text = f.read().decode("latin-1")
    found = problems(text)
    for line in found:
        print(line)
    if not found:
        print("root mount evidence OK")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

- [ ] **Step 4: Write `qemu_boot.py`**

```python
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
vm/golden.img and vm/rhapsody.vmdk are refused outright.  QEMU gets native
paths straight from Python: Git Bash does not rewrite `-serial file:/d/...`
for native programs, which is why this is not a shell script.  Standard
library only.
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
    """Exit if path is one of the read-only master images."""
    for name in _MASTERS:
        master = os.path.join(_HERE, name)
        if (os.path.exists(master) and os.path.exists(path)
                and os.path.samefile(path, master)):
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
    proc = subprocess.Popen(
        build_args(mode, image, outdir, port, firmware_dir, esp=esp),
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    start = time.monotonic()
    qmp = None
    try:
        try:
            qmp = qemu_shot.QMP("127.0.0.1", port)
        except RuntimeError:
            if proc.poll() is not None:
                raise SystemExit("QEMU exited: %s"
                                 % proc.stderr.read().decode(errors="replace"))
            raise
        for t in sorted(at_points):
            remaining = t - (time.monotonic() - start)
            if remaining > 0:
                time.sleep(remaining)
            ppm = os.path.join(outdir, "_shot.ppm")
            qmp.execute("screendump", filename=ppm)
            with open(ppm, "rb") as f:
                w, h, _, pixels = qemu_shot.parse_ppm(f.read())
            os.remove(ppm)
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
    print("console: %s" % os.path.join(outdir, "console.log"))
    print("kernel:  %s" % os.path.join(outdir, "kernel.log"))


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
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd vm && python -m unittest test_check_rootmount test_qemu_boot -v`
Expected: all `ok`. `test_golden_image_is_refused` skips in the worktree, which
has no `golden.img`.

- [ ] **Step 6: Commit the tools**

```bash
git add vm/qemu_boot.py vm/test_qemu_boot.py vm/check_rootmount.py vm/test_check_rootmount.py
git commit -m "vm: boot images under SeaBIOS or IA32 edk2 from Python and judge the kernel log"
```

- [ ] **Step 7: Freeze the source image**

Other sessions write `vm/work/test.img`, so take a private copy before using it.

```bash
mkdir -p vm/work
cp /d/RhapsodiOS/vm/work/test.img vm/work/p1-whole.img
python - <<'EOF'
import hashlib, sys
sys.path.insert(0, "vm")
import rhap_image
with rhap_image.Image("vm/work/p1-whole.img") as img:
    k = img.read_file(img.resolve("/mach_kernel"))
print(len(k), hashlib.sha256(k).hexdigest()[:16])
EOF
```
Expected: `1486184 9916e7c0bdac2d4e`. If the hash differs, someone has changed
`test.img`. Stop and ask which kernel to use before going on.

- [ ] **Step 8: BIOS baseline, whole disk**

```bash
python vm/qemu_boot.py bios vm/work/p1-whole.img vm/logs/p1-bios-whole --at 60,120,180,240
python vm/check_rootmount.py vm/logs/p1-bios-whole/kernel.log
```
Expected: `root mount evidence OK`. Open `vm/logs/p1-bios-whole/shot-240s.png`
(with the Read tool). It should show userland, meaning the DR2 Setup
Assistant or a login screen, not kernel console text. If it's still on kernel
text, rerun with `--at 120,240,360` before drawing conclusions: TCG is slow.
Note the time at which userland first appears. Task 8 uses the same `--at`
list.

- [ ] **Step 9: UEFI baseline, two-disk layout, loader from before this plan's changes**

```bash
python vm/build_uefi_image.py --esp-only src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/p1-esp.img
python vm/qemu_boot.py uefi vm/work/p1-whole.img vm/logs/p1-uefi-whole --esp vm/work/p1-esp.img --at 60,120,180,240
grep -E "RhapsodiOS UEFI loader|rhapsody disk:|boot drivers linked|Starting Rhapsody" vm/logs/p1-uefi-whole/console.log
python vm/check_rootmount.py vm/logs/p1-uefi-whole/kernel.log
```
Expected:
- four `grep` hits, the disk line reading `rhapsody disk: handle N selected for biosdev 0x80`
- `root mount evidence OK`
- a userland screenshot, as in Step 8

This proves the toolchain, the `fat32` ESP, the bundled firmware and the runner
all work together before any loader change. If it fails, stop: that's an
environment problem, and it must be fixed before Tasks 6–8 mean anything.

No commit for Steps 7–9: the logs and images are gitignored. Keep the
`grep` output and the `check_rootmount` output for Task 8's write-up.

---

### Task 6: `bootefi` boots from the disk it was loaded from

**Files:**
- Create: `src/bootefi-1/efi_disk_select.h`, `src/bootefi-1/efi_disk_select.c`
- Create: `src/bootefi-1/tests/efi_disk_select_test.c`
- Modify: `src/bootefi-1/efi.h` (after the `EFI_BLOCK_IO_PROTOCOL_GUID` definition)
- Modify: `src/bootefi-1/efi_disk.c` (includes, the `DISKLABEL` define, `looks_like_rhapsody`, `efi_disk_init`)
- Modify: `src/bootefi-1/Makefile` (`EFI_SRCS`), `src/bootefi-1/tests/Makefile`

**Interfaces:**
- Produces:
  - `unsigned long efi_label_lba(const unsigned char *mbr)`
  - `int efi_dp_is_parent(const unsigned char *disk, const unsigned char *part)`
  - `EFI_LOADED_IMAGE_PROTOCOL`, `EFI_LOADED_IMAGE_PROTOCOL_GUID` and
    `EFI_DEVICE_PATH_PROTOCOL_GUID` in `efi.h`
  - console line `rhapsody disk: handle N selected for biosdev 0x80 (the disk this loader was read from)`,
    or `(first labelled disk)` on the fallback path

- [ ] **Step 1: Write the failing host test**

Create `src/bootefi-1/tests/efi_disk_select_test.c`:

```c
/* Host test for the UEFI loader's disk-selection helpers.  Pure byte
 * buffers: no firmware, no EFI types, no boot-2 headers. */
#include <stdio.h>
#include <string.h>

#include "efi_disk_select.h"

static int failures;

static void check(const char *name, unsigned long got, unsigned long want)
{
    if (got != want) {
        printf("FAIL %s: got %lu want %lu\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

static void put_entry(unsigned char *mbr, int n, unsigned char type,
                      unsigned long relsect)
{
    unsigned char *e = mbr + 446 + 16 * n;

    e[4] = type;
    e[8] = (unsigned char)relsect;
    e[9] = (unsigned char)(relsect >> 8);
    e[10] = (unsigned char)(relsect >> 16);
    e[11] = (unsigned char)(relsect >> 24);
}

static void test_label_lba(void)
{
    unsigned char mbr[512];

    memset(mbr, 0, sizeof mbr);
    check("no signature: whole-disk label", efi_label_lba(mbr), 15);

    mbr[510] = 0x55;
    mbr[511] = 0xAA;
    check("signature, empty table: whole-disk label", efi_label_lba(mbr), 15);

    put_entry(mbr, 0, 0xEF, 2048);
    put_entry(mbr, 1, 0xA7, 133120);
    check("ESP then 0xA7: 15 sectors into the 0xA7 partition",
          efi_label_lba(mbr), 133135);

    memset(mbr + 446, 0, 64);
    put_entry(mbr, 2, 0xA7, 63);
    put_entry(mbr, 3, 0xA7, 99999);
    check("the first 0xA7 entry wins", efi_label_lba(mbr), 78);
}

/* Append one device-path node; returns the offset just past it. */
static unsigned int node(unsigned char *dp, unsigned int at,
                         unsigned char type, unsigned char subtype,
                         unsigned int len)
{
    memset(dp + at, 0x5A, len);
    dp[at] = type;
    dp[at + 1] = subtype;
    dp[at + 2] = (unsigned char)len;
    dp[at + 3] = (unsigned char)(len >> 8);
    return at + len;
}

static unsigned int end_node(unsigned char *dp, unsigned int at)
{
    return node(dp, at, 0x7F, 0xFF, 4);
}

/* PciRoot/Pci(dev)/Ata -- the shape edk2 gives a PIIX3 IDE disk. */
static unsigned int disk_prefix(unsigned char *dp, unsigned char pci_dev)
{
    unsigned int at = 0;

    at = node(dp, at, 0x02, 0x01, 12);          /* ACPI: PciRoot */
    at = node(dp, at, 0x01, 0x01, 6);           /* Hardware: Pci */
    dp[at - 1] = pci_dev;
    at = node(dp, at, 0x03, 0x01, 8);           /* Messaging: Ata */
    return at;
}

static void test_dp_is_parent(void)
{
    unsigned char disk[64], part[128], other[128], cdrom[128];
    unsigned int at;

    end_node(disk, disk_prefix(disk, 1));

    at = disk_prefix(part, 1);
    at = node(part, at, 0x04, 0x01, 42);        /* Media: HardDrive */
    end_node(part, at);
    check("a partition of this disk", efi_dp_is_parent(disk, part), 1);

    at = disk_prefix(other, 2);
    at = node(other, at, 0x04, 0x01, 42);
    end_node(other, at);
    check("a partition of another disk", efi_dp_is_parent(disk, other), 0);

    at = disk_prefix(cdrom, 1);
    at = node(cdrom, at, 0x04, 0x02, 24);       /* Media: CDROM */
    end_node(cdrom, at);
    check("an El Torito entry is not an fdisk partition",
          efi_dp_is_parent(disk, cdrom), 0);

    check("a disk is not its own parent", efi_dp_is_parent(disk, disk), 0);

    disk[2] = 0;                                /* zero-length node */
    disk[3] = 0;
    check("a malformed disk path matches nothing",
          efi_dp_is_parent(disk, part), 0);
}

int main(void)
{
    test_label_lba();
    test_dp_is_parent();
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
```

In `src/bootefi-1/tests/Makefile`, add before `clean:`:

```make
# The disk-selection and boot-string helpers are pure C as well, built the
# same way as the ACPI parser.
$(BUILD)/efi_disk_select_test: efi_disk_select_test.c ../efi_disk_select.c \
		../efi_disk_select.h | $(BUILD)
	$(CC) $(ACPI_TEST_CFLAGS) -o $@ efi_disk_select_test.c ../efi_disk_select.c

test-disk-select: $(BUILD)/efi_disk_select_test
	$(BUILD)/efi_disk_select_test
```

and change the `.PHONY` line to `.PHONY: all clean test-acpi test-disk-select`.

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1/tests test-disk-select
```
Expected: a make error for the missing `../efi_disk_select.c`, or
`fatal error: 'efi_disk_select.h' file not found`.

- [ ] **Step 3: Write the helpers**

Create `src/bootefi-1/efi_disk_select.h`:

```c
/* Pure helpers for choosing the Rhapsody disk: no EFI calls, so
 * tests/efi_disk_select_test.c exercises them on byte buffers. */
#ifndef _BOOTEFI_EFI_DISK_SELECT_H_
#define _BOOTEFI_EFI_DISK_SELECT_H_

/* LBA of the first NeXT label copy on a disk whose sector 0 is `mbr`:
 * 15 sectors into the first 0xA7 fdisk partition, or LBA 15 when sector 0
 * has no 0xA7 entry (a whole-disk label, like golden.img).  Mirrors the
 * walk read_label() does in src/boot-2/i386/libsaio/disk.c. */
unsigned long efi_label_lba(const unsigned char *mbr);

/* Non-zero if `disk`, a whole-disk device path, is the parent of `part`:
 * every node of `disk` before its end node is a byte-for-byte prefix of
 * `part`, and the next node of `part` is Media/HardDrive (type 4,
 * subtype 1), i.e. an fdisk partition.  Both paths end-terminated. */
int efi_dp_is_parent(const unsigned char *disk, const unsigned char *part);

#endif /* _BOOTEFI_EFI_DISK_SELECT_H_ */
```

Create `src/bootefi-1/efi_disk_select.c`:

```c
#include "efi_disk_select.h"

#define MBR_PARTS           446
#define MBR_ENTRY           16
#define FDISK_NEXTNAME      0xA7
#define DISKLABEL           15      /* matches disk.c's DISKLABEL */

#define DP_END_TYPE         0x7F
#define DP_MEDIA_TYPE       0x04
#define DP_MEDIA_HARDDRIVE  0x01

static unsigned long le32(const unsigned char *p)
{
    return (unsigned long)p[0] | ((unsigned long)p[1] << 8) |
           ((unsigned long)p[2] << 16) | ((unsigned long)p[3] << 24);
}

unsigned long efi_label_lba(const unsigned char *mbr)
{
    int n;

    if (mbr[510] != 0x55 || mbr[511] != 0xAA)
        return DISKLABEL;
    for (n = 0; n < 4; n++) {
        const unsigned char *e = mbr + MBR_PARTS + n * MBR_ENTRY;
        if (e[4] == FDISK_NEXTNAME)
            return le32(e + 8) + DISKLABEL;
    }
    return DISKLABEL;
}

/* Bytes before the end node, or 0 for a malformed path. */
static unsigned int dp_body(const unsigned char *dp)
{
    unsigned int off = 0, len;

    while (dp[off] != DP_END_TYPE) {
        len = (unsigned int)dp[off + 2] | ((unsigned int)dp[off + 3] << 8);
        if (len < 4)
            return 0;
        off += len;
    }
    return off;
}

int efi_dp_is_parent(const unsigned char *disk, const unsigned char *part)
{
    unsigned int n = dp_body(disk), i;

    if (n == 0 || dp_body(part) <= n)
        return 0;
    for (i = 0; i < n; i++)
        if (disk[i] != part[i])
            return 0;
    return part[n] == DP_MEDIA_TYPE && part[n + 1] == DP_MEDIA_HARDDRIVE;
}
```

- [ ] **Step 4: Run the host test to verify it passes**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1/tests test-disk-select
```
Expected: nine `ok` lines and `all passed`.

- [ ] **Step 5: Declare the two protocols**

In `src/bootefi-1/efi.h`, after the `EFI_BLOCK_IO_PROTOCOL_GUID` definition, add:

```c
#define EFI_LOADED_IMAGE_PROTOCOL_GUID \
  {0x5b1b31a1,0x9562,0x11d2,{0x8e,0x3f,0x00,0xa0,0xc9,0x69,0x72,0x3b}}
#define EFI_DEVICE_PATH_PROTOCOL_GUID \
  {0x09576e91,0x6d3f,0x11d2,{0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b}}

/* Loaded image: the leading fields only; the loader reads DeviceHandle. */
typedef struct {
    UINT32      Revision;
    EFI_HANDLE  ParentHandle;
    void       *SystemTable;
    EFI_HANDLE  DeviceHandle;
} EFI_LOADED_IMAGE_PROTOCOL;
```

- [ ] **Step 6: Use the helpers in `efi_disk.c`**

In `src/bootefi-1/efi_disk.c`:

(a) After `#include "efi.h"` add `#include "efi_disk_select.h"`.

(b) Delete the `DISKLABEL` definition and its two-line comment (the
"Sector number of the NeXT disk label ..." block). `efi_label_lba()` owns that
constant now.

(c) Replace the comment block above `looks_like_rhapsody`, the function itself,
and `efi_disk_init` with:

```c
/* disk.c's open("hd(0,a)/...") always means biosdev 0x80, i.e. disks[0],
 * and EFI does not enumerate block devices in qemu's -drive order, so the
 * loader picks the Rhapsody disk itself and puts it first.
 *
 * A disk counts as Rhapsody if its first NeXT label copy carries DL_V3 --
 * the raw bytes 64 6c 56 33 ("dlV3"), big-endian whatever the payload's
 * byte order, which golden.img confirms.  efi_label_lba() finds that copy:
 * 15 sectors into the first 0xA7 fdisk partition, or LBA 15 on a
 * whole-disk label.
 */
static int looks_like_rhapsody(EFI_BLOCK_IO_PROTOCOL *bio)
{
    unsigned char sector[BPS];

    if (bio->Media->BlockSize != BPS)
        return 0;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId, 0,
                                  sizeof(sector), sector)))
        return 0;
    if (EFI_ERROR(bio->ReadBlocks(bio, bio->Media->MediaId,
                                  efi_label_lba(sector), sizeof(sector),
                                  sector)))
        return 0;
    return sector[0] == 0x64 && sector[1] == 0x6c &&
           sector[2] == 0x56 && sector[3] == 0x33;
}

static EFI_GUID gLoadedImageGuid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID gDevicePathGuid = EFI_DEVICE_PATH_PROTOCOL_GUID;

/* Device path of the partition this loader was read from, or 0. */
static const unsigned char *loaded_from_path(void)
{
    EFI_LOADED_IMAGE_PROTOCOL *li = 0;
    void *dp = 0;

    if (EFI_ERROR(gBS->HandleProtocol(gImageHandle, &gLoadedImageGuid,
                                      (void **)&li)))
        return 0;
    if (EFI_ERROR(gBS->HandleProtocol(li->DeviceHandle, &gDevicePathGuid,
                                      &dp)))
        return 0;
    return (const unsigned char *)dp;
}

/* Enumerate whole-disk BLOCK_IO handles, skipping partition handles, and
 * make the Rhapsody disk disks[0]: the disk this loader was read from if it
 * is one, otherwise the first labelled disk.  The fallback is what the
 * two-disk layout relies on, where the loader sits on an ESP-only disk. */
int efi_disk_init(void)
{
    EFI_HANDLE *handles = 0;
    UINTN size = 0, i;
    EFI_STATUS st;
    EFI_BLOCK_IO_PROTOCOL *cand[MAX_DISKS];
    const unsigned char *boot_path = loaded_from_path();
    int ncand, first_idx = -1, boot_idx = -1, rhapsody_idx, nmatches = 0;

    st = gBS->LocateHandle(ByProtocol, &gBlockIoGuid, 0, &size, 0);
    if (st != EFI_BUFFER_TOO_SMALL)
        return 0;
    if (EFI_ERROR(gBS->AllocatePool(EfiLoaderData, size, (void **)&handles)))
        return 0;
    if (EFI_ERROR(gBS->LocateHandle(ByProtocol, &gBlockIoGuid, 0, &size,
                                    handles))) {
        gBS->FreePool(handles);
        return 0;
    }

    ncand = 0;
    for (i = 0; i < size / sizeof(EFI_HANDLE) && ncand < MAX_DISKS; i++) {
        EFI_BLOCK_IO_PROTOCOL *bio = 0;
        void *dp = 0;

        if (EFI_ERROR(gBS->HandleProtocol(handles[i], &gBlockIoGuid,
                                          (void **)&bio)))
            continue;
        if (!bio->Media->MediaPresent || bio->Media->LogicalPartition)
            continue;
        if (looks_like_rhapsody(bio)) {
            if (first_idx < 0)
                first_idx = ncand;
            if (boot_idx < 0 && boot_path != 0 &&
                !EFI_ERROR(gBS->HandleProtocol(handles[i], &gDevicePathGuid,
                                               &dp)) &&
                efi_dp_is_parent((const unsigned char *)dp, boot_path))
                boot_idx = ncand;
            nmatches++;
        }
        cand[ncand++] = bio;
    }
    gBS->FreePool(handles);

    rhapsody_idx = boot_idx >= 0 ? boot_idx : first_idx;
    if (boot_idx >= 0) {
        printf("rhapsody disk: handle %d selected for biosdev 0x80 "
               "(the disk this loader was read from)\n", boot_idx);
    } else if (first_idx >= 0) {
        printf("rhapsody disk: handle %d selected for biosdev 0x80 "
               "(first labelled disk)\n", first_idx);
        if (nmatches > 1)
            printf("warning: %d handles matched the Rhapsody disk label; "
                   "using the first\n", nmatches);
    } else {
        printf("rhapsody disk: no handle matched the disk label; "
               "falling back to enumeration order\n");
    }

    ndisks = 0;
    if (rhapsody_idx >= 0)
        disks[ndisks++] = cand[rhapsody_idx];
    for (i = 0; i < (UINTN)ncand; i++) {
        if ((int)i == rhapsody_idx)
            continue;
        disks[ndisks++] = cand[i];
    }
    return ndisks;
}
```

(d) In `src/bootefi-1/Makefile`, change the `EFI_SRCS` definition to:

```make
EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_disk_select.c \
            efi_memory.c efi_vga.c efi_pci.c handoff.c $(BOOT2_SRCS)
```

- [ ] **Step 7: Build the loader**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1 2>&1 | grep -E "error|warning: .*efi_disk" ; ls -la src/bootefi-1/BUILD/BOOTIA32.EFI
```
Expected: no `error` lines and no warnings from `efi_disk.c` or
`efi_disk_select.c`, and a fresh `BOOTIA32.EFI`.

- [ ] **Step 8: Commit**

```bash
git add src/bootefi-1/efi.h src/bootefi-1/efi_disk.c src/bootefi-1/efi_disk_select.h src/bootefi-1/efi_disk_select.c src/bootefi-1/Makefile src/bootefi-1/tests/Makefile src/bootefi-1/tests/efi_disk_select_test.c
git commit -m "bootefi: boot from the disk the loader was read from, finding its label inside an fdisk partition"
```

---

### Task 7: `bootefi` honours `Kernel Flags`

**Files:**
- Create: `src/bootefi-1/efi_bootargs.h`, `src/bootefi-1/efi_bootargs.c`
- Create: `src/bootefi-1/tests/efi_bootargs_test.c`
- Modify: `src/bootefi-1/efi_main.c` (includes; just after the `loadSystemConfig` printf)
- Modify: `src/bootefi-1/Makefile` (`EFI_SRCS`), `src/bootefi-1/tests/Makefile`

**Interfaces:**
- Consumes: `getValueForKey(char *key, char **val, int *size)` (boot-2
  `stringTable.c`, declared in `saio_internal.h`, which `load.h` pulls in);
  `BOOT_STRING_LEN` (160, from `kernBootStruct.h`).
- Produces:
  - `void efi_append_boot_flags(char *boot, unsigned int cap, const char *flags, int len)`
  - console line `bootString '<final string>'`, printed after the config is
    loaded

The kernel's `getargs()` (`machdep/i386/i386_init.c`) reads the boot string
left to right, and each `rootdev=` overwrites the previous one, so the last
one wins. boot2 *prepends* `Kernel Flags` so that a typed `boot:` line
overrides the config. The UEFI loader has no `boot:` line but does have a
compiled-in default (`rootdev=hd0a -v`), so it *appends*: the config then
overrides the default, and `-v` survives.

- [ ] **Step 1: Write the failing host test**

Create `src/bootefi-1/tests/efi_bootargs_test.c`:

```c
/* Host test for appending System.config "Kernel Flags" to the boot string.
 * Pure C: no firmware, no boot-2 headers. */
#include <stdio.h>
#include <string.h>

#include "efi_bootargs.h"

static int failures;

static void check(const char *name, const char *got, const char *want)
{
    if (strcmp(got, want) != 0) {
        printf("FAIL %s: got '%s' want '%s'\n", name, got, want);
        failures++;
    } else {
        printf("ok   %s\n", name);
    }
}

int main(void)
{
    char boot[160], small[20];

    strcpy(boot, "rootdev=hd0a -v");
    efi_append_boot_flags(boot, sizeof boot, "", 0);
    check("an empty value changes nothing", boot, "rootdev=hd0a -v");

    strcpy(boot, "rootdev=hd0a -v");
    efi_append_boot_flags(boot, sizeof boot, "rootdev=hd1aXXXX", 12);
    check("the value follows a space, and only len bytes are taken",
          boot, "rootdev=hd0a -v rootdev=hd1a");

    boot[0] = '\0';
    efi_append_boot_flags(boot, sizeof boot, "-s", 2);
    check("an empty boot string gets no leading space", boot, "-s");

    strcpy(small, "rootdev=hd0a -v");
    efi_append_boot_flags(small, sizeof small, "rootdev=hd1a", 12);
    check("truncated to fit, still terminated", small, "rootdev=hd0a -v roo");

    strcpy(small, "0123456789012345678");
    efi_append_boot_flags(small, sizeof small, "-s", 2);
    check("a full string is left alone", small, "0123456789012345678");

    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    printf("all passed\n");
    return 0;
}
```

In `src/bootefi-1/tests/Makefile`, add after the `test-disk-select` rule:

```make
$(BUILD)/efi_bootargs_test: efi_bootargs_test.c ../efi_bootargs.c \
		../efi_bootargs.h | $(BUILD)
	$(CC) $(ACPI_TEST_CFLAGS) -o $@ efi_bootargs_test.c ../efi_bootargs.c

test-bootargs: $(BUILD)/efi_bootargs_test
	$(BUILD)/efi_bootargs_test
```

and change `.PHONY` to `.PHONY: all clean test-acpi test-disk-select test-bootargs`.

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1/tests test-bootargs
```
Expected: a make error for the missing `../efi_bootargs.c`, or
`'efi_bootargs.h' file not found`.

- [ ] **Step 3: Write the helper**

Create `src/bootefi-1/efi_bootargs.h`:

```c
#ifndef _BOOTEFI_EFI_BOOTARGS_H_
#define _BOOTEFI_EFI_BOOTARGS_H_

/* Append a System.config "Kernel Flags" value to the boot string, after a
 * space.  The kernel's getargs() keeps the last rootdev= it sees, so this
 * lets the config override the loader's compiled-in default -- where
 * boot2's prepend (boot.c) exists so a typed boot: line overrides the
 * config.  `flags` is getValueForKey()'s value: `len` bytes, not
 * NUL-terminated.  Truncates to fit `cap` bytes including the NUL; a
 * value of length 0 changes nothing. */
void efi_append_boot_flags(char *boot, unsigned int cap, const char *flags,
                           int len);

#endif /* _BOOTEFI_EFI_BOOTARGS_H_ */
```

Create `src/bootefi-1/efi_bootargs.c`:

```c
#include "efi_bootargs.h"

void efi_append_boot_flags(char *boot, unsigned int cap, const char *flags,
                           int len)
{
    unsigned int n = 0;
    int i;

    if (len <= 0 || cap == 0)
        return;
    while (n < cap - 1 && boot[n] != '\0')
        n++;
    if (n > 0 && n < cap - 1)
        boot[n++] = ' ';
    for (i = 0; i < len && n < cap - 1; i++)
        boot[n++] = flags[i];
    boot[n] = '\0';
}
```

- [ ] **Step 4: Run the host test to verify it passes**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1/tests test-bootargs
```
Expected: five `ok` lines and `all passed`.

- [ ] **Step 5: Call it after the config loads**

In `src/bootefi-1/efi_main.c`, add `#include "efi_bootargs.h"` after
`#include "sarld.h"	/* sa_rld_t */`, then replace the line

```c
    printf("loadSystemConfig: %d\n", loadSystemConfig(0, 0));
```

with:

```c
    printf("loadSystemConfig: %d\n", loadSystemConfig(0, 0));

    /* boot2 folds the config's "Kernel Flags" into the boot string
     * (boot.c); this loader appends them after its compiled-in default so
     * the kernel's getargs(), which keeps the last rootdev= it sees, takes
     * the config's value. */
    {
        char *val;
        int size;

        if (getValueForKey("Kernel Flags", &val, &size))
            efi_append_boot_flags(kernBootStruct->bootString,
                                  BOOT_STRING_LEN, val, size);
        printf("bootString '%s'\n", kernBootStruct->bootString);
    }
```

In `src/bootefi-1/Makefile`, add `efi_bootargs.c` to `EFI_SRCS`:

```make
EFI_SRCS := efi_main.c efi_console.c efi_disk.c efi_disk_select.c \
            efi_bootargs.c efi_memory.c efi_vga.c efi_pci.c handoff.c \
            $(BOOT2_SRCS)
```

- [ ] **Step 6: Build the loader**

Run:
```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1 2>&1 | grep -E "error|warning: .*(efi_main|efi_bootargs)" ; ls -la src/bootefi-1/BUILD/BOOTIA32.EFI
```
Expected: no `error` lines and no warnings from these two files.

- [ ] **Step 7: Commit**

```bash
git add src/bootefi-1/efi_bootargs.h src/bootefi-1/efi_bootargs.c src/bootefi-1/efi_main.c src/bootefi-1/Makefile src/bootefi-1/tests/Makefile src/bootefi-1/tests/efi_bootargs_test.c
git commit -m "bootefi: append System.config Kernel Flags so the config's rootdev wins"
```

---

### Task 8: The gate — one disk, both firmwares — and the write-up

**Files:**
- Create: `docs/boot/partitioned-disk-boot.md`

**Interfaces:**
- Consumes: everything above. `vm/work/p1-whole.img` (Task 5, Step 7).

- [ ] **Step 1: Build the hybrid disk with the new loader**

```bash
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1 >/dev/null
python vm/build_uefi_image.py vm/work/p1-whole.img src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/p1-hybrid.img
python - <<'EOF'
import hashlib, sys
sys.path.insert(0, "vm")
import rhap_image
with rhap_image.Image("vm/work/p1-hybrid.img") as img:
    k = img.read_file(img.resolve("/mach_kernel"))
    print("part_start", img.part_start, "label_offset", img.label_offset)
print(len(k), hashlib.sha256(k).hexdigest()[:16])
EOF
```
Expected: `part_start 68321280 label_offset 68165120`, which is
`133120 × 512 + 160 × 1024` and `133120 × 512 + 7680`, then
`1486184 9916e7c0bdac2d4e`. Building copies about 8 GB, so allow a few minutes.

- [ ] **Step 2: BIOS boot of the hybrid disk**

```bash
python vm/qemu_boot.py bios vm/work/p1-hybrid.img vm/logs/p1-bios-hybrid --at 60,120,180,240
python vm/check_rootmount.py vm/logs/p1-bios-hybrid/kernel.log
```
Use the same `--at` list the baseline needed in Task 5 Step 8.
Expected: `root mount evidence OK`, and a final screenshot showing the same
userland screen as `vm/logs/p1-bios-whole/`.

This exercises the unchanged boot0, boot1 and boot2 against the rebased label.
If the screen stops at `Missing OS` or `Error loading OS` (boot0's messages),
the CHS values don't match SeaBIOS's translation: print the geometry
`lba_assist_geometry` chose and compare it with SeaBIOS's view (`info block`
over QMP isn't enough; boot the disk with `-d int` if needed). Don't touch the
booters.

- [ ] **Step 3: UEFI boot of the hybrid disk, one disk only**

```bash
python vm/qemu_boot.py uefi vm/work/p1-hybrid.img vm/logs/p1-uefi-hybrid --at 60,120,180,240
grep -E "rhapsody disk:|bootString|boot drivers linked|Starting Rhapsody" vm/logs/p1-uefi-hybrid/console.log
python vm/check_rootmount.py vm/logs/p1-uefi-hybrid/kernel.log
```
Expected:
- `rhapsody disk: handle N selected for biosdev 0x80 (the disk this loader was read from)`
- `bootString 'rootdev=hd0a -v'`, unchanged because `test.img`'s `Kernel Flags`
  is empty. Phase 4's live media is the first image to set it.
- `boot drivers linked:` followed by a non-zero count
- `Starting Rhapsody`
- `root mount evidence OK`
- a userland screenshot

- [ ] **Step 4: The two-disk layout still boots, via the fallback**

```bash
python vm/build_uefi_image.py --esp-only src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/p1-esp.img
python vm/qemu_boot.py uefi vm/work/p1-whole.img vm/logs/p1-uefi-twodisk --esp vm/work/p1-esp.img --at 60,120,180,240
grep "rhapsody disk:" vm/logs/p1-uefi-twodisk/console.log
python vm/check_rootmount.py vm/logs/p1-uefi-twodisk/kernel.log
```
Expected: `... (first labelled disk)`, then `root mount evidence OK`.

- [ ] **Step 5: Write up the result**

Create `docs/boot/partitioned-disk-boot.md` using this skeleton. Fill every
bracketed item from the logs of Task 5 Steps 8–9 and this task's Steps 2–4,
quoting the real lines:

```markdown
# Booting an fdisk-partitioned disk

A Rhapsody disk can share an MBR with other partitions, such as the ESP the
UEFI loader needs. boot0, boot1, boot2 and the kernel all support this
unchanged, provided the NeXT label inside the `0xA7` partition is written
the way `disk -i -b` writes it.

## The label convention

- The label's **location** is relative to the partition. Copies sit at
  `relsect + 15`, `+ 30` and `+ 45`, and each copy's `dl_label_blkno` must
  equal that physical block, or `check_label` rejects it with "Label in wrong
  location" (`driverkit-3/libDriver/label_subr.c`).
- The label's **contents** are absolute. `p_base` and `d_boot0_blkno[]`
  include the partition base (`diskdev_cmds/disk.tproj/hd.c`). boot1 loads
  boot2 from the absolute `d_boot0_blkno` (`boot-2/i386/boot1/boot1.asm`).
  boot2's `read_label()` sets `boff = dl_front + p_base`
  (`boot-2/i386/libsaio/disk.c`). The kernel computes the partition base as
  `(p_base + d_front) × d_secsize / physBlockSize`
  (`driverkit-3/libDriver/IODiskPartition.m`).
- `disk -i` labels an fdisk disk with `secsize` 512 (`disk.c:445` clears
  `force_blocksize`). A whole-disk label, like `golden.img`'s, uses 1024.

Copying a whole-disk image into a partition verbatim breaks both rules. That
is why the original two-disk UEFI layout existed (see
`docs/superpowers/specs/2026-09-17-uefi-bootloader-design.md`, *Disk image*).
`vm/build_uefi_image.py`'s `rebase_labels()` now rewrites the copy.

boot0 reads the active partition's boot sector by the CHS fields in its MBR
entry, so those fields follow the BIOS's LBA-assisted translation
(`lba_assist_geometry()`).

## Evidence (<date>, QEMU <version>, kernel SHA-256 prefix 9916e7c0bdac2d4e)

| Boot | Firmware | Loader's disk choice | Kernel log | Userland at |
|---|---|---|---|---|
| whole disk (baseline) | SeaBIOS | n/a | [check_rootmount output] | [N s] |
| whole disk + ESP disk (baseline, old loader) | edk2-i386 | [line] | [output] | [N s] |
| hybrid, one disk | SeaBIOS | n/a | [output] | [N s] |
| hybrid, one disk | edk2-i386 | [line] | [output] | [N s] |
| whole disk + ESP disk (new loader) | edk2-i386 | [line] | [output] | [N s] |

## Reproducing

    python vm/build_uefi_image.py IMAGE src/bootefi-1/BUILD/BOOTIA32.EFI OUT.img
    python vm/qemu_boot.py {bios,uefi} OUT.img vm/logs/RUN --at 60,120,180,240
    python vm/check_rootmount.py vm/logs/RUN/kernel.log
```

- [ ] **Step 6: Run every test once more**

```bash
cd vm && RHAPSODY_FLOPPY=D:/RhapsodiOS/vm/install/rhapsody_dr2_x86_InstallationFloppy.img python -m unittest test_fat32 test_build_uefi_image test_qemu_boot test_check_rootmount -v; cd ..
export PATH="/c/Program Files/LLVM/bin:$PATH"
make -C src/bootefi-1/tests test-acpi test-disk-select test-bootargs 2>&1 | grep -E "FAIL|all passed"
```
Expected: every Python test `ok`, with only the golden-image refusal test
skipped; and no `FAIL`, with `all passed` printed twice (by the disk-select and
bootargs tests).

- [ ] **Step 7: Commit**

```bash
git add docs/boot/partitioned-disk-boot.md
git commit -m "docs: record the fdisk label convention and the one-disk BIOS and UEFI boots"
```
