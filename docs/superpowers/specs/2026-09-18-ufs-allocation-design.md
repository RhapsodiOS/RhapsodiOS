# UFS allocation for the Rhapsody disk image

## Goal

Add the ability to create, grow and remove files and directories in an existing
Rhapsody UFS filesystem image, so that new content — a driver bundle, a rebuilt
binary — can be installed into a disk image without a running guest.

The immediate need is the reconstructed AHCI driver: it must land at
`/private/Drivers/i386/AHCI.config/` with its real name, and no existing tool
can create that directory.

**Done when:** a directory and its files can be created in a clone of
`golden.img`, the guest boots from it, and the guest's own `/sbin/fsck` reports
the filesystem clean. Removal is held to the same bar: after creating and then
removing a directory tree, fsck reports clean and the filesystem's free counts
return to their original values.

## Why the existing tools cannot do this

Three tools already touch these images, and none can grow one.

`rhap_image.py` reads: superblock, cylinder groups, inodes, directories, file
contents. No writes.

`rhap_inject.py` writes **in place only**. Its opening line is "Never
allocates" — it modifies the contents of already-mapped fragments and `di_size`,
nothing else. That is a deliberate safety property, not an oversight: it is why
the tool can be pointed at an 8GB image with confidence. Its `graft_file()`
extends the idea by repointing a directory entry at a larger donor inode, which
solves "replace a file with a bigger one" without allocating, but cannot create
anything new.

`ufs_build.py` builds a filesystem from scratch and regenerates all allocation
state. It contains the summary math we need, but it refuses any volume with
`ncg != 1` — it exists for the two install floppies. Incrementally mutating a
510-group filesystem is a different problem.

## The target filesystem

`golden.img`, measured:

| Property | Value |
|---|---|
| Cylinder groups | 510 |
| Block size | 8192 |
| Fragment size | 1024 |
| Fragments per block | 8 |
| Direct block pointers | 12 (`NDADDR`) |
| Inode size | 128 bytes |

## Approach

A new module, `vm/ufs_alloc.py`, is the only thing in the tree that can grow a
filesystem. `rhap_inject.py` is not modified, so its "never allocates"
guarantee stays intact and continues to mean something. The two are siblings:
reach for `rhap_inject` when you want edits that provably cannot change
allocation, and for `ufs_alloc` when you explicitly want growth.

Alternatives considered and rejected:

- **Extend `rhap_inject.py`.** One tool, existing safety rails — but every
  refusal path in that file is built around the invariant that it never
  allocates. Adding allocation would blunt the one property that makes it
  trustworthy.
- **Extend `ufs_build.py`.** It has the CG math, but it regenerates allocation
  state for a fresh image and is hard-limited to one cylinder group. Mutating
  an existing multi-group filesystem is a different problem wearing similar
  clothes.

### Shared math

The pure functions currently in `ufs_build.py` — `recompute_cg_tables()`,
`recompute_cluster_maps()`, `bit_is_set()`, `cbtocylno()`, `cbtorpos()` and the
`CgTables` tuple — move to a new `vm/ufs_cg.py`, imported by both the builder
and the allocator.

This is load-bearing rather than tidiness. If the builder and the allocator
ever computed `cs_nbfree` differently, the result would be an image that looks
correct until fsck or the kernel disagrees. One implementation, two callers.
`test_ufs_build.py` covers the builder, so the extraction is verifiable.

### Layers

| Layer | Responsibility |
|---|---|
| CG access | Locate a cylinder group; read and write its header and its two bitmaps |
| Raw allocators | `alloc_frags` / `free_frags`, `alloc_inode` / `free_inode`; maintain the CG summary, the `fs_csaddr` summary array and the superblock's `fs_cstotal` |
| Namespace | `create_file`, `mkdir`, `grow`, `unlink`, `rmdir`; directory entries and `di_nlink` |

The raw allocator layer is where corruption lives, and it knows nothing about
paths or files — only bitmaps and counters. It can therefore be tested
exhaustively against small synthetic images with no directories involved, and
the namespace layer above it can be tested with allocation already trusted.

The public API is path-based and small, mirroring `rhap_inject`'s shape: hand it
a path and bytes; it either succeeds or raises.

