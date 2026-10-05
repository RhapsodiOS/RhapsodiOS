# FreeBSD ext2 filesystem and tools

## Goal and agreed package boundary

Add read/write ext2 data-volume support to RhapsodiOS on i386 and PowerPC.
Users can format a supported volume, mount it, manipulate files, unmount it,
check or repair it, and inspect its metadata with native tools.

The user selected the same split used by the FreeBSD FAT port:

- Filesystem core code belongs in `src/kernel-7/bsd/ext2fs/` and is compiled
  into the kernel.
- User-space tools belong in `src/ext2fs-1/`, producing the `ext2fs` APK.

Installing or upgrading the tools does not install filesystem code. Runtime
mounting requires a kernel built with ext2 support. The tools package can still
format, inspect, and check unmounted images without kernel ext2 support.

This document is the design specification. The implementation plan follows
review of this file; no filesystem source or build configuration has been
changed as part of writing the design.

## Scope

The first version supports local ext2 data volumes, ordinary files and
directories, links, ownership and permissions, sparse files, truncation,
rename, synchronous persistence, and read-only/read-write mounting.

The tools are `mount_ext2fs`, `mke2fs`, `e2fsck`, `dumpe2fs`, `debugfs`, and
`tune2fs`, plus `newfs_ext2fs`, `fsck_ext2fs`, and an `ext2fs.util` helper
following the existing filesystem packages. The helper and small
`autodiskmount` integration provide the same discovery and mount path as FAT.

Root-volume booting, ext3 journal replay, ext4 extensions, online resizing,
quotas, NFS export, and a general filesystem-checker dispatcher are outside
this version. Unsupported kernel operations return the appropriate existing
BSD error rather than inheriting an unsafe UFS implementation.

## Source baselines and provenance

Use FreeBSD **4.11-RELEASE**, matching the FAT port's recorded upstream source,
rather than an unspecified point on the 4.x branch:

- Tag: `release/4.11.0`.
- Resolved commit: `a84f9c8c4d27b7ce34314e6eed0a53ace0abe1dd`.
- Core sources: `sys/gnu/ext2fs/`.
- Mount helper: `sbin/mount_ext2fs/`.
- The upstream `sys/modules/ext2fs/Makefile` supplies the initial core source
  inventory, not the Rhapsody build mechanism.

The core inventory includes `ext2_alloc.c`, `ext2_balloc.c`, `ext2_inode.c`,
`ext2_inode_cnv.c`, `ext2_linux_balloc.c`, `ext2_linux_ialloc.c`,
`ext2_lookup.c`, `ext2_subr.c`, `ext2_vfsops.c`, and `ext2_vnops.c`, together
with their required local headers. Import auxiliary files only where actually
included or compiled; avoid compiling included implementation fragments twice.

Use e2fsprogs **1.35** for the formatter, checker, and inspection tools:

- Tag: `E2FSPROGS-1_35`.
- Commit: `e55043f87678587a03895d9629efb1c5a659d392`.
- Keep its upstream source archive pristine and apply an ordered patch series
  through `rbuild`'s existing `apk/vendor` mechanism.
- Record the release archive's checksum when importing it. Check its archive
  layout against the existing vendor extractor before committing the input.

Each import records origins, immutable revisions, checksums, and local
adaptations. Retain `COPYRIGHT.INFO`, original file notices, and e2fsprogs
`COPYING`. FreeBSD's ext2 tree contains both Berkeley-licensed and GPL code;
its provenance must not be described as uniformly BSD. Record applicable
terms for the imported files and the kernel distribution as part of the
source inventory. The tools package retains e2fsprogs' GPL notices and its
libraries' individual notices.

Primary references:

