# ext2 filesystem acceptance

**The pre-review Task9 i386 matrix passed at `95be5206`.** Its selected1024-device
format/check/probe/mount/write/unmount, all six revision/block profiles,
one current512 regression, independent clean checks and seven fresh cold
readbacks passed. The user explicitly skipped native PowerPC execution and
CPU exchange on 2026-10-08; these are USER-SKIPPED, never passed. Final
independent task and whole-branch reviews identified the follow-up corrections
recorded at the end of this document. Earlier matrix entries retain their
original artifact generations.

The Task 9 baseline is `5503fca18f5171c53ecb800261b388da1969651e` on
`codex/ext2fs-port`. The detailed commands, identities, source manifests,
status codes, logs and image hashes are retained under
`.superpowers/sdd/2026-10-05-ext2fs/` and `vm/work/ext2fs/`. These ignored local
evidence trees are not shipped in the source repository. Earlier task reports
identify the actual artifact generation for each run; a later source revision
is not silently substituted for it.

## Supported contract

The intended profile is ext2 revision 0 or 1, 128-byte inodes, revision-1 first
ordinary inode 11, and 1024/2048/4096-byte filesystem blocks. Allowed feature
masks are compat `0`, incompat `0x0002` (filetype), and ro-compat `0x0001`
(sparse super). Other features and 256-byte inodes are rejected. Individual
files are limited to 2147483647 bytes. Triple-indirect coverage uses 1 KiB
filesystem blocks to remain below that limit.

Device bounds come from `DKIOCGPARTINFO` on the selected logical partition;
legacy whole-drive queries are not partition bounds. Raw and block endpoints,
512- and 1024-byte logical sectors, and refusal of live/invalid/unavailable
capacities are separate cases. A positive capacity query alone does not prove
formatting, checking, mounting, probing, or correct sector mapping.

Task9 reproduced the complete1024 workflow failure: format/check succeeded,
but probe returned252 and mount returnedEINVAL. The capacity gate now admits
bounded512/1024 logical devices. The kernel validates cached device size
against selected capacity before metadata reads and converts byte offsets to
logical-device block addresses. Filesystem mapping uses filesystem shift
minus device shift; superblock writes recover the device shift from existing
ext2 geometry. Ext2 `i_blocks` remains measured in512-byte units. No shared
mount ABI field is added. Current production-kernel workflows and cold
readbacks passed in addition to the owning controls.

Writable admission requires a clean volume. The kernel marks the volume dirty
before mutation and marks it clean only after successful final flush and
unmount. Failed I/O can leave conservative allocated orphans requiring an
explicit offline repair. There is no journal replay, root mounting, ext4,
quotas, NFS export, online resizing, or kernel-server product.

## Native matrix and retained applicability

| Case | i386 evidence | PPC evidence / limitation |
|---|---|---|
| Disk codecs, byte swaps, bitmap helpers | Earlier native production-code units retained; current source applicability is required | Cross-builds retained; native execution user-skipped |
| `readonly`, `mapping`, `directory`, `malformed` | Task4 v5 repeated 126 Task3 cases: 36 valid reads/mapping/directory, 84 malformed, six truncated partitions | Native cases user-skipped |
| `mutation`, `limits`, `mmap-fsync`, `permissions`, `special` | Task5 v2 six revision/block profiles, including ENOSPC/EFBIG recovery and mapped persistence | Native cases user-skipped |
| `persistence`, `remount`, `busy` | Task5 native cold write/read, repeated EBUSY with continued usability, and NULL/device remount controls | Native cases and CPU exchange user-skipped |
| `dirty-refusal`, `recovery` | Task5 interrupted-write image refused RW, allowed RO; explicit offline repair status1, subsequent clean check0 and cold payload recovery | Native cases user-skipped |
| Private fault cases | Task5 v1-v3 selected admission/data/metadata/allocation/truncation/read/clean/close faults; v4a private builds retain diagnostic-only applicability | Native fault execution user-skipped |
| `capacity512`, `capacity1024` | Current i386 selected raw/block query, live/invalid refusal and legacy controls; actual1024 format/check/probe/mount/write/unmount/RO read pass | PPC execution user-skipped; native SCSI/exposed-HFS cases unavailable |
| Wrappers and current vendor I/O | Task7 146 wrapper and 48 actual vendor-module controlled cases; native five regular formats/checks and installed i386 workflow | Both-CPU links are not native PPC runs |
| `discovery` | Task8 24 exact-production ObjC controls; six current1024 actual-driver/helper cases pass | PPC cases user-skipped; installed-daemon/world execution unavailable |