## On-disk invariants

Every allocation must leave these five mutually consistent. They are what fsck
checks.

1. A cylinder group's free-fragment bitmap agrees with its `cg_cs.cs_nbfree`
   and `cs_nffree`, and with the `blktot`/`blks`/`frsum` rotational tables —
   all derivable from the bitmap, which is what `recompute_cg_tables()` does.
2. A cylinder group's inode bitmap agrees with its `cs_nifree` and `cs_ndir`.
3. Each group's `cg_cs` agrees with its entry in the filesystem-wide summary
   array at `fs_csaddr`.
4. The sum of all per-group summaries agrees with the superblock's
   `fs_cstotal`.
5. An inode's `di_blocks` (`total_frags * g.nspf`, not a hardcoded
   512-byte-sector count) agrees with the fragments its block pointers
   actually reference.

### Invariant 4 as a precondition

Before writing anything, the allocator recomputes the sum of every group's
summary and compares it with `fs_cstotal` on the untouched image. Disagreement
means we have misread the layout or the geometry, and the allocator refuses to
write.

This converts "did we parse this 1999 on-disk format correctly?" from an
assumption into a checked precondition, validated against a filesystem already
known to be good.

## Operations

- `alloc_frags(n)` allocates whole 8-fragment blocks except for a file's tail,
  matching UFS policy. Any other packing would be internally legal but would
  leave fragment accounting that disagrees with what the kernel and fsck
  expect.
- `alloc_inode(kind)` claims a free inode and bumps `cs_ndir` for
  directories; it does not touch the dinode itself, so callers zero it
  (`_zero_dinode`) before `write_inode` fills it in, and `free_inode` zeroes
  it again on release so a freed inode never leaves a stale `di_mode` (and
  stale block pointers) behind for fsck to trip over.
- `add_dirent(dir, name, ino, type)` walks the `reclen` chain looking for slack
  inside an existing entry — how UFS packs directories — and grows the
  directory only when no entry has room.
- `create_file`, `mkdir`, `grow`, `unlink` and `rmdir` compose those.

### Size bound

Twelve direct pointers reach 96KB; one single indirect block reaches **16MB**.
The allocator implements direct and single indirect, and refuses anything
larger with an error naming the limit, rather than silently producing a file the
kernel cannot read. Double indirect would reach 32GB but is unreachable on an
8GB filesystem; the structure leaves it additive.

For scale: `AHCI_reloc` is 82KB and `mach_kernel` is 1.4MB.

## Safety

Every refusal raises `SafetyError`. Three preconditions run before any write:

- **Never the master.** Refuse any target not under `vm/work`, and refuse any
  target that resolves by real path to `golden.img`. This checks the property
  that matters rather than a filename; `rhap_inject.check_target()` permits
  exactly `vm/work/test.img`, which constrains the name instead.
- **Geometry sanity.** Refuse on a bad magic, an unexpected `ncg`, or
  unrecognised geometry.
- **The `fs_cstotal` cross-check** described above.

Mutations are collected in five typed pending caches (cylinder-group headers,
the superblock, the summary table, dinode blocks, and file-content fragments)
and applied only after every step has succeeded, so a failure during
computation leaves the image byte-identical. This is not crash safety — nothing here is — but it means out of
space, directory full and oversized file cannot leave a half-allocated
filesystem. Every refusal happens before the first byte is written.

## Testing

**Unit tests on synthetic images.** `ufs_build.py` produces fixtures, and its
single-group limitation is not a problem at this tier: one group is enough to
exercise bitmaps, inode allocation and directory packing.

**A Python consistency checker** runs after every operation in the suite,
recomputing all five invariants from the raw bitmaps. It shares assumptions with
the code it checks, which is exactly why it is not the acceptance gate.

**Guest fsck is the gate.** Boot a modified image single-user and let
`/sbin/fsck` judge it. That verdict is not ours. It is newly available: the
image boots to userland with a kernel built from the current tree.

### The gap worth naming

Synthetic fixtures are single-group, so cylinder-group *selection* — choosing
among 510 groups and updating the right summary slot — is exercised only against
`golden.img` clones. That is the riskiest code and the least unit-testable, so
it carries the heaviest fsck scrutiny.

