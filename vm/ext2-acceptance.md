# ext2 native acceptance

The initial driver supports read-only data mounts. Writable mounts are refused.
Use a kernel with EXT2FS and DKIOCGPARTINFO plus a matching ATA driver; an old
kernel without the partition query is deliberately rejected. A root-volume
boot path is not provided.

The initial supported profile is ext2 revision 0/1, 128-byte inodes, 1/2/4 KiB
filesystem blocks, compat mask 0, incompat mask 0x2, and ro-compat mask 0x1.
The current device mapping requires 512-byte logical sectors. The exported
capacity query separately supports checked 1024-byte logical partitions.

## Disposable i386 run

Set RHAP_VM_ASSETS to the directory containing the installation floppy and
RHAP_TEST_IMAGE to a private root with the rebuilt kernel and matching EIDE.
The runner copies root and data disks, refuses existing output directories,
and validates its own QEMU process/name before sending console input.
RHAP_EXT2_QMP_PORT defaults to 5303 and must be unused.

```
python vm/ext2_guest.py wrap ext2-volume.img labelled.img
python vm/ext2_guest.py run readonly run-ro labelled.img native-tools
python vm/ext2_guest.py capacity 512 capacity512.img
python vm/ext2_guest.py run capacity512 run-capacity512 capacity512.img native-tools
python vm/ext2_guest.py capacity 1024 capacity1024.img
python vm/ext2_guest.py run capacity1024 run-capacity1024 capacity1024.img native-tools
python vm/ext2_guest.py tiny tiny.img
python vm/ext2_guest.py run tiny run-tiny tiny.img native-tools
```

`native-tools` contains mount_ext2fs, ext2_io and partition_info, built from
src/ext2fs-1. The readonly fixture contains /hello.txt (mode0644, exactly
`hello from ext2\n`), root mode0755 and lost+found. A passing run needs status0,
the exact case marker, an unchanged data image, and no serial panic.
Read-only testing repeats mount/read/mutation-refusal/unmount twice.
The tiny fixture exposes partitions of one through four sectors. Native
mounts must reject them cleanly; production disk tests separately prove that
the reader is never called below four sectors and is contained at four.

## Evidence at the read-only milestone

| Check | Result |
| --- | --- |
| Host harness, real codecs and swap helpers | Pass |
| Native i386 disk codecs and actual inode adapter | Pass |
| i386 and PPC enabled kernel compile/link | Pass |
| i386 and PPC ext2-disabled link | Pass; common objects reused from enabled builds |
| Shared UFS inode/mount layouts on both compilers | Unchanged |
| Native i386 repeated read-only mount/unmount | Pass |
| Native i386 tiny partition mount refusal | Pass; capacities 1–4 sectors, unchanged data and mountpoint |
| Native i386 ext2-disabled mount refusal | Pass; unsupported filesystem, unchanged data |
| Native i386 block/raw 512-byte partition capacity | Pass; legacy whole-drive values preserved |
| Native i386 block/raw 1024-byte partition capacity | Pass; legacy whole-drive values preserved |
| Native i386 HFS Plus on a NeXT ATA partition | Pass; mount, listing/checksums, consistency and unmount |
| Native PPC filesystem execution | Pending; cross-link is not execution |
| Native SCSI/exposed HFS partition capacity | Pending; PPC-only HFS bank selector |

The live device, unavailable partition, and whole-drive-sized or oversized
logical partitions must be refused by DKIOCGPARTINFO. HFS mounted inside a
NeXT ATA partition does not prove the exposed HFS partition-bank path.
The later read/write acceptance work must retain these pending native gates.
