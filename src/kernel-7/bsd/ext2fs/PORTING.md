# Ext2 port state and exported disk contract

The pinned NetBSD import supports Rhapsody read and write operations.
Registration uses static type 18, the appended VT_EXT2FS tag, and explicit
normal/spec/FIFO vectors. Writable admission requires a supported clean
filesystem and a synchronously persisted dirty marker. Fault handling and
remount recovery are the following milestone.

## Imported units and adaptations

The ten independently compiled units are `ext2fs_alloc.c`, `ext2fs_balloc.c`,
`ext2fs_bmap.c`, `ext2fs_bswap.c`, `ext2fs_inode.c`, `ext2fs_lookup.c`,
`ext2fs_readwrite.c`, `ext2fs_subr.c`, `ext2fs_vfsops.c`, and `ext2fs_vnops.c`.
This matches the pinned `sys/ufs/files.ufs` manifest recorded in ORIGIN.
No implementation unit includes another. All original function boundaries
remain intact.

- Rename only upstream `ext2fs.h` to `ext2_fs.h`, and mechanically change the
  local disk/declaration includes to quoted filenames. Preserve readwrite as
  an independent compiled unit; the pinned vnops has no readwrite inclusion.
- Replace unavailable `machine/bswap.h` with local fixed-width inline swaps,
  retaining the upstream `h2fs*` / `fs2h*` accessor semantics. Native includes
  use target `sys/types.h`, `sys/cdefs.h`, and `machine/endian.h`; userland
  includes `string.h`, and kernel code includes `libkern/libkern.h`.
- Remove the unavailable `__KERNEL_RCSID` invocation in the portable swap unit
  (its original source RCS identifier and licence remain at the top). Guard
  `sys/systm.h` so the codec unit also compiles in userland.
- Preserve the full group/inode record with `memmove` before selectively
  swapping its scalars. Keep the original explicit block-byte copy. This
  retains reserved OS bytes, descriptor padding, and fast-symlink payloads.
  Use `memmove` in upstream load/save copy macros to support identical buffers.
- Add bounded superblock wrappers, unaligned LE accessors, and supported-profile
  admission in `ext2_disk.[ch]`. Compile-time assertions enforce 1024-byte
  superblocks, 128-byte inodes, and 32-byte descriptors.
- Add byte-numbered bitmap helpers returning the previous bit value. The
  caller owns bitmap-length validation, as with NetBSD's byte bitmap macros.
- `EXT2_PORTABLE_TEST` skips native platform includes only for the optional
  host type bridge. `EXT2_TEST_SWAP` compiles the same production swap routines
  on a little-endian test host; neither flag belongs in kernel builds.

## Exported includes and field conventions

Export `ext2_disk.h`, `ext2_fs.h`, `ext2fs_dinode.h`, `ext2fs_dir.h`, and
`ext2_bitmap.h` together in the ext2 namespace for later kernel/userland
consumers. Include `ext2_disk.h` to obtain the bounded codec interfaces and
all three disk structures. Do not export the generated option header under
this name and do not make `ext2fs_extern.h` part of the userland disk ABI.

`ext2_super_decode(raw, len, out)` accepts at least 1024 bytes, copies unaligned
input to an aligned record, and returns `EINVAL` on short or null input.
Decode leaves scalar fields in host order and opaque fields unchanged.
`ext2_super_encode(in, raw)` writes exactly 1024 bytes; identical input/output
storage is supported. UUID, volume label, mounted-on bytes, padding, and all
reserved bytes must survive. The caller supplies a sufficiently large output.

`e2fs_sbload`/`e2fs_sbsave`, `e2fs_cgload`/`e2fs_cgsave`, and
`e2fs_iload`/`e2fs_isave` remain the upstream conversion paths. Their structure
pointers must be aligned, and descriptor lengths must be bounded multiples of
32. Superblock/group/inode scalar metadata is host order after loading.
**Inode `e2di_blocks` stays disk-order bytes**, including device encodings and
fast-symlink payloads. At pointer use, convert once with `fs2h32`; writes use
`h2fs32`. Indirect buffers remain disk order until each pointer is used.
Do not cast an ext2 disk inode to the Rhapsody UFS disk inode.

