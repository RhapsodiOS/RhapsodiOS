# FFS, buffer cache and mapfs: comparison and measurements

Evidence for `docs/superpowers/specs/2026-10-05-ffs-stall-corruption-design.md`
and its plan, `docs/superpowers/plans/2026-10-05-ffs-stall-corruption.md`.

## Measurements

Measured with `vm/ffsbench.py` on a private QEMU guest (i386, TCG, 128 MB,
`rhap-i386-bootstrapped.img` under snapshot). Each run gets:

- a fresh 1 GB scratch disk, newfs'd once with the installed root's geometry
  (`newfs -u 63 -t 16 -c 16`);
- the same read-only workload disk.

**Workload.** The replay repeats the four build roots `rbuild kernel` populates:
driverkit, drivertools, kernload and kernel. That is 119 dependency installs from
36 apks, 12 MB compressed. As rbuild does, each apk is extracted once to validate
it, then extracted again, copied into its root, and the stage removed.

- `replay.list` sha256: `4d478b9be8959caf9a6e191a662ae71cadf8e4d912eaaa486fd4069ab2c9a5e3`.
- The apks' hashes are in `vm/work/ffsbench/apks.sha256` (not committed).

**Stock kernel.** Master `478344e34`, built `Mon Oct  5 22:00:53 PDT 2026`. It
reports "using 391 buffers containing 2.55 megabytes of memory" at boot.

(Baseline rows follow when the stock campaign finishes.)

## Comparison

**References.**

| Name | Version | Location |
|---|---|---|
| FreeBSD | `releng/4.11` | `F:\ref\freebsd-4.11-sys` |
| NetBSD | `netbsd-2` | `F:\ref\netbsd-2-sys` |
| xnu | 124.13 | `F:\xnu-124.13` |

The FreeBSD and NetBSD files were fetched one by one from their GitHub mirrors,
because a Windows checkout fails on reserved names (`com1.c`) and on `:` in paths.
NetBSD 2.0 has no `vfs_cluster.c` (it uses genfs/UBC) and no dirhash.

**Line numbers.** "Ours" is `src/CoreOS/kernel-7` at `478344e34`. Reference files use
`sys/...` paths. FreeBSD is FB, NetBSD is NB, xnu is X.

**Classes.**
- *bug fix:* our behaviour can corrupt data or hang the system.
- *performance:* it costs time or responsiveness only.
- *irrelevant:* a difference that changes neither.

### vfs_bio.c

| Ours | References | Class | Why |
|---|---|---|---|
| `getblk` miss path, `vfs_bio.c:601`: `getnewbuf`, then `binshash`, then `allocbuf`; `b_lblkno` and `bgetvp` come only after `allocbuf` | FB `vfs_bio.c:2274-2296`: after `getnewbuf`, `if (gbincore(vp, blkno)) { B_INVAL; brelse; goto loop; }`, with a comment describing this exact race. NB `vfs_bio.c:1023-1031`: `binshash`, `b_lblkno` and `bgetvp` are all set at `splbio` *before* `allocbuf`. X `vfs_bio.c` `getblk`: same order as ours, no re-check | bug fix | `getnewbuf` can sleep (its `bawrite` reaches `VOP_STRATEGY` → `VOP_BMAP` → `bread`), and so can `allocbuf` (its own `getnewbuf` loop). Meanwhile `incore()` cannot see the half-built buffer (stale `b_vp`/`b_lblkno`), so a second `getblk` of the same block builds a second buffer. Two copies of an inode, directory or superblock block are then modified independently, and the last write wins. Spec finding 1; Task 10. |
| `getnewbuf`, `vfs_bio.c:803`: a delayed-write victim is `bawrite`n and the function loops to `start`, then returns a buffer to a caller that has not re-checked anything | NB `vfs_bio.c:1199-1214`: "If buffer was a delayed write, start it and return NULL (since we might sleep while starting the write)"; the caller retries from `incore`. FB: dirty buffers live on `QUEUE_DIRTY`, `buf_daemon`/`flushbufqueues` (`vfs_bio.c:1830`, `1899`) write them, and `getnewbuf` never starts a write itself. X: same as ours | bug fix (with row 1) / performance | With the cache full of delayed writes, one caller queues writes for the whole free list, one loop at a time, and every other process needing a buffer waits behind that disk queue (spec finding 3). Task 10 makes it safe; Task 14 bounds it. |
| `allocbuf`, `vfs_bio.c:686`: `while ((nbp = getnewbuf(0, 0)) == NULL) ;` steals pages from other buffers while holding the caller's busy buffer | NB `vfs_bio.c:1083`: memory from `buf_malloc`, never from other buffers. FB `vfs_bio.c:2373`: VMIO pages or `bufspace` kva; `geteblk` (`vfs_bio.c:2349`) has the same loop, but FB's `getnewbuf` sleeps on `needsbuffer` inside | performance (hang candidate) | Each NULL return comes back from a `tsleep` in `getnewbuf`, so this is not a pure spin. But several processes can each hold one busy buffer while waiting for pages owned by the others (spec finding 2). Task 11. |
| `bdwrite`, `vfs_bio.c:446`: no limit on dirty buffers | FB `bdwrite` (`vfs_bio.c:824`) wakes `buf_daemon` through `bd_wakeup`, and `bwillwrite` (`vfs_bio.c:988`) blocks a writer at `hidirtybuffers = nbuf/4 + 20` (`vfs_bio.c:430`). NB 2.0 `bdwrite` (`vfs_bio.c:747`): no limit | performance | The dirty share of the cache is unbounded, which feeds row 2. Task 15. |
| `bwrite`, `vfs_bio.c:366`: no limit on writes in flight | FB `waitrunningbufspace` (`vfs_bio.c:295`): async writers sleep while `runningbufspace > hirunningspace` (1 MB, `vfs_bio.c:415`). NB 2.0: none | performance | A short disk queue lets a reader (sshd, an exec page-in) get in between a writer's requests. Task 15. |
| Cache size, `machdep/i386/unix_startup.c:128`: `bufpages = mem_size / 50` (2%; 391 buffers, 2.55 MB on 128 MB) | NB: `BUFCACHE` defaults to 15% of RAM (`vfs_bio.c:106-111`). FB: `nbuf` scaled from physmem, `maxbufspace = nbuf * BKVASIZE` (`vfs_bio.c:410`) | performance | With MACH_NBC, file data does not use this cache, so it holds metadata only. But a metadata-heavy replay overruns 2.5 MB at once. Task 13. |

