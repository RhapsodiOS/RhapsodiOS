# Injecting the rebuilt i386 kernel and EIDE driver into the Rhapsody DR2 install media

**Date:** 2026-07-28
**Status:** Design approved, pending spec review
**Component:** `vm/` tooling; media under `vm/install/`

## Problem

`out/i386/mach_kernel` and `out/i386/drvEIDE/EIDE.config/EIDE_reloc` carry the
kernel fixes and the reworked EIDE driver described in
`docs/drivers/drvEIDE-issues.md`. Both currently reach a running system only by
patching an already-installed disk (`vm/work/test.img`) with `rhap_inject.py`.
That path cannot test the installer itself, which is where the EIDE failure
actually bites: the stock driver is what mounts the target disk during
installation.

The goal is to boot the Rhapsody DR2 x86 installer under QEMU with the new
kernel and driver and complete an install onto an IDE disk, end to end,
producing a system that boots from IDE unaided.

## What the media actually is

All three files in `vm/install/` are **NeXT-labeled UFS volumes**, not the
formats their names suggest. `rhapsody_dr2_x86.iso` is not ISO 9660: it carries
a `dlV3` disk label at offset 7680 with `secsize` 2048 and a UFS filesystem
inside. `rhap_image.py` reads all three directly, with no mounting and no
external tools.

| File | Role |
|------|------|
| `rhapsody_dr2_x86_InstallationFloppy.img` | Boots the installer. Carries `/mach_kernel.rcz` and `/usr/standalone/i386/sarld`. |
| `rhapsody_dr2_x86_DriverDisk.img` | Supplies disk/SCSI drivers interactively during install. Carries `EIDE.config/EIDE_reloc.rcz`. |
| `rhapsody_dr2_x86.iso` | The installer's root filesystem, and the source tree the installer copies onto the target. |

The installation floppy's `System.config/Instance0.table` reads:

```
"Boot Drivers" = "PS2Keyboard EISABus PCIBus Intel824X0";
"Kernel" = "mach_kernel";
"Kernel Flags" = "rootdev=cdrom";
"Ask For Drivers" = "Yes";
"Installation Driver Families" = "Disk SCSI";
```

So the floppy boots a kernel with no disk driver, prompts for the driver disk,
and mounts the CD as root. `/private/etc/rc.boot` on the CD detects a CD-ROM
root and skips `fsck` entirely. The installed system's `/mach_kernel` and
`/private/Drivers/i386/*` are copied from the CD, so the CD's copies are what
the finished machine runs.

Two measured facts shape the design:

- The four `/System/Installation/DiskImages/Rhapsody*.image` files on the CD are
  1,474,560 bytes each, and `RhapsodyInstall.image` / `RhapsodyDrivers.image`
  are **byte-identical (MD5) to the two standalone floppies**. Whatever we build
  as a floppy is written back into the CD as an exact-size overwrite.
- `src/boot-2/gen/rcz/` contains the rcz compressor sources, so the `.rcz`
  payloads can be regenerated rather than worked around. The `0x0000029a` at the
  head of `mach_kernel.rcz` is `METHOD_17_JUL_95 = 666` stored big-endian.

## Sizing

`rhap_inject.py` never allocates; it can only overwrite within a file's existing
fragments. Measured against that limit:

| Target | New artifact | In-place cap | Fits |
|---|---|---|---|
| CD `EIDE.config/EIDE_reloc` | ~121 KB stripped | 122,880 | yes |
| CD `DiskImages/Rhapsody{Install,Drivers}.image` | 1,474,560 | 1,474,560 | yes, exact |
| CD `/mach_kernel` | 1,472,800 | 1,404,928 | **no** |
| Floppy `/mach_kernel.rcz` | ~1,097,400 | 1,052,672 | **no** |
| Driver disk `EIDE_reloc.rcz` | ~84 KB stripped | 84,992 | n/a — repackaged |

The in-place caps are what `rhap_inject.py` permits. They bind only on the CD,
which is patched in place; both floppies are repackaged, so their caps are
informational and only the whole-volume budget below constrains them.

### The driver is not a sizing problem

`out/i386/drvEIDE/EIDE.config/EIDE_reloc` is 856,404 bytes against the stock
121,056, but the code is the same size — the difference is an unstripped symbol
table:

```
              text+data     symbols        total
stock EIDE      108,924      12,132      121,056   (298 symbols)
new EIDE        108,196     748,208      856,404   (20,021 symbols)
```

