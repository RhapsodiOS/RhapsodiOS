# HFS tools for i386

## Goal

Port the rest of `src/hfs-1` to i386, as `mount_hfs` was on the `hfs-endian`
branch (merged as `a3e168ea6`):

- `hfs_newfs` (`newfs_hfs`): formats HFS and HFS Plus volumes.
- `hfs_util` (`hfs.util`): the Workspace's probe and mount helper.
- `hfs_glue` (`VDI-interface`): the Volume/Directory ID library.

Done means all three build for i386 in the `hfs` package, ppc builds and
behaves as before, and the two tools that touch the disk are verified on the
QEMU i386 guest:

- `newfs_hfs` formats HFS, HFS Plus and 8K-block HFS Plus volumes that the host
  checker finds consistent, and that the i386 kernel then mounts, writes and
  reads back cold.
- `hfs.util -p` reports the right volume name for built HFS, HFS Plus, wrapped
  and 8K volumes, the Apple volume in `devtools.toast`, and every volume
  `newfs_hfs` made.
- `hfs_glue` builds.

## Out of scope

- Partitions whose label says 1024-byte sectors (the kernel port's scope limit).
- ppc runs. The ppc box is unreachable, so ppc gets a cross-build on the i386
  guest only.
- `hfs.util`'s mount and unmount actions (the kernel does that work) and its
  `kl_com` kernel-server loading: the kernel's built-in HFS is tried first.
- `hfs_glue` behaviour beyond building.

## Approach

HFS is big-endian on disk. Both tools follow the Apple sources that made the
same change:

- `newfs_hfs` follows diskdev_cmds-143 `newfs_hfs.tproj/makehfs.c`. Structures
  written once are built big-endian directly, a field at a time
  (`x = SWAP_BE32(v)`): B-tree node descriptors, header records, map words,
  record offsets and the root catalog records. The MDB and volume header,
  which the formatter keeps using for its layout arithmetic, stay in host order
  and are swapped as a whole around the `WriteToDisk` calls that write them,
  as `makehfs.c` does with `SWAP_HFSMDB` and `SWAP_HFSPLUSVH`.
- `hfs.util` follows hfs-226.1.1 `hfs_util/hfsutil_main.c`: every field read
  off the device is swapped where it is read (`SWAP_BE16(p->x)`), and the HFS
  Plus root name is swapped into a copy before conversion to UTF-8. (hfs-116's
  `hfs.util` has no byte-order handling; it predates Intel Macs.)

On ppc the macros are identities and the whole-structure swaps are empty, so
ppc builds as before.

Rejected: building in host order and swapping whole structures before each
`write()` (needs a userland copy of the kernel's node swapper, and
`newfs_hfs` reads its own structures back after building them); replacing the
formatter (throws away Apple's code).

## Components

### Byte-order header

`hfs_newfs/hfs_endian.h` and `hfs_util/hfs_endian.h`, identical to
`hfs_mount/hfs_endian.h`: `SWAP_BE16` and `SWAP_BE32` over
`NXSwapBigShortToHost` and `NXSwapBigLongToHost`. Each subproject gets its own
copy, since each is its own pb_makefiles project; each is added to its
`Makefile` `HFILES` and `PB.project` `H_FILES`.

### newfs_hfs

`hfs_newfs/HFSVolumeInit.c`. The MDB (`InitMasterDirectoryBlock`) and the
HFS Plus volume header (`InitVolumeHeader`) stay in host order and are swapped
as a whole around the two `WriteToDisk` calls that write each (primary and
spare copy), by static routines copied from the kernel's `hfs_swap_MDB` and
`hfs_swap_VolumeHeader`. Every store into a field of:

- the B-tree header record (`InitBTreeHeader`), node descriptors, and the
  record offsets `SetOffset` writes;
- catalog keys and records for the root folder and its thread
  (`SetupCatalogRecords`, `InitRootFolder`), including HFS Plus Unicode name
  lengths and characters;
- map-node descriptors (`WriteMapNodes`);
- allocation bitmap words (`InitBitmap`, `MarkBitInAllocationBuffer`).

FinderInfo, Pascal strings and single bytes are left alone.

### hfs.util

`hfs_util/hfsutil_main.c`. Every field read off the device: the MDB's
`drSigWord`, `drEmbedSigWord`, `drAlBlkSiz`, `drAlBlSt`, `drEmbedExtent`; the
volume header's `signature`, `blockSize`, catalog and extents fork extents;
the B-tree header fields it uses (`firstLeafNode`, `nodeSize`); the catalog
leaf key and record fields it walks to find the volume name; the extent
arithmetic in `CalcFirstLeafNodeOffset`.

### hfs_glue

No code change. It reaches volumes only through system calls such as
`getattrlist`, and FinderInfo arrives big-endian, as on Mac OS X.

### Build

Remove `INCLUDED_ARCHS = ppc` (and the comment above it) from the three
subproject `Makefile.preamble`s, so the whole `hfs` package builds for i386.
All edits to existing sources go through `tools/latin1_replace.py` and are
checked with `git diff | cat -A` for indentation and whitespace changes.

## Testing

### Build

Build `hfs-1` with `rbuild buildpackage --toolchain gcc-darwin-i386.conf
--arch i386` on the guest (its dependencies are built the same way first) and
cross-build it for ppc. Fetch the thin i386 `newfs_hfs` and `hfs.util`; the
results disk carries them beside `mount_hfs`.

### Harness modes

New modes in `vm/hfs_guest.py`, one boot each:

- **`probe IMG`**: the guest runs `hfs.util -p rhd1a removable writable`
  (a five-character device argument, so it opens `/dev/rhd1a` rather than an
  `_hfs_a` node) and records its exit status and
  `/usr/filesystems/hfs.fs/hfs.label` (the directory is made first; `golden.img`
  has none). Pass: `FSUR_MOUNT_HIDDEN` (-9, exit status 247), which is what
  `DoProbe` returns once it has the name, and a label equal to the volume name
  the host reads from the image.
- **`newfs FLAVOUR`**: the host supplies a zeroed disk with the usual 512-byte
  NeXT label. The guest runs `newfs_hfs -H -v NAME /dev/rhd1a` (HFS),
  `newfs_hfs -v NAME /dev/rhd1a` (HFS Plus) or `newfs_hfs -b 8192 -v NAME
  /dev/rhd1a` (8K HFS Plus). The host checker must find the volume consistent,
  with the right name, type and block size and an empty root. In the same
  boot the guest mounts it and runs a fresh-volume write scenario: a folder,
  150 small files, a 20 MB file, and two files grown in turn so the kernel
  inserts extents-overflow records. The host then checks the structure and
  every file's contents, and a cold `reread` boot reads it back.

Host-side unit tests (written first) cover the new guest scripts and the
fresh-volume expected tree.

## Risks

- **A missed field.** With about a hundred swap sites, one can be missed. The
  host checker reads every structure `newfs_hfs` writes; the probe test reads
  every name path `hfs.util` walks.
- **`newfs_hfs` defaults.** Its HFS Plus default may create a wrapped volume.
  The newfs test records what it made rather than assuming.
- **Device size.** `newfs_hfs` gets the size from the raw device (`/dev/rhd1a`);
  with the 512-byte label the partition size is the label's.