Directory headers stay disk order. `ext2_get_le16/32` and
`ext2_put_le16/32` accept unaligned byte addresses; they are the production
path for reading/writing directory inode/reclen fields. Revision 0 has a
16-bit name length; the filetype format has separate name length/type bytes.
Directory record/name/length validation belongs to the subsequent read task.

`ext2_validate_super(es, device_bytes, writable)` admits only revisions 0/1,
128-byte inodes and first ordinary inode 11 for revision 1, block sizes
1024/2048/4096, compat/incompat/ro-compat masks `(0, 2, 1)`, and clean writable
volumes. Revision 0 ignores unused dynamic-revision inode-size/first-inode
fields: consumers must derive 128 and 11 for revision 0. It does not mutate
or normalize the superblock. Zero/unknown device size fails admission.

Geometry admission checks exponents before shifts, equal fragment/block
geometry, expected first-data block, full inode groups, bitmap capacity,
inode-table divisibility and fit, group/descriptor counts, descriptor-buffer
size, last-group metadata capacity, and signed 32-bit disk-sector conversion
before buffer allocation. Device size bounds the whole volume. Descriptor
bitmap/table **addresses** require separate validation after descriptor reads;
this superblock check cannot establish their locations or non-overlap.
The maximum supported file length is `EXT2_FILESIZE_MAX` (2147483647 bytes).

## Dependency and vector audit for subsequent adaptation

| Imported files | Dependencies requiring explicit Rhapsody review |
| --- | --- |
| alloc, balloc, bmap, subr | Shared UFS inode fields, buffer/cache API, `ufs_getlbns`, allocation error unwinding; balloc also imports UVM |
| inode | NetBSD dinode pointers, UFS inode update/truncation assumptions, `ufs_balloc_range`, `uvm_vnp_zerorange/setsize` |
| lookup | Name cache and vnode signatures; `ufs_dirbad`; filetype directory records and endian-safe accesses |
| vfsops | VFS vector layout, `MOUNT_EXT2FS`, root-mount and NFS/export callbacks, pools, locks, quota header, genfs/UVM, mount/reload geometry and descriptor reads |
| vnops and independent readwrite unit | Normal/spec/FIFO vectors, `ufs_*` reuse, vnode lock/reclaim, pools, UBC/genfs paging, mutation ordering and byte-order access |
| extern header | NetBSD pools, signatures and callbacks; private kernel header only |

The normal vector inherits UFS close/lease/ioctl/fcntl/poll/revoke/mmap/seek,
abort/lock/unlock/strategy/print/islocked/pathconf helpers, and genfs page and
kqueue operations. Spec/FIFO vectors also inherit UFS wrappers and foreign
poll/kqueue/page callbacks. Each must be checked against Rhapsody inode,
buffer, vnode, and Mach pager invariants before registration. Unsupported
quota, NFS/export, root-mount, and NetBSD paging callbacks must be replaced or
rejected, not silently inherited. No shared UFS source was changed here.

The imported `cg_has_sb` power loop is not safe for arbitrary large group
numbers; admission's sparse-last-group calculation uses bounded division.
Any later use of that imported helper must receive its own overflow audit.
Imported mount/reload arithmetic is still unadapted; callers must invoke the
bounded validator before deriving geometry or allocating metadata buffers.

## Tests and pending evidence

`make -C src/kernel-7/bsd/ext2fs/tests check` compiles the production sources
against native exported headers. The five named disk cases cover profile,
short input, geometry, metadata byte order, and bitmap boundaries. A separate
direct-swap test exercises reserved-byte preservation, including aliased
buffers, on either host byte order. Independently authored little-endian
fixtures cover scalars and encoded bytes, rather than Python codec substitutes.

For a portable Windows run, use the available GCC and
`CPPFLAGS='-include host_compat.h' EXE=.exe`, with a GCC-version-appropriate
`CFLAGS`. The host bridge provides only standard-width BSD type spellings and
host endian constants: all production disk structures/codecs remain in use.
A host direct-swap result does not supply a PPC execution result. Per-CPU
native results are recorded in the task report; missing PPC evidence remains
an acceptance gate. No filesystem mount/runtime evidence is claimed here.