Stripping restores it to roughly the stock size and it fits in place everywhere.
This is fixed at the build, by adding the strip step to
`vm/build-i386-kernel-eide.sh`, not by a post-hoc Mach-O rewriter: a relocatable
driver must keep its globals, undefineds and relocations intact for the kernel
loader.

### The kernel growth is real

```
              text+data     symbols        total
stock kernel  1,290,240     113,876    1,404,116
new kernel    1,351,680     121,120    1,472,800
```

+61 KB of text and data. Nothing to strip.

On the CD this is handled by `rhap_inject.graft_file`, which repoints a
directory entry at a donor inode. Grafting's known hazard is `fsck`, and the CD
root is mounted read-only and never fscked, so the hazard does not apply. The
630 MB volume has ample donor candidates.

### The installation floppy is the binding constraint

From `fs_cstotal`, the floppy has **38,912 bytes free**, and there is nothing to
delete: of 184 non-kernel frags, `sarld` alone is 160.

```
data capacity (fs_dsize)                1263 frags
non-kernel objects (1224 - 1040)         184 frags
                                        ----------
budget for mach_kernel.rcz              1079 frags  = 1,104,896 B
less its single indirect block            -8 frags
less tail/block rounding                ~ -4 frags
                                        ----------
practical payload ceiling               ~1,092,000 B
projected new mach_kernel.rcz           ~1,097,400 B
```

The projection scales the shipped file's size by the zlib ratio between the two
kernels; rcz is a much weaker compressor (0.749 vs 0.449 on the same input), so
the estimate carries error bars of a few percent — wider than the ~5–8 KB it is
currently over by. **Whether the new kernel fits a 1.44 MB floppy cannot be
decided by estimation.** The design therefore gates on measuring it.

## Approach

Extract the contents of each floppy and repackage the whole volume, rather than
teaching `rhap_inject.py` to allocate. Both floppies are single-cylinder-group,
shallow (depth ≤ 5), and contain 20 and 110 objects with **no symlinks, no hard
links and no device nodes** — so synthesizing a fresh filesystem is less code
than a correct free-bitmap allocator, is deterministic, and is the only approach
that can also change the volume's size.

The CD is *not* repackaged. Once the driver is stripped it needs no growth at
all, and reproducing ~70k inodes, symlinks, ownership, multi-cylinder-group
layout and the `/mach_kernel` ↔ `/private/tftpboot/mach_kernel` hard link would
buy nothing.

### Components

**`vm/rcz.py`** — port of `rcz_compress_mem.c` and `rcz_decompress_mem.c`.
Standard library only; no knowledge of UFS or media.

```
compress(bytes) -> bytes
decompress(bytes) -> bytes
```

**`vm/rhap_image.py`** — extended only as needed: `Inode` gains `uid` and `gid`
(offsets 116 and 120 in the 128-byte dinode) and the reader gains `readlink`, so
an extracted tree carries enough to be rebuilt faithfully. It stays read-only.

**`vm/ufs_extract.py`** — walks an image into a tree of (path, type, mode, uid,
gid, mtime, contents). Pure read.

**`vm/ufs_build.py`** — takes a template image plus a tree and returns a
complete volume as bytes.

The design decision that keeps this small: it clones the template's geometry
rather than inventing a filesystem. The disk label and every geometry field of
the superblock — `fs_size`, `fs_bsize`, `fs_fsize`, `fs_frag`, `fs_ncg`,
`fs_ipg`, `fs_fpg`, `fs_cgoffset`, rotational tables — are copied verbatim from
the source. Only allocation state is regenerated: cylinder-group free bitmaps,
`fs_cstotal`, the inode table, directory blocks, and a sequentially packed data
area. The output is the filesystem `newfs` would have produced with our contents
in it.

It refuses rather than improvises. A symlink, hard link, device node, or a tree
exceeding `fs_dsize` raises instead of producing a best effort. Neither floppy
contains any of those today, so these are tripwires against silent corruption,
not limitations being worked around.

**`vm/build_media.py`** — the orchestrator, and the only component that knows
what "EIDE" means. A manifest states which artifacts go onto which medium, so
widening the set later is data rather than code.

### Data flow

