# instmedia's UFS writer

`vm/instmedia/` writes UFS filesystems and NeXT `dlV3` labels on the Windows
host. It works from an in-memory tree of nodes, and lays everything out as
Rhapsody's `newfs` and `disk -i` would. It is phase 3 of the install-media
design (`docs/superpowers/specs/2026-09-22-install-media-design.md`), and
the live-root builder in phase 4 is its first user.

| Module | Job |
|---|---|
| `ufs_geometry.py` | `newfs`'s geometry arithmetic, ported from `mkfs()` in `src/Commands/diskdev_cmds/newfs.tproj/mkfs.c` with `newfs.c`'s defaults |
| `label.py` | Encodes a label and writes its copies, each with its own `dl_label_blkno` |
| `space.py` | Hands out free space in ascending order, starting from what `initcg()` leaves free |
| `ufs.py` | The writer: superblock and copies, cylinder groups, inodes, directories, data |
| `readback.py` | Reads an image back with `rhap_image` and diffs it against its tree |
| `sample.py` | The two images phase 3 is checked with |

## Nodes

A tree is a list of `ufs_extract.Node(path, kind, mode, uid, gid, mtime, data)`:

| kind | `data` | stored as |
|---|---|---|
| `dir` | `None` | `.`, `..`, then the children in list order |
| `reg` | bytes | fragments for the last direct block only, then single and double indirect blocks |
| `lnk` | target | inline when shorter than 60 bytes, otherwise a data block |
| `chr`, `blk` | `(major, minor)` | `(major << 8) \| minor` in `di_db[0]` |
| `hlink` | another node's path | a directory entry naming that node's inode |

Inodes are numbered from 2 in list order and spill into later cylinder
groups as they fill. The caller supplies the time stamped on the
filesystem, so the same tree always gives the same bytes.

## How it is checked

1. **Against Apple's own output.** Three references are used: `golden.img`,
   the DR2 install floppy and the DR2 CD.
   - Every geometry field matches.
   - The serialized superblock is byte-identical, except for the four
     fields the kernel rewrites at mount time: `fs_fsmnt`, `fs_cgrotor`,
     `fs_csp` and `fs_maxcluster`.
   - Cylinder-group offsets and sizes match.
   - The labels on `golden.img` and the floppy are reproduced byte for byte.

   The tests only read these images. The writer takes nothing from them.
2. **Read back on the host.** `readback.diff` walks the image's directories
   and checks every node's type, mode, owner, mtime, contents, link count
   and `di_blocks`. `ufs_check.check` then recomputes the allocation
   accounting.
3. **`fsck -n` in the guest.** Each sample image is attached as IDE `hd1` to
   the phase 1 fixture, booted single-user:

```bash
cd vm
python -m instmedia.sample work/p3-gate
python qemu_boot.py bios D:/RhapsodiOS/vm/work/p1-eide.img work/p3-gate/run512 --hd1 work/p3-gate/fdisk512.img --type "6:-s" --type "70:fsck -n /dev/rhd1a" --at 40,65,90,110
python qemu_boot.py bios D:/RhapsodiOS/vm/work/p1-eide.img work/p3-gate/run2048 --hd1 work/p3-gate/cd2048.img --type "6:-s" --type "70:fsck -n /dev/rhd1a" --at 40,65,90,120
```

Results on 2026-09-24: all five phases were clean on both images.

| Image | Label | Summary |
|---|---|---|
| `fdisk512.img` | `secsize` 512 in an `0xA7` partition at LBA 2048, 9 cylinder groups | `1805 files, 16558 used, 46801 free (9 frags, 5849 blocks, 0.0% fragmentation)` |
| `cd2048.img` | `secsize` 2048, fsize 2048, copies at 0/15/30/45, 4 cylinder groups | `8077 files, 32872 used, 96143 free (3 frags, 24035 blocks, 0.0% fragmentation)` |

## Worth knowing

- **Label partition fields.** `golden.img`'s label says `minfree` 10, but
  its filesystem was made with 5. `disk -i` fills the label from disktab
  defaults, and `newfs` then uses its own. `label.for_filesystem` records
  the values the filesystem actually has.
- **NeXT's `cg_clustersumoff`.** NeXT dropped BSD's `- sizeof(long)`
  (PR2216969, in both `mkfs.c` and `fsck`'s `pass5.c`). Pass 5 compares the
  whole map region from `cg_iusedoff`, so BSD's offset would fail it.
- **A `secsize` 2048 label on a 512-byte disk works.** `IODiskPartition`
  scales `p_base + d_front` by `d_secsize / physical block size`, and fsck
  takes its device block size from `fs_fsize / fs_nspf`. That is how the
  CD-style image was checked as an IDE disk.
- **Label copies are addressed in 512-byte physical blocks.** This holds on
  a CD too: DR2's copies say 0, 15, 30 and 45. A CD needs the copy at 0,
  because the kernel reads it in 2048-byte blocks.
- **Free space.**
  - Group 0's data starts right after the cylinder summary. That is often
    in the middle of a block, and the fragments before the next block
    boundary stay free.
  - In later groups, the stretch before the superblock copy is data space
    too.
  - Space never hands out a whole block that straddles either edge.