The original `msync` entry point is unsupported on this platform. That
capability failure is retained separately; it is not a passing test and does
not replace the successful `mmap-fsync` cases.

Task9's current profile evidence is deliberately aggregated. The first run
completed logical1024/revision0/1KiB and its clean snapshot, then was stopped
by the controller during the next profile after delayed log visibility was
mistaken for a stall. This was an interrupted run, not a demonstrated kernel
failure. Its successful snapshot independently passed `e2fsck -fn`, payload
and metadata checks with an unchanged image hash. The failed overall run and
its partial second profile remain preserved.

A fresh continuation covers the remaining five logical1024 profiles and
logical512/revision1/1KiB with unchanged current kernel, package and mutation
assertions. The requested current acceptance set is therefore seven profiles
across these runs, not a pristine twelve-profile execution. The six Task5
logical512 profiles retain their original source/artifact qualification:
current512 mapping computes the same nine-bit device addresses, and the
current native66 controls and native bmap cases cover all three512 filesystem
block sizes. No new1024 fault-injection execution is claimed.

The continuation completed with guest and launcher status0, all six profile
markers, all six discovery cases and native checker status0. Its five QEMU
Slirp failed-send diagnostics are retained; stderr was not pristine. All
seven closed snapshots independently passed e2fsprogs1.47.4 `e2fsck -fn`,
five exact persisted payloads, mutation-proof mode0641/uid123/gid456, and
unchanged input hashes. A fresh cold boot then mounted all seven snapshots
read-only, verified persisted mutation/mapped/fresh data and metadata, and
unmounted successfully. Both complete packed data-image hashes remained
unchanged after closure.

The first cold launch failed before guest execution because QEMU rejected
read-only IDE block attachments. All input hashes remained unchanged. A
separately reviewed fresh run used writable private device copies with
read-only filesystem mounts and required complete final byte equality.
The original failed resources and logs remain preserved.

| Current closed snapshot | SHA-256 |
|---|---|
| logical1024-rev0-block1024 | `5f6226a242860c580770dcf7954f4669b275b99ea4ad5054f6ad85898ce3bd12` |
| logical1024-rev0-block2048 | `7c391805a67269ed403da3c233faf362182b62b25d33b9e0707467ae7d0691b0` |
| logical1024-rev0-block4096 | `197fbb2dd347d57c75a0102213994e4fad1eccbe1c46fcc309bf4671c8e72f64` |
| logical1024-rev1-block1024 | `aba09c0c53d491ea03ce7d83866db736d6ccf54ef37b4f426d4dae40c925b232` |
| logical1024-rev1-block2048 | `dd69cd308d8462ebae59a5f59d071869237c8edbd66c2d524e71c81a27dc99f4` |
| logical1024-rev1-block4096 | `502d11839b62aedf817360bc8308b875f50050808619b446daf82c1b3953f323` |
| logical512-rev1-block1024 | `0971698031aea6489866207a69c089be74671655fc88694081a0dcb11aef4741` |

Task5 applicability is explicit: v2 corrected the truncate bitmap-error
return; v3 invalidated and latched two failed/short-read paths; v4 added the
matching `vnode_pager_umount` declaration. Root accepted the declaration-only
v3-to-v4 applicability; no v4 native run is invented. Private v4a changes only
a bounded residual diagnostic cast. Changes to executable paths reopen the
affected cases.

Task8 actual discovery covered supported literal 16-byte labels, mount and
unmount, dirty writable refusal, unsupported and malformed rejection, missing
helper, and restored-clean control. Six bounded raw reads proved complete
16777216-byte producer success and equal before/after CRC pairs: dirty
1966104465, unsupported 2357522940, malformed 1673179109. Full output retains
all six records; raw sidecar files retain only the final malformed pair.

## Artifacts and build qualifications

