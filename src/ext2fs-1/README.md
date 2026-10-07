# ext2fs tools

The aggregate preserves the local mount Tool and builds e2fsprogs 1.35 with
private static support libraries. `apk/vendor` extracts the pristine release
and applies ordered patches before the Project Builder build. World-manifest
integration is deferred to the filesystem-discovery milestone.

`ext2_tools/build-tools.sh SOURCE OBJECTS DSTROOT "RC_ARCHS"` uses a native
Rhapsody build machine, isolated per-CPU configure caches and staging roots,
and matching compiler/linker architecture flags. The build-machine subst
generator uses the actual build CPU. Target configure executables are never
run; verified 32-bit ABI sizes and endianness are supplied separately per CPU.
Each invocation replaces its private objects before building, and merges the
five installed programs only after every requested thin build succeeds.

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
