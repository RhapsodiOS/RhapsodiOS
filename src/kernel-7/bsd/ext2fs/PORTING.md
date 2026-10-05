# Ext2 port state and exported disk contract

This task imports the pinned NetBSD core and establishes disk codecs. The
filesystem remains disabled: no kernel configuration, registration, UFS union,
mount ABI, tools project, or package manifest is changed. The imported VFS and
vnode implementations still depend on NetBSD interfaces and must not be
compiled into Rhapsody until those adaptations are completed. ORIGIN records
all upstream files, immutable URLs, pristine checksums, and preserved notices.

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
