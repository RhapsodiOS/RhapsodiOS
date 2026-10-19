# HAMMER Phase 1 (Read-Only Mount) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mount a single-volume HAMMER v7 volume read-only on RhapsodiOS and
read its files, directories, symlinks and metadata exactly as DragonFly BSD
wrote them. `newfs_hammer` and offline `hammer show`/`blockmap`/`checkmap`
work on Rhapsody.

**Architecture:** Import DragonFly's HAMMER1 kernel and tool sources pristine.
Make every on-disk field a little-endian wrapper type so byte order is
compiler-enforced on both CPUs. Port the userland tools first, which tests the
format layer without the kernel. Then register `hammer` as a static
filesystem with its own buffer layer on 8 KB device reads, and port only the
read paths. Write-side units are not compiled in this phase. A DragonFly BSD
QEMU guest makes the reference volumes and checks ours.

**Tech Stack:** Darwin 0.3 BSD VFS, gcc 2.7.2.1-based Rhapsody `cc` (C89 plus
GNU extensions), ProjectBuilder/pb_makefiles, rbuild/apk, Python/pytest host
harnesses, QEMU i386, a DragonFly BSD live ISO in QEMU, `qemu-img`.

**Spec:** [HAMMER design](../specs/2026-10-17-hammer-design.md) (Phase 1).

## Global Constraints

- Kernel code `src/kernel-7/bsd/hammer/`; tools `src/hammer-1/`; package `hammer`.
- Upstream DragonFly `master` at `4e10f78d03f3d76c5bbe99c5d65022a03ea21e2e`.
- BSD 3-clause throughout. Keep every upstream notice. New files carry the
  same BSD 3-clause text with a RhapsodiOS copyright line.
- On-disk format is HAMMER **version 7**, **single volume** (`vol_count == 1`,
  `vol_no == 0`), root PFS only. **Little-endian on disk on every CPU.**
- Static filesystem name `hammer`, type number **19**, `MNT_LOCAL`, no
  mountroot. Append `VT_HAMMER` to the vnode-tag enum without renumbering.
- Kernel metadata buffers are 16 KB (`HAMMER_BUFSIZE`) and large data buffers
  are 64 KB (`HAMMER_XBUFSIZE`). Rhapsody `MAXBSIZE` is **8192** and must not
  change. `MAXPHYS` is 64 KB.
- Target compiler is gcc 2.7.2.1: no mixed declarations or `for (int ...)`, no
  `<stdint.h>`/`<stdbool.h>`, no `__func__` (use `__FUNCTION__`), no C99
  designated array initialisers, no VLAs. Rewrite these in place.
- Phase 1 is read-only. Mutating vnode operations return `EROFS`. Read-write
  mount requests are refused with `EROFS`.
- Device capacity comes from `DKIOCGPARTINFO` (`bsd/dev/disk.h`), as ext2 uses.
- Test volumes are **2 GB** raw images. HAMMER requires at least 64 UNDO
  big-blocks (512 MB).
- All guests follow CLAUDE.md: private overlays or copies, their own ports and
  `-name`, QMP-only shutdown after `query-name`. The base image is never written.
