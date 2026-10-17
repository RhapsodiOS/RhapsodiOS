# HAMMER filesystem for RhapsodiOS

## Intent

RhapsodiOS needs a crash-safe, high-performance filesystem with a modern
on-disk design, so that a crash costs a quick recovery at mount instead of a
long `fsck`. UFS and HFS give neither.

The user chose to **port DragonFly BSD's HAMMER (version 1)** and cut it down to
a **single volume with a single namespace**. PFS (pseudo-filesystems),
mirroring and multi-volume are removed. Offline dedup is kept. What remains is HAMMER's core
architecture: a B+tree holding all filesystem records, transaction IDs on every
record, an UNDO FIFO that makes crashes recoverable, and retained history with
a pruner and snapshots on top.

The point is a filesystem designed **for Rhapsody**. The DragonFly code is the
starting material, not something kept in sync with upstream.

### Why HAMMER rather than XFS

XFS v4 was considered first (via FreeBSD's old GPL port) and dropped. Recorded
here so the reasons aren't lost:

| | HAMMER1 (this design) | XFS v4 (rejected) |
| --- | --- | --- |
| License | BSD 3-clause. Kernel-clean. | GPLv2 in an APSL/BSD kernel. |
| Kernel source | ~1.0 MB, ~0.9 MB after removals | ~3.0 MB plus a shim |
| Integrity checks | CRC on B-tree nodes, records and volume header | None (CRCs arrived in v5) |
| Crash recovery | UNDO FIFO replay at mount | Log replay at mount |
| History/snapshots | Built in | None |
| Reference system | DragonFly BSD, which ships HAMMER1 today and runs in QEMU | Linux, whose current kernels compile v4 out by default |
| Boot reader | BSD reader exists (`stand/lib/hammer1.c`) | None usable |
| Byte order | Little-endian only, no swapping code. **ppc needs work.** | Big-endian with swap macros |
| VFS distance | DragonFly namecache VOPs: further from Rhapsody | FreeBSD 9 VOPs: closer |
| Costs | History needs a pruner; designed for big disks; uses more memory | Mature large-file performance |

Both need a native buffer layer (see below), and both need their OS glue
rewritten.

## Goals

The user's feature list, staged:

1. **Disk format and block allocator.** Format, mount, unmount, volume-header checks.
2. **B+tree.** Insert, lookup, delete, split, recovery.
3. **Objects and inodes.** Create files and read inode metadata.
4. **Directories.** Lookup, create, mkdir, readdir.
5. **File data.** Read, write, truncate.
6. **UNDO transactions** that make crashes recoverable.
7. **History.** Superseded records are kept by transaction ID.
8. **Cleaner/pruner** that reclaims obsolete history.
9. **Snapshots** that pin transaction IDs and expose historical state.
10. **Root filesystem**, only after substantial torture testing.

## Non-goals

- PFS (master or slave), mirroring streams, `mirror-*` commands.
- Multiple volumes. No volume add/remove; the volume count must be 1.
- Live (write-time) dedup. It is experimental and off by default upstream, and
  stays off and unsupported here *(my call)*. Offline dedup **is** supported
  (Phase 4).
- HAMMER2.
- NFS export, quotas, extended attributes, `chflags` beyond what the core
  already stores.
- `autodiskmount` / filesystem-helper discovery. Deferred until writes are
  trusted.
- Staying merge-compatible with DragonFly's source. A **disk** made by DragonFly
  (single volume, root PFS only) should stay mountable, but the code is ours to
  reshape.

## Anti-goals

- Never write to a volume the code doesn't fully understand. Wrong version,
  more than one volume, non-root PFS data present on a read-write mount, a CRC
  failure, or a failed volume-header check all mean refusal, never "mount and
  hope".
- Never silently repair.
- Never test on `vm/rhap-i386-bootstrapped-v2.img` itself (see CLAUDE.md).
- Never let a ppc and an i386 build disagree on what's on disk.

## Source baselines and provenance

DragonFly BSD `master`, pinned to commit
`4e10f78d03f3d76c5bbe99c5d65022a03ea21e2e`. The last change to `sys/vfs/hammer`
before that was `30436b52c8f4` (2026-09-01).

| Upstream | Size | Destination |
| --- | --- | --- |
| `sys/vfs/hammer/` (32 files) | ~1.0 MB | `src/kernel-7/bsd/hammer/` |
| `sbin/newfs_hammer/` | ~28 KB | `src/hammer-1/` |
| `sbin/mount_hammer/` | ~11 KB | `src/hammer-1/` |
| `sbin/hammer/` (subset, see below) | ~437 KB in total | `src/hammer-1/` |
| `stand/lib/hammer1.c` | Phase 5 only | booter, later |

All of it is BSD 3-clause (The DragonFly Project / Matthew Dillon). Keep every
upstream notice. New RhapsodiOS files use the same BSD 3-clause text with a
RhapsodiOS copyright line *(my call, to keep the directory under one license)*.
Record origin, commit, per-file SHA256 and local changes in `bsd/hammer/ORIGIN`
and `PORTING.md`, as `bsd/ext2fs/` does. The first import commit is
byte-identical to upstream, and adaptations go in later commits.

**Files removed from the kernel import:** `hammer_pfs.c`, `hammer_volume.c`
(volume add/remove). `hammer_mirror.c` is cut down to the
`HAMMERIOC_MIRROR_READ` scan that `hammer dedup` uses, restricted to PFS 0; the
mirror-write side goes. Code in the remaining
files that only serves those features is cut as files get adapted.
**Kept:** blockmap, btree, cursor, dedup, inode, object, ondisk, io, flusher,
transaction, undo, recover, redo, prune, reblock, rebalance, ioctl (subset),
subs, signal, vfsops, vnops.

**`hammer(8)` subset:** `info`, `show`, `blockmap`, `history`, `snapshot`/
`snapls`/`snaprm`, `prune`/`prune-everything`, `reblock*`, `rebalance`,
`cleanup`, `config`, `recover`, `synctid`, `version`, `checkmap`,
`show-undo`, `dedup`, `dedup-simulate`. (`checkmap` and `show-undo` are the
consistency checker, see below.) Dropped: `pfs-*`,
`mirror-*`, `volume-*`, `strip`, remote/ssh mirroring.

## On-disk format

- **HAMMER version 7** (DragonFly's current default), unchanged. A single-volume
  volume made by DragonFly `newfs_hammer` mounts here, and ours mounts on
  DragonFly. This is what makes DragonFly usable as the reference system.
- **Single namespace:** B-tree keys keep their 32-bit `localization` field.
  The top 16 bits (the PFS id) are always 0. Code paths that select or iterate
  PFSes are removed. Mount refuses a volume whose `vol_count != 1`. Read-write
  mount refuses a volume containing records outside PFS 0. *(My call: read-only
  mounts may ignore other PFSes and expose only the root.)*
- **Byte order: little-endian on disk, on every CPU.** HAMMER1 has no swapping
  code anywhere (it assumes x86). Every on-disk structure access (volume header,
  blockmap layers, B-tree nodes and elements, records, data, UNDO/REDO entries)
  must go through accessors that are free on i386 and swap on ppc. CRCs are
  computed over the on-disk (LE) bytes. This is the single largest ppc cost in
  the project. The builder picks the technique, e.g. load/store at buffer
  boundaries as ext2fs does for inodes, or accessor macros on each field, and
  records it in `PORTING.md`. Host tests must catch missing **and** double swaps.
- Offsets are 64-bit (`hammer_off_t`, with the zone in the top 4 bits).
  Rhapsody's block numbers are 32-bit 512-byte sectors, so volumes are limited to
  what `daddr_t` can address. Validate and refuse anything larger.
- Small volumes: HAMMER allocates in 8 MB big-blocks and reserves an UNDO FIFO
  (up to 128 big-blocks). DragonFly warns that small volumes are not
  recommended. `newfs_hammer` here keeps a sensible minimum, and test images
  should be at least a few GB. *(My call: test sizes are 2–8 GB. The builder
  measures overhead and records the practical minimum.)*

## Kernel integration

Follow the ext2fs pattern (see
`docs/superpowers/specs/2026-10-05-ext2fs-design.md` and
`src/kernel-7/bsd/ext2fs/PORTING.md`):

- `options HAMMER # <hammer>` in `conf/MASTER`, `OPTIONS/hammer` and `optional
  hammer` lines in `conf/files`, and `hammer` added to the RELEASE/DEBUG lists in
  `MASTER.i386` and `MASTER.ppc`. Builds with it off must still work.
- `vfs_conf.c`: `{ &hammer_vfsops, "hammer", 19, 0, MNT_LOCAL, NULL, NULL }`
  under `#if HAMMER` (19 is the next free static number). Append `VT_HAMMER`
  to the vnode-tag enum. Use its own `M_HAMMER*` malloc types. There is no
  mountroot until Phase 5.
- Device size comes from the `DKIOCGPARTINFO` query added for ext2fs.

### What has to be rewritten

HAMMER is written against DragonFly kernel APIs that Rhapsody (4.4BSD-Lite /
Darwin 0.3) lacks. Rough counts from the source: ~140 LWKT token uses, ~85
`struct bio`/`bio_*` uses, ~44 namecache-style `vop_n*` operations, plus
`cluster_*`, `objcache` and `kmalloc` limits.

- **Buffers: the biggest design problem.** HAMMER does metadata I/O in
  16 KB buffers and large data in 64 KB buffers. Rhapsody's `MAXBSIZE` is 8 KB
  and `MAXPHYS` is 64 KB. `hammer_io.c` drives DragonFly's buffer cache with
  dependency callbacks and ordering. It must become a HAMMER-owned buffer layer
  that allocates its own memory and issues device I/O through `VOP_STRATEGY`,
  splitting at `MAXPHYS`. It must keep HAMMER's write-ordering rules: data and
  UNDO before meta-data, and the volume header last. Do not raise `MAXBSIZE`
  globally. Record the design in `PORTING.md`.
- **Vnode operations.** DragonFly's namecache VOPs (`nresolve`, `ncreate`,
  `nmkdir`, `nremove`, `nrename`, ...) are rewritten as 4.4BSD
  `componentname`/`namei` VOPs (`lookup`, `create`, `mkdir`, `remove`,
  `rename`, ...). The HAMMER logic underneath (`hammer_object.c`,
  `hammer_inode.c`) stays.
- **Locking.** LWKT tokens and HAMMER's own locks map onto Rhapsody's
  `simple_lock`/`lockmgr` model. The BSD side of this kernel is effectively
  uniprocessor, but HAMMER's locks still order work between its flusher and
  callers, so they become real locks, not no-ops.
- **Threads.** The flusher and its workers become Mach kernel threads.
- **Memory.** `kmalloc` limits and `objcache` become `malloc` with explicit
  limits. HAMMER keeps a lot in memory (inodes, in-memory records), so it
  must run on a **128 MB** guest without exhausting kernel memory (acceptance
  test). Tune the limits to RAM size.
- **Paging.** Use `vnode_pager_setsize` and the existing buffered I/O pattern.
  There is no UBC or `cluster_*`, so drop clustering.

## User-space package

`src/hammer-1/` follows `src/ext2fs-1`: a Project Builder aggregate, `apk/`
metadata, `PROVENANCE.md`, tests and man pages. Products: `newfs_hammer` and
`mount_hammer` in `/sbin`, and the `hammer` subset in `/sbin`. These are native
sources, not a vendor archive, since they are BSD code we adapt directly. They
share the on-disk header and the byte-order accessors with the kernel (one
copy, exported like the ext2fs headers). Add the project to `src/Manifest`.
Universal i386+ppc build.

**Nightly cleanup (user's decision):** the package installs a nightly
`hammer cleanup` run from `/etc/daily`, so retained history never fills a
volume on its own. Each volume gets DragonFly's default retention config on
first run: daily snapshots kept 60 days; daily prune, rebalance and reblock
and dedup with 5-minute budgets; monthly recopy with a 10-minute budget. The
dedup step joins the shipped schedule in Phase 4. Users change it with
`hammer config`.

## Phases and acceptance

All guest testing uses snapshot or throwaway images, its own ports and
`-name`, and QMP-only shutdown, per CLAUDE.md. Test volumes are separate disk
images attached as a second drive.

**Consistency check** *(my call)*: HAMMER1 has no `fsck`. "A check with no
findings" means our ported `hammer show` (B-tree and CRC walk) plus
`hammer checkmap` (B-tree against freemap) report nothing, run on the
Rhapsody guest itself, so crash loops need only one guest. Every Nth
iteration, and at each phase sign-off, the same volume is also checked on
DragonFly. `hammer recover` is a salvage tool, not a checker.

**Reference system:** a DragonFly BSD QEMU guest, a recent release that ships
HAMMER1, set up with the same isolation rules. The user approved downloading a
DragonFly install ISO from dragonflybsd.org. Confirm the exact file and size
with the user at download time. Kept under `vm/` and never committed. It makes and fills reference
volumes, reads back volumes we wrote, and runs `hammer` inspection on them.
*(My call: this replaces the Linux reference the XFS draft needed.)*

### Phase 1: read-only mount (goals 1–4, 5 read)

- Import, provenance, removals, kernel builds with `HAMMER` on and off for
  both CPUs.
- `mount -t hammer -o ro` works. Reference volumes made and filled on
  DragonFly read correctly: small and large directories (B-tree splits on
  several levels), small and large files, sparse files, short and long
  symlinks, hard links, ownership, modes and timestamps, and a volume deduplicated on DragonFly
  (shared data blocks). Contents are compared
  against checksums recorded on DragonFly.
- CRCs are verified on read, and a corrupted node or record returns EIO without a
  panic.
- Refusals: wrong version, a 2-volume volume, a corrupted volume header, and a
  volume needing UNDO recovery (Phase 3 adds recovery). None of them change the
  image (hash before and after).
- 100 repeated mount/unmount cycles leak nothing measurable.
- `newfs_hammer` and `hammer info/show` build for both CPUs. Our
  `newfs_hammer` output mounts read-only on DragonFly and here.
- Existing UFS/ext2/HFS smoke tests still pass on the new kernel.

### Phase 2: read-write (goals 2–6)

- Writes go through HAMMER transactions, the flusher and the UNDO FIFO. There is
  no mode that skips UNDO.
- Create, write, append, overwrite, truncate (shrink and grow), rename, unlink
  of open files, mkdir/rmdir, hard links and symlinks. Large directories and
  files force B-tree splits and deletions that rebalance.
- After clean unmount, DragonFly mounts the volume and `hammer show` /
  `hammer recover` find nothing wrong, and DragonFly reads the files back
  identically.
- History is retained, as the format requires. `hammer history` lists the
  versions.
- ENOSPC leaves a consistent volume.
- `mount_hammer -u` handles ro↔rw.

### Phase 3: recovery, pruner and stress (goals 6, 8)

- **Read-only mounts of a volume needing recovery** *(my call)*: follow
  upstream. UNDO is replayed into memory, buffers stay dirty and unwritten, and
  they are flushed only when the mount is upgraded to read-write, so `-o ro`
  never changes the image. Phase 5 root (mount ro, then upgrade) relies on
  this. The HAMMER buffer layer must support pinned, unflushable buffers. If
  the recovered set exceeds a memory cap, the read-only mount is refused with a
  clear message rather than exhausting kernel memory. The builder sets and
  records the cap.
- UNDO recovery at mount on both CPUs, including recovery of volumes DragonFly
  left mid-flush. REDO is replayed if present.
- Crash testing: QMP `quit` and blkdebug fault injection mid-workload, then
  remount (recovery) and a check with no findings. Many iterations with
  randomized timing.
- **Pruner and reblocker**: `hammer prune`, `reblock*`, `rebalance` and
  `cleanup` reclaim space. A stress run with history on reaches a steady state
  instead of filling the disk. These are heavy B-tree mutators and are
  crash-tested like any other workload. Steady state is measured with the
  shipped nightly `cleanup` schedule (accelerated in the test harness), not
  with hand-run commands.
- Concurrency torture on both CPUs for hours (fsstress-like, builder's choice
  to port or write), with no panics, deadlocks or check findings.
- Runs on a 128 MB guest.

### Phase 4: history and snapshots exposed (goals 7, 9)

- `hammer snapshot`/`snapls`/`snaprm` pin transaction IDs, and the pruner
  respects them.
- As-of access: DragonFly's `@@0x<tid>` path syntax (or a mount option) gives a
  read-only view of any retained state. Historical views are read-only.
- Interop: snapshots made on DragonFly are visible here, and the reverse.
- **Offline dedup:** `hammer dedup` and `dedup-simulate` work. A deduplicated
  volume passes `show` + `checkmap`, and deleting one of the sharing files frees
  nothing until the last reference goes (blockmap accounting goes negative as
  upstream intends). Dedup is crash-tested like the pruner. DragonFly reads our
  deduplicated volumes identically.

### Phase 5: root filesystem (goal 10)

Designed separately, only after Phase 3 has passed and Phase 4 has had real use.
Constraints known now: i386 boot2 has about 64 bytes of headroom, so it cannot
grow a HAMMER reader. Root-on-HAMMER needs a UFS boot partition or the UEFI
booter, using `stand/lib/hammer1.c` as the reader. Mountroot and
`fsck`-less boot (recovery at mount) also need design.

## Left to the builder

- The byte-order technique (record it).
- The HAMMER buffer layer against `MAXBSIZE` (record it).
- The token→lock mapping and flusher thread model.
- Memory limits and their scaling.
- How non-root-PFS records are detected for the read-write refusal.
- Whether REDO is generated, or only replayed.
- Torture tool choice. The DragonFly release used for reference.
- Commit granularity, within CLAUDE.md's commit rules.

## ppc evidence (user's decision)

No ppc runtime currently exists (the ppc box is down and there is no QEMU ppc
path). As with ext2fs, a phase closes on i386 runtime evidence plus ppc
kernel and tool builds and host-side byte-order tests that run the swap
accessors in both directions. Missing ppc runtime evidence is recorded as an
open item in `PORTING.md` for each phase, and is run when a ppc runtime exists.
"All tests on both CPUs" elsewhere in this document is read with that rule.