### ufs / ffs write paths

| Ours | References | Class | Why |
|---|---|---|---|
| `ufs_setattr` utimes, `ufs_vnops.c:492`: `VOP_UPDATE(vp, &atimeval, &mtimeval, 1)` (synchronous) | FB: `UFS_UPDATE(vp, 0)`. NB: `VOP_UPDATE(vp, …, 0)` | performance | `pax -pe` sets times on every file, so this is one synchronous inode write per file that neither reference makes. Task 16. |
| `ufs_makeinode`, `ufs_vnops.c:2187`: `VOP_UPDATE(tvp, …, 1)` before `ufs_direnter` | FB: `UFS_UPDATE(tvp, !(DOINGSOFTDEP(tvp) \| DOINGASYNC(tvp)))`, synchronous without soft updates. NB: `VOP_UPDATE(tvp, NULL, NULL, UPDATE_DIROP)`, synchronous unless the mount is async | irrelevant | Same ordering as both references without soft updates. It keeps a crash repairable. |
| `ufs_direnter2`, `ufs_lookup.c:864-973`: `VOP_BWRITE` | FB `ufs_direnter`: `bdwrite` only for async mounts, otherwise `bwrite` when not soft updates. NB: same shape | irrelevant | Same as above. |

### kern/mapfs.c and the MACH_NBC hooks

None of the three references has `mapfs`. xnu-124.13 had already replaced it with
UBC.

| Ours | xnu-124.13 | Class | Why |
|---|---|---|---|
| `mapfs_trunc`, `kern/mapfs.c:623`: for a mapped file, unmaps the window past the new end and runs `vno_flush` on `[size, vnode_size)`. For an unmapped one, only records the size | `ubc_setsize` (`bsd/kern/ubc_subr.c:243`): always invalidates `[trunc_page(nsize), round_page(osize))` through `memory_object_lock_request`, and flushes the partial last page | candidate (unconfirmed) | `unmap_vnode` keeps a file mapped while it has links (`mapfs.c:473-483`), so "unmapped" means never mapped or freed. But a resident page left past EOF before `ffs_truncate` frees the blocks could later be pushed onto a reused block. Task 8's `ffsdebug: page past truncation` checks exactly this. |
| Object offset = file offset (`remap_vnode`, `mapfs.c:564`: `vm_allocate_with_pager(..., vmp->pager, offset)` with `offset = trunc_page(start)`) | UBC: same convention | irrelevant | Recorded because the Task 8 check depends on it. |