| Retained artifact | SHA-256 |
|---|---|
| Task5 normal i386 v4 | `3ace08ce283780817500e27cb87b0095a079337f4e7a75fdfe2d91f16b989c71` |
| Task5 normal PPC v4 | `51f448ffddc64307f22c226c139dfe180333bb9f858510d7015840162863e442` |
| Task5 private i386 v4a | `0e6cd4b17ce2825ab359583569b94f22372ff0e4379a5c56c106f9b27ef8548f` |
| Task5 private PPC v4a | `825766c07225357b81c9d69b10f961e6f90fe8aac8b4c8daf8ffe2bfdfcff31a` |
| Task8 universal ext2fs 1.0 APK | `a2e240a06737159e6ad819afa3f22fd07e812e9de0ab51eaef8fe00c6b78953d` |
| Current Task9 i386 enabled | `3ea69005722c23d2009684c203f75a82f35ca3695b5658aafab41fe1faef9f03` |
| Current Task9 universal ext2fs 1.0 APK | `e89bec685b85a87601a828259c8d6dfc4e092b6006d6fd6fded5f7a44938b074` |
| Task9 i386 disabled | `bf70c46da17d564d88e7981cff3d055f71e63645530e3a4b0ab70d0993696ec7` |
| Task9 PPC disabled | `b829fa40c53cab81645c18f02db901fe18835f2635a344ec75653bacd3fe0c14` |

The historical Task8 APK was built from the exact 62-file snapshot with source fingerprint
`929b7eaa`. The later 64-file snapshot changes only uninstalled tests; the APK
was **not** built from that later snapshot. It contains nine commands with
i386/PPC slices, nine manuals, and three notices, with root ownership and
0755 command modes. It installs no generic headers or libraries, generic
fsck dispatcher, or kernel-server output. Task9 usage documentation and the
uninstalled sector test likewise do not establish a new package build.

Current Task9 packaging used the exact 66-input source generation with
fingerprint `282a0cb1`. It preserves the same installed payload shape. Later
documentation edits are not that build's source generation; compiled and
installed inputs remain unchanged. The current i386 kernel recompiled the
changed ext2 units and linked successfully with `EXT2FS=1`, without private
fault-test inputs. Both disabled kernels built with `EXT2FS=0`; subsequent
ext2-only changes are excluded from those configurations. The earlier Task9
PPC enabled kernel predates the sector fix and is historical build evidence.

Current vendor-patch-003 i386 evidence is 67 raw successes, six cosmetic
differences (blank-line output and gid0 displayed as wheel rather than root,
with checker status0), and two unconditional upstream skips, `e_brel_bma`
and `e_irel_ima`. Outer make status0 is not a pristine suite pass. Task6's
earlier run belongs to its earlier vendor source generation.

The narrow Task9 PPC prerequisite changes only three optional lookup helpers:
absent nodes return zero, while found nodes missing `reg` still panic. Exact
production-body tests changed from six absence failures to 21 passing native
i386 controls, and both CPU test binaries link. The complete captured mac99
tree has no normal MESH/audio match. Zero remains an offset added to the I/O
base; it is not a general controller-disable sentinel. Full PPC boot,
consistency checking and filesystem execution are user-skipped; link and
source proofs do not establish their behavior.

## Independent checks and regressions

Independent checking uses e2fsprogs 1.47.4 on separate unmounted copies;
production tools use pinned e2fsprogs 1.35. Clean native unmounts require
`e2fsck -fn` status0, unchanged checker input hashes, expected file hashes and
metadata after cold remount. Intentional damaged images retain before/after
copies and repair status bits. Task5's repaired fsynced 20-byte payload was
recovered on a fresh RW mount; unflushed application data is not covered.

The prescribed host suite is:

```text
python -m pytest vm/test_ext2_guest.py vm/test_ufs_alloc.py vm/test_ufs_cg.py vm/test_ufs_extract.py vm/test_ufs_e2e_image.py vm/test_ufs_e2e_boot.py vm/test_hfs_guest.py -q
```