### Working images

This host is APFS, so `cp -c` uses `clonefile`: an 8GB work image clones
instantly and costs almost nothing until written. The tooling clones rather than
copies by default. Full copies previously accumulated to 320GB.

## Out of scope

- Crash safety or journalling.
- Double and triple indirect blocks (see the size bound).
- Multi-group support in `ufs_build.py`; it keeps its `ncg == 1` restriction.
- Any change to `rhap_inject.py`'s behaviour.

## Outcome

Task 8 could not reach the fsck gate. `install-driver.py` produced a clean
image (`ufs_check.check()` empty) after adding the AHCI bundle, and the
grafted kernel booted the loader correctly (`kaddr 100000`, `intbuf`-equivalent
`extmem 253876` matched expectations exactly). But under `run-q35-uefi.sh`
the boot-time standalone linker failed to link the AHCI driver itself:

```
Loading binary for AHCI device driver.
Error occurred while linking driver AHCI:
rld(): Undefined symbols:
_vm_page_size
Error linking AHCI device Driver.
...
boot drivers linked: 6
```

`vm_page_size` is referenced by `AHCIDiskInternal.m` and `AHCIPort.m` under
`src/drivers-i386/ide/drvAHCI` but is not resolvable by the boot-time linker's
symbol table, so the driver never configures, no disk is registered (q35 has
no legacy IDE at 0x1f0 for the kernel to fall back to), and `root on hd0a`
fails with `errno = 19`, dropping into the kernel's interactive
`root device?` retry loop. This is a driver-link/kernel-export gap, not a
filesystem-allocation defect, and is out of scope for this plan (no source
under `src/` was touched). The UFS allocator itself is not implicated: the
image it produced is clean by both the Python checker and by the loader
successfully reading and linking every other driver and the kernel image
from it. Guest fsck was never reached and remains outstanding.

Routing around the AHCI link failure via `run-pc-uefi-virtio-esp.sh` (PIIX
IDE, so the EIDE driver finds the disk instead) and a single-user loader
build reached the gate: root mounted and `/sbin/fsck -n /dev/hd0a` ran at a
single-user shell. That first run's verdict was **not clean** — Phase 1
reported systematic 2x block-count mismatches from low inode numbers up
and two unreferenced files, and Phase 5 reported the superblock free-block
count, bitmaps, and summary information all wrong. A control run against
an image with only the kernel graft applied (no `install-driver.py`, no
allocator writes) showed the block-count mismatches and unreferenced files
were absent there, isolating them as allocator bugs, while the link-count
and Phase 5 complaints reproduced identically with no allocator
involvement at all, isolating those as pre-existing artifacts of
`graft-kernel.py`/`rhap_inject`'s kernel graft.

Both allocator bugs were fixed in `vm/ufs_alloc.py`: `di_blocks` was
exactly 2x too large (wrong unit; corrected to `total_frags * g.nspf`),
and directory-entry record sizes omitted `DIRSIZ`'s "+1" for the name's
NUL terminator, undersizing entries whose name length was a multiple of 4
(e.g. "AHCI", "PostLoad") and causing the real kernel fsck to discard the
remainder of that directory block, orphaning everything after it.

Re-running the identical gate after both fixes: `INCORRECT BLOCK COUNT`
and `UNREF FILE` are now **gone** — captured via screendump every 0.5s
across the full `fsck -n` run with no gap between frames, so no output was
missed. The only complaints remaining are exactly the four pre-existing,
graft-caused ones identified by the control run (`UNKNOWN FILE
TYPE`/`BAD TYPE VALUE` on the graft donor inode, `LINK COUNT FILE
I=1253202`, and the three Phase 5 superblock/bitmap/summary complaints).
Nothing new appeared. By the narrow question this gate was designed to
answer — does the allocator produce a filesystem the guest's own fsck
accepts as correctly accounted — the allocator now passes. Full output and
analysis are in `.superpowers/sdd/task-8-report.md` under "fsck gate via
PIIX IDE", "fsck-found fixes", and "fsck gate re-run after fixes".