## Task 2 native dependency audit

Shared UFS source changes are limited to one pointer in each existing union.
The union size and shared inode/mount layout remain unchanged. ext2fs_node
places the unchanged inode first, followed by the private ext2 disk snapshot.
M_MISCFSNODE allocates/frees that node; M_UFSMNT owns mounts, superblocks,
group descriptors and the ext2-only inode hash. VGET interprets its void pointer
argument as the historical inode-number value, never dereferences it.

| Reused local helper | Audit / ext2 assumptions |
| --- | --- |
| ufs_start | Returns success, no FFS metadata access. |
| ufs_getlbns | Uses only um_nindir and inode indirect geometry; same 12/3 pointers. |
| ufs_access | Invoked only after ext2 rejects VWRITE, so QUOTA getinoquota is unreachable; uses canonical mode/UID/GID. |
| ufs_vinit | Uses canonical mode/rdev, checkalias and locks; returned alias is retagged VT_EXT2FS. No i_fs read. |
| ufs_lock/unlock/islocked | Uses canonical inode lock and vnode interlock, not disk metadata. |
| ufs_strategy | Uses i_devvp and calls the ext2 VOP_BMAP; no FFS geometry. |
| ufs_abortop | Releases native namei buffer; no inode/disk access. |
| ufs_select/mmap/seek/pathconf | Constant/generic vnode answers, no i_fs dereference. |
| ufs_advlock | Uses inode lockf and canonical i_size. |
| ufs_revoke | Local alias for generic vop_revoke. |
| ufs_pagein/pageout | Native pass-through to VOP_READ/VOP_WRITE, which select ext2 buffered read/write. |

Do not use ufs_close or ufs_ioctl: both can interpret i_fs as FFS. Do not
use shared UFS reclaim/hash: ext2 owns a separate hash and allocation class.
Do not use ufs_inactive because truncation and timestamp policy differ.
Spec/FIFO I/O uses local spec/fifo functions directly, with ext2 metadata
operations and inactive/free handling; no ufsspec/ufsfifo wrappers. No quota or export implementation
is linked from ext2. NFS handles and quota callbacks return EOPNOTSUPP.

Active NetBSD algorithms retained in their own units: ext2fs_bmap and
ext2fs_bmaparray retain direct/indirect traversal and ufs_getlbns; ext2fs_read
uses the upstream buffered loop for all types; ext2fs_lookup retains the
linear scan, cached directory offset, parent/child locking and native
VOP_BLKATOFF dispatch; ext2fs_readdir retains entry-by-entry conversion;
ext2fs_blkatoff retains buffer-cache reads. Bounds are checked before device
block access; directory errors return EIO instead of panicking or repairing
metadata on an RO mount. Native cache_lookup has incompatible reference and
locking semantics, so the initial path uses the uncached scan. Read hardening
and comprehensive corrupt-image coverage remain the next task.

The vnode vectors, mount lifecycle and inode load/save are ABI-specific
replacements. ext2fs_update(struct vop_update_args *) delegates to
ext2fs_update_inode(vnode,timeval,timeval,wait). Four-argument VOP_UPDATE,
VOP_TRUNCATE, VOP_VALLOC and VOP_VFREE use the local dispatch descriptors;
mutation entries use the native descriptors. Imported UVM/UBC paths are
replaced by native buffered I/O and pager size updates; the original UVM
range-allocation helper remains guarded. Unsupported NetBSD
VFS scaffolding remains guarded; no compatibility macro silently ignores
its behavior. All ten imported C units compile independently.

Original allocation, block allocation, directory mutation, truncate/free,
inactive, and buffered write algorithms are active in their original units.
VFS/vnode dispatch and lifecycle code use the native ABI.
The private dinode retains ext2-only scalars and raw little-endian block
bytes. Metadata aliases name local canonical i_din fields; block/ext2 flag
access uses ext2fs_dinode explicitly. No disk-record casting is used.