Initial Task9 execution reported 31 passed and 64 fixture-dependent skips;
the ext2 subset had 27 passes and no skips. Verified private golden/install
media copies and a test-module-only `shutil.copyfile` substitution for the
macOS APFS convenience clone produced 103 passes, two skips and two setup
failures. Supplying the additional driver-disk fixture and placing the
temporary directory outside `vm/work` restored the intended refusal-test
condition; both focused reruns passed. Thus 105 distinct cases pass across
the retained runs, with two AHCI-bundle fixture cases unavailable. No test
assertion changed. APFS clone semantics remain untested. No host check
establishes native kernel behavior.

Current production-kernel UFS sparse direct/single/double-indirect,
mapped-fsync readback, owner/other permission and mapped-append controls pass
on a UFS volume with 1024-byte fragments and 8192-byte blocks. Current FAT/HFS
mount smoke and dynamic volfs registration remain unavailable. Historical
HFS-on-NeXT ATA evidence is retained with its original artifact identity.
No new general driver or hardware prerequisite work is part of the amended
scope.

## Reproduction and open release gates

The focused controls extract the actual production function bodies. Use
fresh output directories, then compile and execute their generated C files:

```text
python vm/ext2_sector_test.py sector-controls
cc -O2 -Wall sector-controls/sector_io.c -o sector-controls/sector_io
sector-controls/sector_io
python vm/pexpert_optional_test.py pexpert-controls
cc -O2 -Wall pexpert-controls/pexpert_optional.c -o pexpert-controls/pexpert_optional
pexpert-controls/pexpert_optional
```

Expected results are 66 mapping checks and 21 optional-helper checks with
zero failures. These provider controls do not compile the full kernel ABI
or execute a filesystem. Native bmap and production-kernel builds separately
validate the actual headers and link inputs; complete guest workflows remain
necessary.

Use disposable data images and private root clones. `tests/run-native.sh`
names the filesystem cases; `tests/run-sector.sh RAW BLOCK TOKEN MOUNT COUNT`
exercises actual raw/block formatting and checking, probing, mounting and
conditional persistence. COUNT is the selected partition's number of
1024-byte chunks, not an assumed fixture constant. A failed case remains
failed even if later observations succeed. `checksum-partition.sh` requires
producer exit0, complete input/output records and the exact byte count.

For the general i386 harness, set `RHAP_VM_ASSETS` to the directory containing
the installation floppy, `RHAP_TEST_IMAGE` to the private rebuilt root, and
`RHAP_EXT2_QMP_PORT` to an unused port. The runner copies root/data images and
refuses existing output directories. `native-tools` contains the matching
`mount_ext2fs`, `ext2_io`, and `partition_info` binaries.

```text
python vm/ext2_guest.py wrap ext2-volume.img labelled.img
python vm/ext2_guest.py run readonly run-ro labelled.img native-tools
python vm/ext2_guest.py capacity 512 capacity512.img
python vm/ext2_guest.py run capacity512 run-capacity512 capacity512.img native-tools
python vm/ext2_guest.py capacity 1024 capacity1024.img
python vm/ext2_guest.py run capacity1024 run-capacity1024 capacity1024.img native-tools
python vm/ext2_guest.py tiny tiny.img
python vm/ext2_guest.py run tiny run-tiny tiny.img native-tools
```

The simple readonly fixture has root mode0755, lost+found, and `/hello.txt`
mode0644 containing exactly `hello from ext2\n`. It repeats
mount/read/mutation-refusal/unmount twice. Tiny fixtures expose one through
four 512-byte sectors and must be rejected without changing media or the
mountpoint. Every passing runtime requires status0, its exact marker and no
serial panic; read-only/refusal cases also require unchanged media. Earlier
native i386 HFS Plus-on-NeXT ATA mounting and ext2-disabled mount refusal are
retained milestone evidence. HFS-on-NeXT does not prove the distinct PPC
exposed-HFS-bank selector.

The user's amended scope requires the current i386 blocker, affected
profiles, independent clean checks and cold remounts, followed by Task9 and
whole-branch review. PPC native execution and CPU exchange are user-skipped.
Unavailable SCSI/exposed-HFS, current FAT/HFS/volfs and installed-daemon
execution remain explicit limitations. Infrastructure failures and unavailable
prerequisites must not be relabeled as filesystem passes.