- [FreeBSD release core](https://github.com/freebsd/freebsd-src/tree/release/4.11.0/sys/gnu/ext2fs)
- [FreeBSD ext2 source list](https://github.com/freebsd/freebsd-src/blob/release/4.11.0/sys/modules/ext2fs/Makefile)
- [FreeBSD copyright inventory](https://github.com/freebsd/freebsd-src/blob/release/4.11.0/sys/gnu/ext2fs/COPYRIGHT.INFO)
- [e2fsprogs 1.35](https://github.com/tytso/e2fsprogs/tree/E2FSPROGS-1_35)

## Kernel integration

### Build and registration

Add an `EXT2FS` option to `src/kernel-7/conf/MASTER`, with the matching
`OPTIONS/ext2fs` and conditional source entries in `conf/files`. Enable it in
the normal i386 and PPC configurations using the existing option-selection
pattern. Add the necessary header directory to `conf/Makefile.template`.

Register the filesystem name `ext2fs`, its VFS operations, and its normal,
special-device, and FIFO vnode vectors in `bsd/vfs/vfs_conf.c`. Use filesystem
type number 18, the next unused static number after HFS (17) in the current
table. Existing static numbers remain unchanged; dynamically loaded filesystems
continue to obtain their numbers from `maxvfsconf`. Append `VT_EXT2FS` to the
vnode-tag enumeration without renumbering existing tags. Registration has
`MNT_LOCAL` and no root-mount callback.

Replace FreeBSD `VFS_SET`, `VNODEOP_SET`, module events, and allocator
declarations with Rhapsody's static registration and existing allocation
interfaces. There is no kernel-server product, load command, unload path, or
change to `vfsconf_add()` or `vfsconf_del()`.

### VFS, UFS, and memory interfaces

FreeBSD's ext2 implementation depends on UFS in-memory inode and mount
structures, shared vnode operations, and block-mapping helpers. Preserve that
approach where the local code is compatible rather than replacing the whole
filesystem or importing FreeBSD's UFS subsystem.

Add an ext2 superblock pointer to the existing inode and mount unions, with
forward declarations and ext2 accessors. Audit each reused `ufs_*` operation
for assumptions about FFS disk structures, byte order, vnode tags, and
filesystem-specific callbacks. Keep ext2-specific adaptations in the new
directory; change shared UFS helpers only when their existing interface cannot
serve the port, with UFS regression coverage for each such change.

Adapt the VFS vector to the actual `bsd/sys/mount.h` layout and signatures.
Use Rhapsody's vnode descriptors, name cache, locks, credentials, buffer
cache, and Mach pager integration. FreeBSD's `cachedlookup`, `getpages`,
`putpages`, VM-zone, and module interfaces cannot be copied unchanged.
Validate cached reads, writes, and mappings against the existing FFS/HFS
patterns. Shared code must never interpret ext2 metadata as an FFS superblock.

Keep the mount argument structure in a small exported header, shared with
`mount_ext2fs`. Its device name and mount flags are interpreted using
Rhapsody's mount syscall ABI, not an unverified FreeBSD structure layout.

### Byte order and allocation

Ext2 disk metadata is little-endian. Define explicit disk-to-host and
host-to-disk accessors and use them for superblocks, group descriptors,
inodes, directory entries, and indirect block pointers. Maintain host-order
in-memory metadata and convert at I/O boundaries. Preserve fast-symlink bytes
as bytes rather than treating their contents as block pointers.

Use portable bitmap operations with ext2's byte and bit numbering. Replace
i386-only assembly dependencies for PPC; a simple C implementation is the
default until measurements justify architecture-specific code. Exercise both
allocation and release across word and block-group boundaries.

## Disk-format contract

Supported volumes use ext2 revision 0 or 1, 128-byte inodes, and 1024-, 2048-,
or 4096-byte blocks. Revision 1 uses first ordinary inode 11. Support the
directory-entry `filetype` feature and `sparse_super`; initially allow no
other optional feature bits. Both revision-0 and revision-1 directory layouts
must work on both CPUs.

The first implementation uses a conservative file-size limit of
`2 GiB - 1 byte` and rejects writable large-file-feature volumes. Do not
advertise the disk format's theoretical maximum volume size: validate all
geometry and block-to-sector arithmetic against the actual target types and
device size. Reject overflow, invalid inode sizes, unsupported revisions,
out-of-range metadata, and unsupported features before attempting writes.

Reject journaled volumes, including ones requiring journal recovery. Never
clear unsupported bits merely to make a mount succeed. The tools may inspect
other formats supported by their upstream implementation, but the documented
RhapsodiOS data-volume profile is this narrower contract.

`newfs_ext2fs` creates that profile explicitly, with revision 1, 128-byte
inodes, and only the allowed features. Patch the packaged `mke2fs` defaults
to the same profile. `newfs_ext2fs` rejects options outside it; advanced
upstream tools retain their documented capabilities and make clear that those
capabilities can exceed kernel support. The kernel remains authoritative for
mount admission.

## User-space package

`src/ext2fs-1/` contains the aggregate project, mount and filesystem-helper
subprojects, an e2fsprogs build wrapper, `apk/pkginfo`, `apk/vendor`, source
archive, patches, provenance, manuals, and tests. Follow `pb_makefiles` for
the local tools and the existing GNU-source build conventions for e2fsprogs.

Build e2fsprogs independently for each CPU with architecture-specific
configuration and object directories. Merge installable Mach-O tools using
the existing universal-build conventions. Link the needed e2fsprogs libraries
statically into the tools; keep generic library names and developer headers
private to the build. Preserve the target compiler's generated configure
results and avoid executing cross-architecture probes.

| Product | Installation and behavior |
| --- | --- |
| `mount_ext2fs` | `/sbin`; supports `mount -t ext2fs` through the existing external-helper search, read-only mounting, and valid mount updates. |
| `newfs_ext2fs` | `/sbin`; small wrapper enforcing the supported disk profile and translating the documented native command interface. |
| `mke2fs` | `/sbin`; upstream formatter with compatible defaults. |
| `fsck_ext2fs` | `/sbin`; adapter to `e2fsck`, with documented flags and result semantics. |
| `e2fsck` | `/sbin`; upstream checker and offline repair tool. |
| `dumpe2fs`, `debugfs`, `tune2fs` | `/sbin`; upstream inspection and maintenance tools. |
| `ext2fs.util` | `/usr/filesystems/ext2fs.fs/ext2fs.util`; probe, label, mount, unmount, repair, and initialize actions using `kernserv/loadable_fs.h` conventions. |

Use ordinary root-owned executable permissions consistent with the tool's
needs. Do not inherit HFS's setuid installation setting without a demonstrated
requirement. Probe and inspection operations are read-only. Format and repair
operations reject a mounted target, accounting for block/raw device aliases.
Invoke child tools with argument vectors, propagate status, and translate
helper results to the existing `FSUR_*` protocol.

Patch e2fsprogs only for demonstrated Rhapsody compiler, libc, device-size,
mounted-device detection, installation, and byte-order differences. Use its
existing static support libraries rather than adding system-wide library
packages. Exclude tools outside the product table from the installed payload.

Add `ext2fs-1` to `src/Manifest`. Package metadata follows current `rbuild`
rules: default universal userland output, `build-base` build dependencies,
verified licenses, and no architecture-specific kernel payload. Bootstrap
manifests need no ext2 entry because ext2 is not required to bootstrap.

## Discovery, errors, and persistence

Add the ext2 filesystem name and probe/mount dispatch to `autodiskmount` using
the FAT pattern. Reuse the current exposed device/partition candidates; do
not add a partition-table parser or an ext2-specific synthetic device name.
The helper recognizes only a supported ext2 volume and reports its label
through the existing filesystem-helper protocol. Without installed tools,
automatic discovery does not try to run a nonexistent ext2 helper.

The current `/sbin/fsck` checks UFS and is not a filesystem dispatcher.
`fsck_ext2fs` is invoked directly or through `ext2fs.util`. Fstab mounting uses
the type `ext2fs`, but setting an fstab check pass does not imply automatic
ext2 checking by the current UFS checker. Document the direct check workflow.

Writable mounts require a clean supported filesystem. Mark it unclean before
accepting mutations, flush data and metadata according to existing BSD sync
semantics, and mark it clean only after successful final unmount writes.
Propagate buffer I/O failures and prevent a failed sync from producing a clean
state. Failed mount attempts unwind allocations and vnode references. Busy
unmounts preserve the live mount. Neither mounting nor discovery performs
silent repair; offline `e2fsck` owns recovery.

## Verification and acceptance

Use disposable data images and private boot-image copies for all guest tests.
Keep source-build evidence separate from runtime evidence; compiling a PPC
slice does not establish correct PPC byte order or allocation behavior.

1. **Build integration:** i386 and PPC kernels link with `EXT2FS` enabled;
   configurations with it disabled also build. The universal tools APK has
   both CPU slices, expected paths, manuals, notices, and no kernel binary or
   unintended generic library installation.
2. **Format and admission:** both guest architectures format volumes that an
   independent host e2fsck accepts. Exercise revision 0/1, all three block
   sizes, filetype on/off, and sparse-super on/off. Verify malformed geometry,
   unsupported features, and 256-byte inodes fail without changing the image.
3. **Reads and writes:** test directories, long names, short and long symlinks,
   hard links, ownership, modes, timestamps, sparse files, overwrite,
   truncation, rename, unlink of open files, and allocation across group
   boundaries. Exercise direct, single-, double-, and triple-indirect mapping
   within the supported file-size limit, plus mmap and ordinary buffered I/O.
4. **Persistence and interoperability:** after guest writes and a clean
   unmount, independent e2fsck reports no unexpected repairs and file contents
   match host expectations. Read again after reboot. Exchange the same test
   images between i386, PPC, and the independent checker.
5. **Failures and recovery:** exercise block and inode exhaustion, oversized
   writes, injected data/metadata I/O errors, and interrupted writable sessions
   on disposable images. An unclean volume is refused for normal writable
   mounting; offline repair restores consistency and permits remounting.
6. **Integration and regressions:** validate `mount -t ext2fs`, direct
   `fsck_ext2fs`, helper return codes and label handling, automatic discovery,
   and operation with the tools absent. Re-run relevant UFS tests for changes
   to shared inode, mount, block mapping, or vnode code, plus FAT/HFS mount
   smoke tests on the changed kernel.

Completion requires recorded native read/write and cold-remount evidence on
both CPUs, supported-profile format/check agreement, and passing regressions
for shared kernel code. If one guest is unavailable, record the unverified
architecture explicitly and leave that acceptance requirement open.

## Implementation sequence

The detailed implementation plan will order work as follows:

1. Import and document pinned sources, dependency inventory, and format limits.
2. Add kernel structures and static build/registration wiring.
3. Establish validated read-only mounting and metadata byte-order handling.
4. Port allocation, writes, truncation, sync, and failure handling.
5. Build the upstream tools and native wrappers for both CPUs.
6. Add filesystem-helper discovery and package-manifest integration.
7. Run interoperability, recovery, regression, and package acceptance checks.

These stages are milestones toward the agreed read/write scope. Read-only
operation is an intermediate verification point, not the final deliverable.