```
vm/install/*.iso,*.img   (pristine masters, never written)
        |
        +-- InstallationFloppy --> extract -> swap /mach_kernel.rcz
        |                              = rcz.compress(out/i386/mach_kernel)
        |                          -> build --> build/InstallationFloppy.img
        |
        +-- DriverDisk ---------> extract -> swap EIDE.config/EIDE_reloc.rcz
        |                              = rcz.compress(strip(out/.../EIDE_reloc))
        |                          -> build --> build/DriverDisk.img
        |
        +-- ISO ---------------> copy, then in place:
                                   put  EIDE.config/EIDE_reloc
                                   put  DiskImages/RhapsodyInstall.image
                                   put  DiskImages/RhapsodyDrivers.image
                                   graft /mach_kernel
                                                    --> build/rhapsody_dr2_x86.iso
```

Outputs land in `vm/install/build/`. The masters in `vm/install/` are treated
exactly as `golden.img` is: read-only, protected by a `check_target`-shaped
refusal so a bug cannot destroy them.

The graft leaves `/private/tftpboot/mach_kernel` pointing at the stock kernel.
That is the netboot copy, unused by this install path; it is left stale
deliberately rather than growing the tooling to chase it.

## The gate

Port `rcz.py` and measure `len(compress(out/i386/mach_kernel))` against the
ceiling computed from the live superblock. This runs **before anything else is
built**, because it is the only step that can invalidate the approach.

The port must earn trust before its output is believed:

1. `decompress(shipped mach_kernel.rcz)` equals the CD's `/mach_kernel` exactly,
   all 1,404,116 bytes.
2. `compress(CD /mach_kernel)` reproduces the shipped `mach_kernel.rcz`
   byte-for-byte — proving the port makes the same choices as the tool that
   built the media.
3. If (2) does not reproduce, because the shipped media may predate this source
   drop, fall back to requiring `decompress(compress(x)) == x` for both kernels
   and the driver, plus round-trips on empty, all-zero, incompressible and
   boundary-length inputs. The measurement stands, noted as not cross-checked.

**If the kernel fits**, build 1.44 MB media as described.

**If it does not**, resize the installation floppy to 2.88 MB. The repackager
already regenerates geometry, so this is a parameter change: a new label
geometry (80 cylinders, 2 heads, 36 sectors) and a filesystem sized for 2880
frags. This branch is pre-approved, and costs only the rcz port, which is needed
either way. It yields QEMU-only media, which is acceptable for this goal.

## Testing

Standard library `unittest`, matching the existing `vm/test_*.py`.

- **`test_rcz.py`** — the three properties above.
- **`test_ufs_build.py`** — the load-bearing test is the identity round-trip:
  extract a pristine floppy, rebuild it unmodified, and assert the result reads
  back through `rhap_image` with the same tree, file bytes, modes and ownership,
  and self-consistent free-space accounting. Byte-identity with the original is
  *not* asserted; allocation order will not match `newfs`. Then each refusal
  path — symlink, hard link, device node, over-capacity — raises.
- Both floppies are small enough to test against the real media rather than
  synthetic fixtures.

## Success criteria

Goal-ordered; the last is the definition of done.

1. `rcz.py` satisfies its verification properties, and the measured compressed
   kernel size is recorded against the computed ceiling.
2. Rebuilding either pristine floppy unmodified reads back identical.
3. QEMU boots `build/InstallationFloppy.img` and the new kernel comes up.
4. The installer accepts `build/DriverDisk.img` and the new EIDE driver attaches
   to QEMU's PIIX3 IDE — this is the direct test of
   `docs/drivers/drvEIDE-issues.md` §2.
5. The installer mounts the CD and sees a blank IDE target disk.
6. The install completes.
7. **The installed system boots from IDE unaided** — no graft, no `rc.boot`
   edits, none of the `vm/work/test.img` scaffolding.

Driven by the existing `qemu-shot.py` and `guest-console.py` against a scratch
disk image.

## Out of scope

- `RhapsodyNetInstall.image` and `RhapsodyNetDrivers.image`. The netboot path is
  not exercised by this goal; they stay stock.
- Repackaging the CD.
- Any driver other than EIDE. The manifest makes adding one data, but nothing
  else is added speculatively.

## Gate result (2026-07-28)

`vm/measure-kernel-fit.py` output:

```
kernel            1472800 bytes
compressed        1103265 bytes
other objects     184 frags
budget            1079 frags
ceiling           1089536 bytes
margin            -13729 bytes
VERDICT: does NOT fit; fall through to the 2.88 MB branch (Task 7a)
```

The rebuilt kernel's rcz stream does not fit the 1.44 MB floppy, so the plan
proceeds down the 2.88 MB resize branch (Task 7a) rather than the 1.44 MB
media path.