Retained warning debt includes vendor BLKFLSBUF/FDFLUSH and LIST_HEAD warnings,
stock Java configuration noise, the exposed unused byte-writer warning and
notice EOF whitespace. The mounted-source naming defect and positive
aligned-prefix-short129/768 test gap were addressed in the final review wave.

## Final review wave

The current ordinary i386 kernel is
`d517fb588377364cf16a68ddbef92b209f27ee6c428fb3dcd73047a8c97784d1`.
The universal APK is
`8dd5e8e30018eda11b20b0749dc80dea612a8610b0eca760f3fa5dd6334670fa`,
source identity `db7a5d0d`, from 68 frozen LF-qualified inputs. It contains
nine CPU7/18 commands, nine manuals, three notices and package metadata.
The later uninstalled `review_io.c` helper has separate native source/binary
proof; installed package inputs are unchanged. These artifacts supersede the
earlier generation for this focused validation, without relabelling its tests.

Vendor patch004 makes mounted-target inspection conservative and fixes both
destructive callers, while preserving readonly inspection and explicit force
semantics. Indirect truncation validates unshifted roots and recursive pointer
arrays before explicit I/O or freeing, and retains conservative error state.
Allocation compares free and reserved counts directly. Buffered/inline reads
and the ext2-tagged MapFS ordinary-read boundary record delivered RW accesses.
The installed mount manual now describes the writable profile.

Actual-production native controls passed: 39 allocator/read/chown checks,
112 final truncate checks, 48 MapFS copy-boundary checks, 41 vendor mounted
decision checks, and 54 vendor I/O checks including positive129/768. Actual
disabled MapFS compilation and 48 disabled controls also passed. Native
execution is i386; PPC links are compile evidence only. The retained31
ownership controls passed before the user explicitly skipped comprehensive
ownership follow-up. That follow-up and native PPC/CPU exchange are
USER-SKIPPED, never passed.

The targeted current i386 workflow passed on logical512/1024, revision1 and
1 KiB filesystem blocks. It covers valid truncation, root crossing the reserve
with nonroot ENOSPC, persisted buffered/mapped/inline access times, readonly
nonmutation, all six outside/removed/relative mounted-source refusals with
unchanged bounded full-partition checksums, and malformed indirect-root EIO
with an unchanged sentinel outside the advertised filesystem. The1024 result
is aggregated: passed mutation/timestamp work was retained through an exact
private copy, explicit offline repair1/clean-check0 and full payload/timestamp
verification before the remaining refusal cases. It is not a pristine repeat
of the earlier seven-profile matrix.

Original failures remain explicit: an oversized reserve fixture was rejected
by the pinned checker, an unbounded raw checksum read reached end-of-partition
EIO, and ordinary build attempts exposed CRLF input errors. The successful
continuation uses the existing bounded checksum helper and explicitly returns
producer failure. It finished status0 with no panic and one retained QEMU
Slirp failed-send diagnostic. Two clean snapshots precede the deliberate
malformed-pointer fixtures.

The native UFS mapped-write/fsync/immediate readback passed, but its closed
disk lacked the five mapped bytes. UFS cold persistence is not established.
The shared change is gated to ext2 reads; no UFS/write behavior was changed.
This observation remains available to scoped review, with no broad UFS repair
or baseline-VM follow-up under the final scope ruling.

Independent e2fsck1.47.4-f-n checks passed on both clean16MiB snapshots,
with full Q payloads, empty-file checks and on-disk access times newer than100.
A fresh i386 cold run passed both RO readbacks/unmounts; both full packed data
image hashes remained unchanged. Native lstat and independent debugfs report
different inline-link atime values (all newer than100); exact readings remain
in the report for review rather than being claimed identical.
Full commands, CPU/config/source applicability, statuses, streams, cards and
hashes are in `final-fix-wave-report.md` and its named local proof files.

The new owning fixtures are generated with:

```text
python vm/ext2_review_test.py private-generated
python vm/ext2_vendor_mount_test.py private-patched-vendor private-vendor-tests
```

Compile those extracted bodies with the actual native ABI headers/configuration;
host substitutes do not establish kernel ABI or execution. The uninstalled
`src/ext2fs-1/tests/review_io.c` is for the exact guarded private fixtures,
including their selected-device geometry and offline mutation checkpoints.