Mount admission uses DKIOCGPARTINFO from exported bsd/dev/disk.h. Its fixed
eight-byte disk_partition_info contains u_int32_t block_size/block_count;
ioctl number 29 was unused. The selected logical partition supplies these
values in bsd/dev/ata_hd_registry.m, bsd/dev/SCSIDiskKern.m and
bsd/dev/ppc/drvATADisk/ATADiskKernel.m. Live, absent, zero, out-of-signed-32-bit
range, and whole-drive-sized or larger capacities are rejected. The last
check deliberately excludes DriverKit's unlabelled partition-zero fallback:
supported NeXT/APM partitions have label/front overhead. It compares checked
64-bit byte products; partition offsets remain governed by existing I/O.
No label parser or device-name inference is added to ext2 or its tools.

Legacy DKIOCBLKSIZE/DKIOCNUMBLKS retain their existing UFS/FAT/HFS behavior;
they often describe the physical drive and cannot bound a NeXT partition.
Native partition_info tests assert both new and legacy results on block/raw
512/1024-byte NeXT partitions plus live, unavailable, equal and oversized
refusals. Exposed HFS paths require per-CPU runtime evidence as recorded in
the report; cross-compilation is not execution. Existing UFS image tests and
shared-header layout comparisons cover the unchanged UFS structures.
Older kernels without the new query fail mount cleanly. The current ext2
buffer mapping admits 512-byte device sectors only. RO mount/sync/unmount
issue no superblock, dirty-bit, inode timestamp or free-map writes.
Registration has no root-mount callback.

The first superblock read uses ext2_read_super in ext2_disk.c. Its production
gate requires at least four 512-byte sectors before invoking the reader for
bytes 1024..2047. The callback must return all bytes or an errno; the VFS
adapter rejects residual data and releases the buffer on success or failure.
Disk tests count this actual callback boundary, including zero calls for
capacities 0..3 and one contained call at four sectors. The later userland
codec mirror must include this helper and retain the same parity checks.

## Task 3 read validation

The local ufs_getlbns geometry is compatible: NDADDR=12, NIADDR=3 and
um_nindir=block_size/4 (256/512/1024). Its largest third-level block count
is 1024^3=1073741824, within the local signed int; admitted file offsets
are bounded by 2147483647. The native bmap test compiles the actual shared
ufs_bmap.c alongside the ext2 mapper and checks the first single/double
paths at all block sizes and the 1 KiB triple path at logical block 65804.
No shared FFS source or constants change.

Inode and indirect pointers remain disk-order bytes until fs2h32 at use.
Contiguous run hints stop before an out-of-volume pointer; successful short
indirect-buffer reads return EIO before interpreting pointers. Native tests
count the mapper's buffer/device boundary and require no device read for
an invalid inode pointer, one contained metadata read for an invalid data
pointer, and buffer release on errors. Those test boundaries substitute
only process accounting and device buffers, not geometry or traversal.

Directory conversion/validation, inode load/save, root-inode selection,
spec/FIFO vectors and vnode locking were established in Task 2 and retained.
Task 3 adds EINVAL when a nonempty getdirentries buffer cannot hold its first
entry, preserving the directory offset instead of falsely reporting EOF.
Syscall suites check both directory layouts, the full 255-byte name, repeated
lookups, short/long readlink, sparse content and indirect boundary bytes.
PPC cross-builds are recorded separately from unavailable PPC executions;
native admission of truncated partitions is not a short inode-read test.

## Task 4 write integration

Canonical mode, links, ownership, size, timestamps and block count remain in
local inode.i_din. ext2fs_dinode accesses ext2-only fields and little-endian
block pointers; allocation locality hints belong to the private ext2fs_node.
The internal ext2fs_alloc and ext2fs_balloc signatures are unchanged.
Vnode allocation, free and truncate take their typed native vop arguments.
Metadata writes pass through ext2fs_inode_save, preserving the disk adapter.

ext2fs_vget_alloc is a private allocation admission path called only after
the allocator reserves a free inode bitmap bit. It admits an uninitialized
on-disk inode and defers vnode type initialization until ext2fs_makeinode or
mkdir installs the mode. The allocator clears both private and canonical
records; failed admission returns the reservation through VOP_VFREE. Normal
ext2fs_vget still rejects zero mode/link count, oversize files and unsupported
regular-file high size. Lookup and malformed-image admission use that normal
path. Local successful symlink/mknod callers consume no returned reference:
those ext2 methods release their newly created vnode before returning.

