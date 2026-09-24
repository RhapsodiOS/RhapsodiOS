# Booting an fdisk-partitioned disk

A Rhapsody disk can share an MBR with other partitions, such as the ESP the
UEFI loader needs. boot0, boot1, boot2 and the kernel all support this
unchanged, provided the NeXT label inside the `0xA7` partition is written
the way `disk -i -b` writes it. `vm/build_uefi_image.py`'s `rebase_labels()`
keeps the copied image's own `secsize` (1024 for golden-derived images)
rather than rewriting it to the 512 `disk -i -b` writes; both boot, because
boot1, boot2 and the kernel all scale `p_base`/`d_boot0_blkno` by
`d_secsize`, and phase 4's `label.py` writes 512 on an fdisk disk as
`disk -i -b` does.

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

## Test image

The boots in the evidence table below run `vm/work/p1-eide.img`, not
`test.img` directly.
`p1-eide.img` starts from `vm/work/test.img` (kernel SHA-256 prefix
`9916e7c0bdac2d4e`, matching `vm/install/mach_kernel`) and replaces two
files in place, via `ufs_alloc.grow_file`:

- `/private/Drivers/i386/EIDE.config/EIDE_reloc` ← the in-tree `drvEIDE`,
  host-built 2026-09-20 22:07 from `drvEIDE` at commit `2d2d7e5f0` (the only
  later `drvEIDE` commit, `cbe7ba4bf`, is declaration-only) — 131,264
  bytes, SHA-256 prefix `6c0438307e371843`.
- `/usr/standalone/i386/sarld` ← the node-table-limit fix described in
  `docs/boot/sarld-driver-link-limit.md` — 148,108 bytes, SHA-256 prefix
  `6867129c1a6bfb85`. Stock `sarld` (SHA-256 prefix `bbfb53f28725908d`)
  cannot link a 131 KB driver.

Apple's stock `drvEIDE` cannot be used for this image: it sizes the disk
from CHS geometry rather than from the drive's own reported LBA capacity,
which is too small once the filesystem sits behind an ESP on an 8 GB disk.
See "Found along the way" below.

## Found along the way

- **`init died` on both firmwares.** The stock `drvEIDE` sizes the disk
  from CHS geometry: 16383×16×63 sectors = 8063.5 MB
  (`IdeCntInit.m`'s `ip->total_sectors = chsSectors` path). The 8 GB
  filesystem ends at 8024.7 MB as a whole disk, but shifted 65 MB behind
  the ESP it ends at 8089.7 MB, so `System.framework/Versions/B/System`
  (cylinder group 508, ~8067 MB) fell past the CHS-derived capacity and
  `mach_init` could not start. `IdeCntInit.m` publishes IDENTIFY's LBA
  capacity instead (`ip->total_sectors = capacity.sectors`) whenever its
  "Address Mode" config key is `LBA`; installer targets larger than
  8063.5 MB need this in-tree `drvEIDE`, not Apple's stock one. The label
  rebase, booters and kernel were not at fault.
- **UEFI's wrong disk-choice line.** `looks_like_rhapsody` re-evaluated
  `efi_label_lba(sector)` after the first `ReadBlocks` had already
  overwritten `sector`, because the old `EFI_ERROR(...)` macro ran its
  argument twice — so the second evaluation re-read LBA 15 instead of the
  label's real location, and no handle matched. Commit `a008e1876` made
  `EFI_ERROR` a single-evaluation inline function in `efi.h`, fixing the
  double call.

## Evidence (2026-09-23, QEMU 11.1.0, kernel SHA-256 prefix 9916e7c0bdac2d4e)

| Boot | Firmware | Loader's disk choice | Kernel log | Userland at |
|---|---|---|---|---|
| whole disk (baseline, stock driver) | SeaBIOS | n/a | root mount evidence OK | 60 s |
| whole disk + ESP disk (baseline, stock driver, old loader) | edk2-i386 | `handle 0 selected for biosdev 0x80` | root mount evidence OK | 60 s |
| hybrid, one disk (first attempt, stock driver) | SeaBIOS | n/a | found 'panic' (`init died`) | none — kernel panic screen |
| hybrid, one disk (first attempt, stock driver) | edk2-i386 | `no handle matched the disk label; falling back to enumeration order` | found 'panic' (`init died`) | none — kernel panic screen |
| whole disk (EIDE-fixture sanity boot) | SeaBIOS | n/a | root mount evidence OK | 60 s |
| hybrid, one disk (rerun, EIDE fixture) | SeaBIOS | n/a | root mount evidence OK | 60 s |
| hybrid, one disk (rerun, EIDE fixture) | edk2-i386 | `handle 0 selected for biosdev 0x80 (the disk this loader was read from)` | root mount evidence OK | 60 s |
| whole disk + ESP disk (rerun, EIDE fixture, new loader) | edk2-i386 | `handle 0 selected for biosdev 0x80 (first labelled disk)` | root mount evidence OK | 60 s |

## Reproducing

    python vm/build_uefi_image.py IMAGE src/bootefi-1/BUILD/BOOTIA32.EFI OUT.img
    python vm/qemu_boot.py {bios,uefi} OUT.img vm/logs/RUN --at 60,120,180,240
    python vm/check_rootmount.py vm/logs/RUN/kernel.log

Each run directory also gets a `qemu-stderr.log`, so a boot that fails
before or during a screenshot still leaves a diagnostic trail.

For the two-disk layout (an ESP-only loader disk plus IMAGE attached whole):

    python vm/build_uefi_image.py --esp-only src/bootefi-1/BUILD/BOOTIA32.EFI vm/work/esp.img
    python vm/qemu_boot.py uefi IMAGE vm/logs/RUN --esp vm/work/esp.img --at 60,120,180,240