- ppc: kernels and tools must **build** for ppc. ppc runtime evidence is
  recorded as open in `PORTING.md` (user's decision), not faked.
- Commit prefixes are `kernel:`, `hammer:` or `vm:`. Stage only each task's
  files. No metadata in commit messages.

## Review Focus

1. **Inode numbers.** 64-bit HAMMER object IDs are folded into Rhapsody's
   32-bit `ino_t`. `stat` and `readdir` must agree, and hard links must share a
   number (Tasks 6, 7).
2. **`readdir` with small buffers** on large directories with hash collisions:
   every entry is returned exactly once, and resuming from an offset works (Task 6).
3. **Crafted volumes:** names longer than `NAME_MAX`, record lengths
   past a buffer, and bad B-tree element counts return `EIO`. They must never
   overrun memory or panic (Tasks 6, 7).
4. **Timestamps** before 1970 or after 2038 are clamped, not wrapped
   (Task 6).
5. **EOF and holes:** reads at or past EOF, holes inside and between data
   records, partial last records and a partial last mmap page return zeros or
   short counts correctly (Task 7).

## File and interface map

| Files | Responsibility |
| --- | --- |
| `src/kernel-7/bsd/hammer/hammer_*.c`, `hammer*.h`, `crc32.c`, `icrc32.c`, `ORIGIN` | Pristine import (Task 1), then adaptation. |
| `bsd/hammer/hammer_port.h` | Portable fixed-width types, `bool`, LE wrapper types and accessors, shared by kernel and tools. |
| `bsd/hammer/hammer_admit.[ch]` | Pure volume-header admission check, shared by kernel, tools and host tests. |
| `bsd/hammer/hammer_rhapsody.[ch]` | Kernel glue: malloc types, token and `kmalloc` mapping, device reads, vnode allocation, `hammer_ino32`. |
| `bsd/hammer/hammer_rostubs.c` | Link-time stubs for write-side entry points not compiled in Phase 1. Each one panics with its name. |
| `bsd/hammer/PORTING.md` | Adaptation record, byte-order rule, buffer design, token audit, open ppc evidence. |
| `bsd/hammer/tests/{Makefile,swap_test.c,admit_test.c}` | Native and portable C tests. |
| `conf/{files,MASTER,MASTER.i386,MASTER.ppc,Makefile.template}`, `bsd/vfs/vfs_conf.c`, `bsd/sys/vnode.h` | Option, registration, tag, header export. |
| `src/hammer-1/{PB.project,Makefile,...}`, `newfs_hammer/`, `mount_hammer/`, `hammer/`, `common/`, `apk/`, `PROVENANCE.md` | Tools aggregate. `common/` holds upstream `ondisk.c cache.c blockmap.c misc.c uuid.c` plus mirrored `crc32.c icrc32.c` and `compat.[ch]`. |
| `src/hammer-1/tests/{hammer_walk.c,hammer_io.c,run-native.sh}` | Portable tree-manifest tool (built on Rhapsody and DragonFly), syscall assertions, guest case runner. |
| `vm/hammer_guest.py`, `vm/test_hammer_guest.py` | Volume wrapping (streaming), fixtures, Rhapsody i386 case runs. |
| `vm/dfly_guest.py`, `vm/test_dfly_guest.py`, `vm/dfly-reference.md` | DragonFly reference guest and reference-volume recipes. Assets go in `vm/work/dfly/` (never committed). |

## Verification conventions

Planned commands, not results. Build guest recipe: see memory
`private-qemu-guest-from-bootstrapped-img` and the ext2 plan's conventions
(`docs/superpowers/plans/2026-10-05-ext2fs.md` "Verification conventions"):

```sh
rbuild kernel --state /build/state-hammer --arch i386 /build/src /build/repo /build/hammer-kernel-i386
rbuild kernel --state /build/state-hammer --arch ppc  /build/src /build/repo /build/hammer-kernel-ppc
rbuild buildpackage --state /build/state-hammer --toolchain --arch i386 --dir --target all /build/src/hammer-1 /build/repo /build/hammer-tools
```

C unit tests run natively on the i386 build guest
(`make -C src/kernel-7/bsd/hammer/tests check`). WSL `gcc` may run the portable
subset (`make check CPPFLAGS=-DHAMMER_PORTABLE_TEST`), but that never counts as
target evidence. Host Python: `python -m pytest vm/test_hammer_guest.py vm/test_dfly_guest.py -q`.

The Rhapsody runner `python vm/hammer_guest.py run CASE OUTDIR VOLUME TOOLS_DIR`
follows `vm/ext2_guest.py run`. Differences: the data disk is a **qcow2 overlay**
on the wrapped reference volume. After a read-only case,
`qemu-img compare WRAPPED OVERLAY` must print `Images are identical.` The case
marker is `HAMMER_OK <case>`. Any `panic:` or `hammer: leaked` in `serial.log`
fails the run.

---

### Task 1: Import pristine sources and provenance

**Files:**
- Create: `src/kernel-7/bsd/hammer/` with all 32 files of upstream `sys/vfs/hammer/`, plus `sys/libkern/crc32.c` and `icrc32.c`, and `ORIGIN`
- Create: `src/hammer-1/newfs_hammer/`, `mount_hammer/`, `hammer/` with the upstream `sbin/` directories verbatim, and `PROVENANCE.md`

**Interfaces:**
- Produces: `ORIGIN` in `sha256sum -c` format (`<sha256>  <path relative to bsd/hammer>`), headed by comment lines giving the repository URL, commit and upstream paths. `PROVENANCE.md` does the same for the tools.

- [ ] **Step 1:** Fetch each file at the pinned commit with
  `gh api repos/DragonFlyBSD/DragonFlyBSD/contents/<path>?ref=<commit> -H "Accept: application/vnd.github.raw"`.
  Write the bytes unmodified with LF line endings (see memory `git-archive-subtree-crlf`).
- [ ] **Step 2:** Generate `ORIGIN`/`PROVENANCE.md` hashes from the fetched bytes.
- [ ] **Step 3:** Verify with `cd src/kernel-7/bsd/hammer && sha256sum -c ORIGIN`
  (and the same for `src/hammer-1`). Expected: every line `OK`.
- [ ] **Step 4:** Confirm that nothing references these paths yet:
  `git grep -n "bsd/hammer\|hammer-1" -- src/kernel-7/conf src/Manifest` prints nothing.
- [ ] **Step 5:** Commit: `hammer: import DragonFly HAMMER1 kernel and tool sources`.

### Task 2: Portable little-endian format layer

**Files:**
- Create: `bsd/hammer/hammer_port.h`, `bsd/hammer/hammer_admit.[ch]`, `bsd/hammer/tests/{Makefile,swap_test.c,admit_test.c}`, `bsd/hammer/PORTING.md`
- Modify: `bsd/hammer/hammer_disk.h`, `hammer_btree.h`, `hammer_crc.h`, `crc32.c`, `icrc32.c`
- Delete: `bsd/hammer/hammer_pfs.c`, `hammer_volume.c` (record in `PORTING.md`)

**Interfaces:**
- Produces, in `hammer_port.h`:
  - `typedef struct { u_int16_t le_; } hle16_t;` and the same for `hle32_t` and `hle64_t`.
  - `u_int16_t hget16(hle16_t)`, `u_int32_t hget32(hle32_t)`, `u_int64_t hget64(hle64_t)`.
  - `hle16_t hmk16(u_int16_t)`, `hle32_t hmk32(u_int32_t)`, `hle64_t hmk64(u_int64_t)`.
  - All are `static __inline`. They are the identity when `BYTE_ORDER == LITTLE_ENDIAN` and `HAMMER_TEST_SWAP` is not defined, and swap otherwise. Signed fields use the same types and are cast at the accessor.
  - Typedefs `int8_t` through `uint64_t` and `bool` onto Rhapsody's `u_int*_t`, under `#ifndef` guards.
- Produces, in `hammer_admit.h`: `int hammer_admit_volume(const void *hdr, size_t len, u_int64_t device_bytes, const char **why)`. It returns 0, `EINVAL` (bad signature, short `len`, CRC mismatch, geometry outside the device) or `EOPNOTSUPP` (version != 7, `vol_count != 1`, `vol_no != 0`, or the UNDO zone blockmap `first_offset != next_offset`, meaning recovery is needed). `*why` is a static string naming the failed rule.
- Produces, in `hammer_crc.h`: the upstream `hammer_crc_test_volume()` and the related helpers, unchanged in meaning (v7 uses `iscsi_crc32`, and the older `crc32` is accepted as upstream does).
- Rule (record it in `PORTING.md`): every field of every on-disk structure in `hammer_disk.h` and `hammer_btree.h` uses `hle*_t`. This includes `hammer_off_t`/`hammer_tid_t` fields and the `uuid_t` integer members. Byte arrays stay arrays. In-memory copies of on-disk structures stay in disk format and are read through accessors. CRCs are computed over the raw bytes. Direct arithmetic on a field is then a compile error on every CPU.

- [ ] **Step 1: Write `swap_test.c`:** check `hget64(hmk64(0x0102030405060708ULL))` round-trips. With `-DHAMMER_TEST_SWAP`, check that the raw `le_` of `hmk32(0x11223344)` is `0x44332211`. Check `sizeof(union hammer_btree_elm) == 64`, `sizeof(struct hammer_node_ondisk) == 4096` and `sizeof(struct hammer_volume_ondisk) <= HAMMER_MIN_VOL_JUNK`, so the wrapper types add no padding. The real-volume layout check is Task 5 `admit` against a DragonFly-made volume. Check `iscsi_crc32("123456789",9) == 0xE3069283` and `crc32("123456789",9) == 0xCBF43926`.
- [ ] **Step 2: Write `admit_test.c`:** build a valid v7 header in a 16 KB buffer through accessors (`vol_count` 1, CRC set with the upstream helper, UNDO first==next) and assert 0. Then each mutation returns the listed errno and a non-NULL `why`: signature changed to `HAMMER_FSBUF_VOLUME_REV` (EINVAL), version 6 (EOPNOTSUPP), `vol_count` 2 (EOPNOTSUPP), one CRC-covered byte flipped (EINVAL), `vol_buf_end` greater than `device_bytes` (EINVAL), `len` 512 (EINVAL), UNDO `next_offset` advanced (EOPNOTSUPP). Use `device_bytes` of 0 → EINVAL.
- [ ] **Step 3:** Run `make -C src/kernel-7/bsd/hammer/tests check` on the i386 build guest. Expected: it fails to compile, because `hammer_port.h` doesn't exist yet.
- [ ] **Step 4: Implement** `hammer_port.h` and `hammer_admit.c`. Convert the three headers to wrapper types and C89, and convert `crc32.c`/`icrc32.c` to C89.
- [ ] **Step 5:** Run `make check` natively. Expected: `swap_test: PASS`, `admit_test: PASS`. Also run it once with `CPPFLAGS=-DHAMMER_TEST_SWAP` (swap path on a little-endian host). Expected: PASS.
- [ ] **Step 6:** Commit: `hammer: make on-disk format little-endian typed and add admission check`.

### Task 3: newfs_hammer and offline hammer tools

**Files:**
- Create: `src/hammer-1/{PB.project,Makefile,Makefile.preamble,Makefile.postamble}`, `common/compat.[ch]`, `common/` (moved upstream shared sources, mirrored CRC files), `apk/pkginfo`, `tests/Makefile`
- Modify: `newfs_hammer/*`, `hammer/{hammer.c,hammer.h,cmd_show.c,cmd_blockmap.c,Makefile}`; `conf/Makefile.template` (`install_hammer_hdrs`, exporting `hammer_port.h hammer_disk.h hammer_btree.h hammer_crc.h hammer_admit.h hammer_ioctl.h hammer_mount.h` to `$(INCDIR)/bsd/hammer`); `src/Manifest` (`dir hammer-1 all`)

**Interfaces:**
- Consumes: `hammer_port.h` accessors and `hammer_admit_volume` (Task 2).
- Produces: `/sbin/newfs_hammer` and `/sbin/hammer`. In Phase 1, `hammer` dispatches only `show`, `blockmap` and `checkmap`, all offline through `-f DEVICE`. Other commands print `hammer: <cmd> not supported yet` and exit 1. Removed command sources are left out of the Makefile, not deleted.
- `compat.h` provides: `int hammer_device_size(int fd, u_int64_t *bytes)`, which uses `DKIOCGPARTINFO` for devices and `fstat` for regular files; `uuid_create`/`uuid_to_string`/`uuid_from_string`, with random v4 UUIDs from `/dev/random`; and `humanize_number`. Nothing else.
- `tests/Makefile check` runs `cmp` between `common/crc32.c` and `../../kernel-7/bsd/hammer/crc32.c`, and the same for `icrc32.c`, so the mirrors cannot drift.

- [ ] **Step 1: Write `tests/newfs-show.sh IMAGE`:** it creates a 2 GB regular file, runs `newfs_hammer -L T -f IMAGE`, then `hammer -f IMAGE show` and `hammer -f IMAGE checkmap`. It asserts exit 0, that `show` reports zero CRC errors (no `BADCRC` or `crc` failure strings), and that `checkmap` prints no mismatch lines. It prints `HAMMER_OK newfs-show`.
- [ ] **Step 2:** Run it on the i386 build guest. Expected: it fails, because the tools don't build yet.
- [ ] **Step 3: Port the tools.** Convert to C89 and the accessors, route device sizing through `hammer_device_size`, and replace `sys/diskslice.h` use. `newfs_hammer` refuses `-V` versions other than 7 and refuses multiple volume arguments ("single volume only"). `hammer show` refuses volumes that fail `hammer_admit_volume`, except for the recovery rule: offline inspection of a volume needing recovery is allowed, with a warning.
- [ ] **Step 4:** Build the package for i386 and ppc. Run `newfs-show.sh` and `make -C src/hammer-1/tests check` natively on i386. Expected: `HAMMER_OK newfs-show`, and the mirror `cmp` checks are silent.
- [ ] **Step 5:** Commit: `hammer: port newfs_hammer and offline show/blockmap/checkmap`.

### Task 4: DragonFly reference guest and reference volumes

**Files:**
- Create: `vm/dfly_guest.py`, `vm/test_dfly_guest.py`, `vm/dfly-reference.md`, `src/hammer-1/tests/hammer_walk.c`, `vm/hammer_guest.py` (the volume functions only), `vm/test_hammer_guest.py`

**Interfaces:**
- `hammer_walk ROOT` (C89 + POSIX, one source for both OSes) walks with `lstat` and prints one line per object, sorted by path:
  `path<TAB>type<TAB>mode%o<TAB>uid<TAB>gid<TAB>nlink<TAB>size<TAB>mtime<TAB>extra`.
  `extra` is the POSIX `cksum` CRC of a regular file's contents, the target of a symlink, or `-`. Objects with `nlink > 1` append `<TAB>=<smallest path sharing (st_dev,st_ino)>`. atime and ctime are never printed.
- `vm/hammer_guest.py`:
  - `wrap_volume_file(volume: Path, out: Path) -> None` streams the volume behind the NeXT label prefix from `ext2_guest.wrap_volume`, patches the partition size with `ufs_build.patch_labels`, and pads to a whole cylinder. It never holds the volume in memory. It refuses an existing `out` and protected names, as `ext2_guest._new_target` does.
  - `unwrap_volume_file(wrapped: Path, out: Path) -> None` reverses it.
  - `make_fixture(kind: str, volume: Path, out: Path) -> None` copies the volume and applies one header mutation (`badsig`, `v6`, `twovol`, `badcrc`, `needs-recovery`), recomputing the CRC except for `badcrc`. CRC32C is implemented in Python and tested against `0xE3069283`.
- `vm/dfly_guest.py`:
  - `run_script(iso: Path, volume: Path, script: str, outdir: Path) -> int` boots the live ISO with `-snapshot` on the CD only, a private `-name`, its own QMP and serial TCP ports, the volume as virtio disk 0 and a FAT32 transfer disk (`vm/fat32.py`) as virtio disk 1. It switches the loader to the serial console, logs in as root, mounts the FAT disk, runs `script` from it with output captured onto it, then quits through QMP after `query-name`. It returns the script's status.
  - `populate`, `walk` and `check` are scripts in `dfly-reference.md`. `check` runs `hammer -f /dev/vbd0 show` and `checkmap`.

- [ ] **Step 1: Ask the user to confirm** the exact ISO URL, version and size from `https://www.dragonflybsd.org/download/` before downloading it to `vm/work/dfly/`. Record the version and SHA256 in `dfly-reference.md`.
- [ ] **Step 2: Write host tests** for `wrap_volume_file`/`unwrap_volume_file` (round-trip byte identity on a 64 MB sparse test file, label size equal to the volume sectors, refusal of an existing output), `make_fixture` (each kind changes only the intended fields and keeps the CRC valid except for `badcrc`), and the CRC32C vector. Run pytest. Expected: FAIL (no implementation).
- [ ] **Step 3: Implement** the helpers and `run_script`. Run pytest. Expected: PASS.
- [ ] **Step 4: Define and build the reference volumes** (2 GB each) by running `populate` on DragonFly. Record the exact script in `dfly-reference.md`. Then unmount cleanly.
  - `ref-main` contains:
    - A directory of 20,000 entries.
    - Directories of 0, 1 and 100 entries.
    - Names of length 1 and 255.
    - Files of 0, 1, 16383, 16385, 1048577 and 64 MiB bytes.
    - A 512 MiB sparse file with data only at 0, 256 MiB and its last byte.
    - A 24-byte and a 200-byte symlink.
    - A file with three hard links.
    - Owner `1234:5678`.
    - Modes `0`, `4755`, `1777` and `0644`.
    - mtimes `1969-12-31 23:59:59 UTC` and `2100-01-01 UTC` (`touch -t`).
    - A file rewritten three times and a file created then deleted, with `sync` between steps so history records exist.
  - `ref-dedup` contains 32 identical 1 MiB files, deduplicated with `hammer dedup` on the mounted volume.
  - `populate` compiles `hammer_walk.c` with the live system's `cc` (copied in on the FAT disk). Save `walk` output for each volume as `vm/work/dfly/<name>.walk`.
- [ ] **Step 5: Cross-check our newfs.** Take an image made by our `newfs_hammer` (Task 3) and `unwrap_volume_file` it. DragonFly `check` reports no errors, and DragonFly mounts it read-only. Record the result in `dfly-reference.md`.
- [ ] **Step 6:** Commit: `vm: add DragonFly reference guest and HAMMER volume helpers`.

### Task 5: Kernel registration, buffer layer and mount admission

**Files:**
- Create: `bsd/hammer/hammer_rhapsody.[ch]`, `bsd/hammer/hammer_rostubs.c`, `src/hammer-1/mount_hammer` port, `src/hammer-1/tests/{run-native.sh,hammer_io.c}`, the `run` subcommand in `vm/hammer_guest.py`
- Modify: `conf/files` (`OPTIONS/hammer optional hammer` plus the Phase-1 compile set: `hammer_admit.c hammer_rhapsody.c hammer_rostubs.c hammer_io.c hammer_ondisk.c hammer_subs.c hammer_vfsops.c crc32.c icrc32.c`; Task 6 extends the set), `conf/MASTER` (`options HAMMER # <hammer>`), `MASTER.i386`/`MASTER.ppc` (RELEASE and DEBUG lists), `bsd/vfs/vfs_conf.c`, `bsd/sys/vnode.h`, `bsd/sys/malloc.h` (`M_HAMMER`, appended), `bsd/hammer/hammer_mount.h`, `hammer_io.c`, `hammer_vfsops.c`, `hammer_ondisk.c`, `hammer_subs.c`, `PORTING.md`

**Interfaces:**
- `struct hammer_args { char *fspec; };` in `hammer_mount.h`. This replaces `hammer_mount_info` (no volume arrays, as-of or master ID).
- `struct vfsops hammer_vfsops`, registered as `{ &hammer_vfsops, "hammer", 19, 0, MNT_LOCAL, NULL, NULL }` under `#if HAMMER`.
- VFS signatures follow ext2 (`ext2fs_vfsops.c`): `hammer_vfs_mount(struct mount *, char *, caddr_t, struct nameidata *, struct proc *)`, `hammer_vfs_unmount(struct mount *, int, struct proc *)`, `hammer_vfs_statfs(struct mount *, struct statfs *, struct proc *)`, `hammer_vfs_root(struct mount *, struct vnode **)`, `hammer_vfs_sync(...)` (returns 0 read-only), `hammer_vfs_init(struct vfsconf *)`.
- `int hammer_dev_read(struct vnode *devvp, int64_t offset, void *dst, int bytes)` in `hammer_rhapsody.c`. It reads in `MAXBSIZE`-aligned chunks with `bread`, copies into `dst`, and releases each chunk with `B_INVAL` so it is not double-cached. `offset` and `bytes` must be multiples of `DEV_BSIZE`.
- Buffer layer: rewrite `hammer_io.c` so each `hammer_io` owns `malloc(M_HAMMER)` memory of its buffer size and fills it with `hammer_dev_read`. The `hammer_io`/`hammer_buffer` API that the rest of HAMMER calls stays the same, and write entry points return `EROFS`. Record "shortcut: copy through 8 KB `bread`; upgrade to direct `VOP_STRATEGY` I/O when Phase 2 write ordering needs it" in `PORTING.md`.
- Tokens: `lwkt_gettoken`/`lwkt_reltoken` map to empty macros, but only after Step 4's audit confirms the BSD kernel side is not preempted in kernel mode. HAMMER's own `hammer_lock_*` stay as upstream (`tsleep`/`wakeup`).
- `hammer_rostubs.c`: exactly the symbols the Phase-1 link reports as undefined. Each is `panic("hammer: %s not in phase 1", __FUNCTION__)`.
- Global counts (`hammer_count_inodes`, `hammer_count_buffers` and the other upstream `hammer_count_*`): at the last unmount, if any is nonzero, print `hammer: leaked <name>=<n>`.
- Refusal messages: `printf("hammer: %s: %s\n", fspec, why)`. A read-write request prints `hammer: read-only in this release`.

- [ ] **Step 1: Write runner cases** in `run-native.sh` and `hammer_io.c`:
  - `refuse FIXTURE_KIND`: `mount -t hammer -o ro` fails, and `hammer_io mounterr` reports `EOPNOTSUPP` or `EINVAL` per Task 2.
  - `refuse-rw`: a mount without `-o ro` fails with `EROFS`.
  - `admit`: a mount of `ref-main` with `-o ro` gets past admission. Until Task 6 it fails at root vnode with `EOPNOTSUPP` and prints `hammer: root not available`, so this case asserts the admission success message `hammer: <dev>: v7 single volume ok`.
  - Every case is followed by `qemu-img compare` against the image (host side).
- [ ] **Step 2:** Run `python vm/hammer_guest.py run refuse-badsig ...` on a stock kernel. Expected: the mount type is unknown and the case fails.
- [ ] **Step 3: Implement** the static wiring, `hammer_rhapsody.c`, the buffer layer, the C89 and accessor conversion of the compiled set, and the `mount_hammer` port.
- [ ] **Step 4: Token audit.** Read how `bsd/ufs/ffs` and `bsd/kern` serialise with `simple_lock`, and whether Rhapsody BSD code can be preempted in kernel mode. Record the evidence (file:line) and the decision in `PORTING.md`. If preemption is possible, map tokens to a recursive sleep lock instead, and record that.
- [ ] **Step 5:** Build i386 and ppc kernels with `HAMMER` on, and an i386 kernel with it off. Expected: all three link.
- [ ] **Step 6:** Run the cases `refuse-{badsig,v6,twovol,badcrc,needs-recovery}`, `refuse-rw` and `admit` on i386. Expected: every case prints `HAMMER_OK`, `qemu-img compare` reports `Images are identical.`, and there is no panic.
- [ ] **Step 7:** Commit: `kernel: register hammer and admit read-only volumes`.

### Task 6: Read-only namespace: root, lookup, getattr, readdir, readlink

**Files:**
- Modify: `conf/files` (add `hammer_btree.c hammer_cursor.c hammer_blockmap.c hammer_inode.c hammer_object.c hammer_transaction.c hammer_vnops.c`), those sources, `hammer_rhapsody.[ch]`, `hammer_rostubs.c` (shrinks), `PORTING.md`, `tests/hammer_io.c`, `run-native.sh`

**Interfaces:**
- `u_int32_t hammer_ino32(int64_t obj_id)` returns `(u_int32_t)(obj_id ^ (obj_id >> 32))`. It is used by both `getattr` (`va_fileid`) and `readdir` (`d_fileno`). The root reports `hammer_ino32(HAMMER_OBJID_ROOT)`.
- `int hammer_get_vnode(struct hammer_inode *ip, struct vnode **vpp)` replaces the DragonFly `getnewvnode`/`vx_*` path. It allocates with `getnewvnode(VT_HAMMER, mp, hammer_vnodeop_p, &vp)`, uses a per-inode `lockmgr` lock, and is reclaimed through `hammer_vop_reclaim`.
- Vnode op table (4.4BSD `componentname` style): `lookup`, `open`, `close`, `access`, `getattr`, `read` (Task 7), `readdir`, `readlink`, `inactive`, `reclaim`, `lock`/`unlock`/`islocked`, `print`, `pathconf`, `strategy` (Task 7) and `bmap`. `create`, `mknod`, `mkdir`, `remove`, `rmdir`, `rename`, `link`, `symlink`, `setattr` and `write` return `EROFS`. Everything else is `vn_default_error`.
- `hammer_vop_lookup` follows the ufs lookup locking protocol (`LOCKPARENT`, `ISDOTDOT`, `cache_lookup`/`cache_enter`). It finds names by `hammer_directory_namekey` and compares each collision. `..` uses `ino_data.parent_obj_id`. A name record longer than `NAME_MAX`, or with a length past its data, returns `EIO` and logs a message.
- `hammer_vop_readdir` emits `struct dirent` records, with `uio_offset` holding the next directory key. Synthetic `.` and `..` are at offsets 0 and 1. Every returned entry is current as of the mount's TID; historical records are skipped.
- Time conversion clamps HAMMER's 64-bit microsecond values to the range of `time_t`.

- [ ] **Step 1: Write cases:**
  - `namespace`: mount `ref-main` read-only, run `hammer_walk /mnt/h` with the content CRC disabled (`-n`, metadata only), and the host diffs the result against `ref-main.walk` with the CRC column ignored. Expected: identical.
  - `hammer_io readdir-small DIR`: read the 20,000-entry directory through `getdirentries` with 512-byte buffers. Assert 20,002 unique names and that every `d_fileno` equals `lstat` `st_ino`.
  - `hammer_io times`: the two clamped mtimes read as `-1` and `0x7fffffff`.
  - `hammer_io erofs`: `open(O_CREAT)`, `mkdir`, `unlink`, `rename` and `chmod` each fail with `EROFS`. `statfs` reports `f_fstypename` `hammer`.
  - `crafted-name`: a fixture with one directory entry's name length patched past `NAME_MAX` (`make_fixture('longname')`; add that kind) gives `EIO` on listing, with no panic.
- [ ] **Step 2:** Run them. Expected: they fail at root vnode (Task 5 state).
- [ ] **Step 3: Implement** the files listed. Convert to C89 and accessors, rewrite the namecache VOPs as `componentname` VOPs, and compile only the read paths of `hammer_object.c`/`hammer_inode.c`. Write paths go behind `#if 0 /* phase 2 */`, keeping upstream bodies for Phase 2.
- [ ] **Step 4:** Run all Task 5 and 6 cases on i386, and build ppc. Expected: `HAMMER_OK` for every case, identical images, no leaks or panics.
- [ ] **Step 5:** Commit: `kernel: read hammer directories and metadata`.

### Task 7: File data reads, mmap and deduplicated volumes

**Files:**
- Modify: `hammer_vnops.c` (read, strategy, bmap, pagein if the vnode pager requires it, following `ext2fs_vnops.c`), `hammer_rhapsody.c`, `PORTING.md`, the tests

**Interfaces:**
- The vnode logical block size is **8192**. `hammer_vop_read` uses `bread(vp, lbn, 8192)` on the vnode. `hammer_vop_strategy` maps `lbn*8192` to the HAMMER data record covering that offset (a data record's B-tree key is its end offset). It reads that slice through a `hammer_buffer` (16 KB or 64 KB), copies it into `bp`, zero-fills holes and the tail past EOF, and completes `bp` with `biodone`. A CRC failure on the record or its data returns `EIO`, sets `B_ERROR` and logs a message.
- `bmap` returns the identity mapping with `runp` set to 0. Device-level clustering is not used.

- [ ] **Step 1: Write cases:**
  - `data`: a full `hammer_walk` of `ref-main` (with CRCs) matches `ref-main.walk` exactly.
  - `hammer_io holes FILE`: `pread` at 0, 1 MiB, 256 MiB−1, 256 MiB and the last byte of the 512 MiB sparse file returns the expected bytes. A `pread` at EOF returns 0, and one 4 bytes before EOF returns 4.
  - `hammer_io mmap FILE`: `mmap` the 16385-byte file. Bytes match `read`, and the bytes past EOF in the last page are zero.
  - `dedup`: a full walk of `ref-dedup` matches `ref-dedup.walk`.
  - `crafted-data`: `make_fixture('baddata')` (add it) flips one byte inside the data of the 1048577-byte file, found through our `hammer -f show`. Reading the file returns `EIO`. Other files still read, with no panic.
- [ ] **Step 2:** Run them. Expected: the data cases fail (read not implemented).
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run all cases on i386 and build ppc. Expected: `HAMMER_OK` everywhere and identical images.
- [ ] **Step 5:** Commit: `kernel: read hammer file data`.

### Task 8: Lifecycle, regressions and Phase 1 acceptance record

**Files:**
- Modify: `run-native.sh`, `PORTING.md`, `vm/dfly-reference.md`

- [ ] **Step 1: Write the `cycle` case:** 100 `mount -o ro`/`walk -n`/`umount` cycles on `ref-main`, with no `hammer: leaked`, no panic, and an identical image.
- [ ] **Step 2: Run `cycle`, then regressions on the same kernel:** the ext2 `readonly` case (`vm/ext2_guest.py run readonly ...`), the HFS harness's basic case (`vm/hfs_guest.py`), and a normal UFS root boot. Expected: all pass.
- [ ] **Step 3:** Run `sha256sum -c ORIGIN`, which is expected to show only the documented modified and deleted files as failures (list them in `PORTING.md`). Every file still carries its upstream notice (`grep -L "DragonFly Project" bsd/hammer/*.[ch]` lists only the new RhapsodiOS files).
- [ ] **Step 4: Record in `PORTING.md`:**
  - The Phase 1 evidence table: case, CPU, result and date.
  - The ppc row: kernel and tools built, swap tests run with `HAMMER_TEST_SWAP`, runtime **open**.
  - The list of stubs left for Phase 2.
- [ ] **Step 5:** Commit: `hammer: record phase 1 acceptance`.

## Self-review notes

- Spec Phase 1 says `hammer info/show`. `info` needs a mounted-filesystem ioctl, so Phase 1 ships offline `show`/`blockmap`/`checkmap`, and `info` moves to Phase 2 with the ioctls.
- "Our `newfs_hammer` output mounts read-only on DragonFly and here" is covered by Task 4 Step 5 (DragonFly) and Task 3 plus Task 5 `admit` (here). A full namespace check of our own newfs output comes for free in Task 6 if `ref-main` is swapped for it, but that isn't required.
