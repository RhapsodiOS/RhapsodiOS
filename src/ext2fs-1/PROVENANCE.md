# Mount helper provenance

NetBSD netbsd-2-0 snapshot c90afb5a84a9c36a5c076093afade8e63ed2b6a9,
`sbin/mount_ext2fs/`, BSD licensed notices retained in each file.

| Original file | SHA-256 before adaptation |
| --- | --- |
| mount_ext2fs.c | dfdab885e0ddb778c3f600d295fa5cd57c3c06e5fb17f26bbf988b68c9057ad7 |
| mount_ext2fs.8 | 050261940683e2590e18bc3ad414977ff4378152457763f3e90e9a886fcf68f1 |

Native mount uses the exported one-pointer ext2fs_args and local flag values.
The unavailable NetBSD getmntopts and GETARGS/NODEVMTIME options are not
carried over. Unknown options are refused before the mount syscall.
The mount Tool subproject is retained alongside the private e2fsprogs build.


# Vendored e2fsprogs tools

Pristine official e2fsprogs 1.35 release archive (28-Feb-2004), downloaded
from https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/1.35/e2fsprogs-1.35.tar.gz.
SHA-256: `c8688b34a4bbd12ce8c4fad04693ff7a72e8663a82fcf5f1ec212aa3a43c0177`
(3,152,299 bytes). This is a computed digest of the official archive;
no maintainer-published SHA-256 manifest was found. The detached historical
DSA signature remains **UNVERIFIED (NO_PUBKEY)**, not an authenticated digest.

Pinned upstream tag E2FSPROGS-1_35 resolves to
`e55043f87678587a03895d9629efb1c5a659d392`. The release archive is not
byte-identical to a Git tag archive: nine shared files have only expanded
RCS/SCCS keywords; RELEASE-NOTES has four typo corrections. The archive
adds e2fsprogs.spec, while Git-only .cvsignore, .hgtags, README.subset, TODO,
and Makefile.pq files are excluded by upstream release generation.
All other 887 shared regular files match exactly. Generated configure is
release material and matches the pinned tag.

The archive has one e2fsprogs-1.35 root, 898 regular files and 114 directories;
no links, special files, traversal, duplicate regular names or case collisions.
Most files are mode 0444; the 17 executable release files below are 0555.
Directory modes are 0755/0775. The pristine tar preserves all original
notices and modes. apk/vendor extracts to e2fsprogs and applies the named
patch series at level 1, in filename order. No expanded tree is tracked.

- `e2fsck/mtrace.awk`
- `config.guess`
- `util/gcc-wall-cleanup`
- `install-sh`
- `.fix-Changelog`
- `contrib/dconf`
- `install-utils/compile_manpages`
- `install-utils/remove_preformat_manpages`
- `install-utils/convfstab`
- `mkinstalldirs`
- `configure`
- `.head-Changelog`
- `debian/rules`
- `config.rpath`
- `config.sub`
- `.missing-copyright`
- `tests/test_script.in`

Patch order:

1. `001-rhapsody.patch`: release configure and its input avoid target execution
   for Rhapsody; the wrapper seeds verified 32-bit ABI sizes and target endian
   separately. The subst generator uses build-machine flags. Device sizing
   consumes the exported selected-partition DKIOCGPARTINFO and refuses legacy
   device fallback; both fields must be positive and at most 0x7fffffff,
   matching the actual driver contract. Regular files remain supported with
   checked block counts, including empty files with an explicit formatter size.
   Mount checks use getmntinfo without mutating its table, preserve mount flags,
   and match device identity and raw/block aliases without parsing labels.
   mke2fs defaults to revision 1, inode size 128, compat=0, filetype and
   sparse_super; explicitly requested upstream advanced features remain available.

2. `002-rhapsody-printf.patch`: Rhapsody stdio's BSD quad (`q`) modifier
   replaces unsupported C99 `ll` only for the selected checker/debugger output
   sites, through EXT2FS_LLFMT. Other targets retain `ll`. Native fixtures
   demonstrated truncated 64-bit diagnostics and shifted block-range arguments
   before this patch. No libc or shared-source repair is involved.

3. `003-rhapsody-sector-io.patch`: the existing Rhapsody target macro selects
   the vendor sector-bounce read path and full-superblock write fallback.
   Short reads preserve the aligned prefix, copy only available logical
   fragment bytes, zero the remainder and report the delivered byte count.
   Private native tests include the actual patched I/O module and cover
   aligned requests, content, short/error callbacks and buffer boundaries.

COPYING carries the GPL v2 and GNU Library GPL v2 text. LIBRARY-NOTICES
retains verbatim copyright/permission headers from the six private support
libraries (ext2fs, e2p, com_err, ss, uuid, blkid), plus the com_err documentation
permission notice. Both are installed under /usr/share/licenses/ext2fs.
Generic library archives and headers remain exclusively in the private objects.

The private exported `ext2_tools/include/dev/disk.h` is an exact copy of
`src/kernel-7/bsd/dev/disk.h` at reviewed kernel commit
`aa77c6012a7f13050ec44e426022f58750dda423`, SHA-256
`f59b3b30e5544b177f3cd9a4a6a7f683ea6346302540fff3e425d206daa70806`.
It is never installed. Its type layout is two u_int32_t fields at offsets
0/4 (size 8), ioctl `_IOR('d',29,struct disk_partition_info)`. This scoped
include avoids shadowing the vendored ext2fs headers or changing the SDK.
Refresh the exact export when the authoritative ABI changes.
