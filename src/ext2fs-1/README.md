# ext2fs tools

The aggregate preserves the local mount Tool and builds e2fsprogs 1.35 with
private static support libraries. `apk/vendor` extracts the pristine release
and applies ordered patches before the Project Builder build. `src/Manifest`
includes `ext2fs-1 all`; the Rhapsody package version is 1.0 and its upstream
e2fsprogs version remains 1.35. The universal package uses `build-base`, which
already includes the required exported kernel headers. It has no kernel runtime
dependency, so formatting and checking regular images works without ext2fs
being enabled in the running kernel.

`ext2_tools/build-tools.sh SOURCE OBJECTS DSTROOT "RC_ARCHS"` uses a native
Rhapsody build machine, isolated per-CPU configure caches and staging roots,
and matching compiler/linker architecture flags. The build-machine subst
generator uses the actual build CPU. Target configure executables are never
run; verified 32-bit ABI sizes and endianness are supplied separately per CPU.
Each invocation replaces its private objects before building, and merges the
five installed programs only after every requested thin build succeeds.
The wrapper matches the patched generated `configure` timestamp to
`configure.in` before configuration, so patching across a filesystem timestamp
boundary does not request an unneeded autoconf regeneration. Their contents
remain the pinned release plus ordered patches. `make -C tests
check-configure-order VENDOR_SOURCE=/absolute/patched/vendor` exercises the
actual wrapper and the vendor make dependency without compiling the vendor.

Installed tools are `/sbin/{mke2fs,e2fsck,dumpe2fs,debugfs,tune2fs}`, their five
section-8 manuals, and the upstream/license notices under
`/usr/share/licenses/ext2fs`. Generic headers, support libraries, resizing
tools, and the upstream fsck dispatcher are not installed.

The default mke2fs profile is revision 1, 128-byte inodes, no compat features,
`filetype` incompat and `sparse_super` ro-compat. The initial kernel accepts
only revisions 0/1, 128-byte inodes, blocks of 1024/2048/4096 and those masks.
Explicit upstream options can create journals, htree directories, larger
inodes, or other advanced features; those images are outside this kernel's
supported profile. Debugfs can modify images without kernel validation.
The kernel limits individual files to 2147483647 bytes.

Device sizing requires the exported `dev/disk.h` selected-partition
`DKIOCGPARTINFO` ABI. Builds against older headers fail; devices on kernels
without that query are refused. Regular-file images remain supported.
The exact exported header is retained under `ext2_tools/include/dev`, keeping
the selected-partition ABI self-contained when rbuild stages the source.
`EXT2_CPPFLAGS` may supply additional private include flags for native tests.

Run `sh tests/smoke_tools.sh DSTROOT UNIQUE_TEST_DIRECTORY "i386 ppc"`
on the native guest to check versions, slices, exact payload and a disposable
labelled image. A missing CPU execution is an acceptance gate; a slice check
alone does not establish native execution on that CPU.

The native entry points are `newfs_ext2fs`, `fsck_ext2fs`, and
`/usr/filesystems/ext2fs.fs/ext2fs.util`. Commands are root-owned mode 0755,
with no setuid bit. The formatter defaults to 1024-byte blocks and 5 percent
reserved space, and explicitly selects revision 1, 128-byte inodes and masks
(0,2,1). It accepts only `-b`, a label of at most 16 bytes with `-L`, an integer
reserved percentage 0..50 with `-m`, and an optional block count. The checker
accepts mutually exclusive `-n`, `-y`, or `-p` plus `-f`/`-v`, preserving every
e2fsck exit bit. Both wrappers refuse mounted targets and failed inspection,
including unresolved or relative mount-table sources. Relative regular-file
image paths remain supported. Neither wrapper invokes a shell.

The helper follows `kernserv/loadable_fs.h`: `-p` returns recognized for a
supported volume, while `-P` returns initialization-recognized for the same
bounded read-only probe. Unsupported images and I/O failures retain their
respective protocol results; blank-media initialization capability is not
inferred. Device tokens follow existing partition-a conventions (`hd1` maps
to `/private/dev/hd1a` and `/private/dev/rhd1a`). `-m` honors readonly/writable,
refuses dirty writable mounts, and invokes mount directly; `-u` invokes
umount. `-r` explicitly requests preen repair and reports reboot advice;
`-i` invokes the formatter defaults. Repair errors remain unclean, while
operational/usage/cancellation/library failures map to I/O failure. There is
no automatic repair or forced-mount helper action. Successful probes write
`ext2fs.name` and the bounded label to `ext2fs.label` in the helper directory.

Autodiskmount probes ext2fs on its existing exposed partition-a candidate after
UFS, HFS banks, CD9660 and FAT. A candidate already classified by those paths
keeps that classification; a separate HFS bank does not claim partition-a.
NeXT partitions marked `p_newfs` are classified as UFS by the existing label
path without inspecting filesystem contents. Use an appropriate partition
label when preparing ext2 media; discovery does not rewrite labels or create
device nodes. Missing helpers, unsupported profiles and malformed media do
not trigger formatting or repair. A dirty supported volume can be recognized,
but its writable mount is refused until an explicit successful check/repair.

Use `/sbin/fsck_ext2fs -n -f /dev/rhd1a` directly for inspection, or explicitly
request repair with `/sbin/fsck_ext2fs -p /dev/rhd1a` on an unmounted volume.
The general `/sbin/fsck` dispatcher and bootstrap manifests are unchanged;
ext2 is not automatically checked through fstab. `COPYING` retains the GNU GPL
and GNU Library GPL texts; `LIBRARY-NOTICES` retains the individual private
library notices, and `NETBSD-NOTICES` retains the mount/helper BSD notices.
See `PROVENANCE.md` for pinned upstream sources, checksums and ordered patches.

`make -C tests check-tools` compiles production common and command code with
private compile-time child paths and test-only inspection providers. The
common codec sources are exact mirrors of the kernel codecs; host test
`test_shared_codec_matches` requires byte-for-byte equality. Refresh both
copies together. Tool projects compile against exported namespaced kernel
headers and do not depend on a sibling kernel source checkout.

This product includes software developed by Manuel Bouyer. The copied BSD
license is installed as `/usr/share/licenses/ext2fs/NETBSD-NOTICES`.

Before any formatter child starts, a read-only preflight establishes the
selected logical partition's 512/1024-byte sector capacity via DKIOCGPARTINFO.
Missing, invalid, whole-drive and old-kernel queries are refusals; no legacy
whole-drive query is used. Explicit counts cannot exceed device capacity.
Raw character targets receive internal -F to avoid upstream's block-only
prompt; the preflight still bounds them before execution. Existing regular
images may grow to an explicit size within checked native offset/block-address bounds.

The vendor I/O manager pads partial-sector reads and uses full-superblock
writes on Rhapsody. To exercise its actual production body after configuring
and generating a vendor build's headers, run `make -C tests check-vendor-io
VENDOR_SOURCE=/absolute/vendor VENDOR_OBJECTS=/absolute/objects
TEST_DIR=/absolute/fresh-tests`. The private providers verify issued offsets
and sizes, contents, partial reads, errors, callbacks and canaries. Set
`VENDOR_IO_ACTION=build` when linking a CPU that cannot execute on that guest.