The original buffered write loop serves regular files and long symlinks.
The local ufs_pagein/pageout wrappers dispatch through ext2 VOP_READ/WRITE;
ext2fs_vm_flush enrolls an existing user pager in MapFS before flushing or
truncating it. Initial enrollment uses paired map_vnode/unmap_vnode; an
already mapped cache with map_count zero gains no new reference. vmp_get/put
hold the recursive native cache lock and use count while the active
vmp_push_range walks the entire file object, including hardware-dirty user
pages outside the kernel I/O window. Busy or missing-object state and prior
or immediate push errors fail the operation; cleanup preserves the first
error while the same live cache remains. mapfs_trunc coordinates mapped
truncate before changing inode blocks. getattr uses the local UFS live-size
rule for enrolled cache; inode.i_din remains serialization authority. Native
vnode_pager_setsize follows the local UFS mapped-vnode guard. Sparse
truncate growth changes size without allocating holes; shrink zeros an
allocated partial tail before releasing blocks. Growth past 2147483647 is
EFBIG. A crossing write is rejected entirely. ENOSPC after successful bytes
returns that prefix through the native syscall layer; IO_UNIT rolls back.

Writes do not use cluster_write, so close needs no FFS cluster-flush adapter.
ext2fs_fsync first pushes user pages, then drains native vnode dirty buffers
and serializes inode metadata.
Mount sync traverses native vnode locks, flushes the device, and updates group
counts and the superblock. Paged regular vnodes participate even without
inode flags or dirty buffers, so mapped-only stores reach final flush. Successful unmount flushes/reclaims all vnodes,
flushes allocation metadata, then persists the clean marker and flushes the
device again. RO lifecycle stays write-free. Mode-changing remounts are refused
before either NULL-fspec or same-device update success (RO-to-RW EROFS,
RW-to-RO EOPNOTSUPP), pending Task 5's transition and error-latch work.
The one-pointer mount ABI has no export payload. NULL-device update requests
use the native export route and return EOPNOTSUPP after mode-change guards;
generic mount strips the user MNT_EXPORTED flag before calling the filesystem.
Named-device same-mode updates remain supported. Quota is EOPNOTSUPP.

Shared UFS implementations, structures and FFS block geometry are unchanged.
The dependency audit now includes kern/mapfs.c: enrolled ordinary I/O bypasses
ext2 VOP_WRITE, and the generic overflow check precedes its append adjustment.
A real native append returned two bytes and size2147483648 while the disk inode
remained2147483646. The ext2-only guard computes the effective write offset
before mapfs_get can remap, and checks offset/residual with subtraction against
EXT2_FILESIZE_MAX. It returns EFBIG without consuming bytes. It is conditional
on EXT2FS and VT_EXT2FS write requests; other filesystem paths retain their
existing checks and behavior. The generated ext2fs.h controls inclusion of
the authoritative ext2_disk.h limit. Required regressions are enabled and
disabled kernel compile/link on both CPUs, actual ext2 mapped append/ordinary
crossing/truncate/count tests, and native UFS mapped bounded append/read. The ext2 access method implements
native owner/group/other permissions without linking the UFS quota path.
Native FIFO and special-device operations use their existing local vectors.

The native test case is mmap-fsync: generic fsync first calls mapfs_fsync,
then the ext2 VOP_FSYNC. The supplied system library lacks msync and the
kernel syscall is unimplemented; the original msync case remains a separately
recorded unsupported platform capability, not a successful ext2 test.

Existing-block allocation reads reject successful-short buffers before
returning data or decoding indirect pointers. Decoded indirect data pointers
must be below the filesystem block count before full-block getblk overwrites
can bypass bmap. The native balloc test compiles production allocation and
shared UFS geometry, controlling only buffer I/O and unused allocation hooks;
it checks exact buffer ownership and no write/allocation after refusal.
