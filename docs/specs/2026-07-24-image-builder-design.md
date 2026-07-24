# Bootable image builder design (host-side, packages → QEMU disk)

## Goal

Take a complete set of packages (`.deb` today, `.apk` also supported) from a
local repository and produce a **bootable raw disk image** that boots a
RhapsodiOS **i386** build in the existing `qemu.exe`, without depending on a
running Rhapsody guest. PowerPC is a later phase reusing the same core.

Success = `python build.py --repo vm/debs --arch i386 --preset minimal-base
--out rhapsody-i386.img` yields an image that boots through
`boot0 → boot1 → boot → mach_kernel → /etc/rc` to a login shell in `qemu.exe`.

## Constraints and decisions

- **Host-side only.** No Rhapsody guest in the build path. Runs on Windows with
  Python 3.13 (present) — no C compiler assumed.
- **Pure-Python** image generation. No off-the-shelf `makefs` (it cannot emit
  Rhapsody's big-endian-on-i386 UFS1 + NeXT disk label as-is).
- **i386 first**, ppc later. Shared package/UFS core; only the partition/boot
  layer differs (MBR + NeXT label vs. Apple Partition Map + Open Firmware).
- **deb and apk both** ingested behind one reader interface. No apk packages
  exist in-repo yet, so the apk reader is validated only against a synthetic
  fixture until real apk packages exist.
- **Flat repository**: a directory of `*.deb`/`*.apk` (default `vm/debs/`) plus
  optional `.tar` bundles auto-extracted to a cache.
- **Minimal bootable base first**, then scale to the full set.
- **Raw `.img` output**; convert to qcow2/vmdk with `qemu-img.exe` when needed.
- **UFS1 writer fidelity: approach (A)** — emulate `newfs` defaults with a
  simple, generous, write-once layout that the kernel FFS and `fsck` accept;
  validated by a Python round-trip reader. (Not a line-for-line `newfs` port.)
- Tools live in `vm/imgbuild/`.

## On-disk contract (i386, ground truth from sources)

- **MBR (sector 0):** `boot0` code + 4-entry fdisk table + `0xAA55`
  (`DISK_SIGNATURE`). Our partition: `systid=0xA7` (`FDISK_NEXTNAME`),
  `bootid=0x80` (`FDISK_ACTIVE`), `relsect`=partition LBA start.
  Source: `src/kernel-7/bsd/dev/i386/disk.h`, `src/boot-2/gen/libsaio/disk.c`.
- **NeXT disk label:** at **partition sector 15** (`DISKLABEL`), written as
  4 copies, **big-endian**, `dl_version=DL_V3` (`0x646c5633` = "dlV3"),
  embedding a `disktab` (`d_secsize=512`, `d_front`, `d_partitions[]`,
  `d_bootfile`). Root FS base = `dl_front + dl_part[part].p_base` sectors.
  Source: `src/kernel-7/bsd/dev/disk_label.h`, `src/kernel-7/bsd/sys/disktab.h`,
  `src/boot-2/gen/libsaio/disk.c` `read_label()`.
- **Root UFS1 (big-endian):** boot block `BBSIZE=8192` at offset 0; superblock
  at `SBOFF=8192` (sector 16); `FS_MAGIC=0x011954`; `MINBSIZE=4096`; default
  bsize 8192 / fsize 1024. Byte order per `boot-2/gen/libsaio/ufs_byteorder.c`.
  Source: `src/kernel-7/bsd/ufs/ffs/fs.h`.
- **Boot flow:** `boot0` (MBR) → `boot1` (partition boot sector) → `boot`
  (boot2, in the ~29 reserved sectors of the partition) → loads `mach_kernel`
  from the UFS root (`dl_bootfile`).
  Source: `src/boot-2/i386/doc/README`, `docs/boot/boot-i386.md`.

## Architecture: staged pipeline

```
repo/ (*.deb,*.apk) --1--> PackageIndex --2--> ordered install list
   --3--> staging rootfs tree + FileManifest
   --4--> dpkg DB + static /dev + deferred maintainer scripts
   --5--> big-endian UFS1 image
   --6--> MBR + fdisk(0xA7) + boot0/boot1/boot + NeXT label(x4) + spliced UFS
   --7--> raw .img  --(qemu-img.exe)--> qcow2/vmdk  --> qemu.exe
```

Each stage has a defined input/output and is testable in isolation.

### 1. Repository index (`repo.py`)
- Input: directories (default `vm/debs/`) + optional `.tar` bundles (extracted
  to a cache). Output: `PackageIndex` (`name → [PackageMeta...]`).
- `PackageMeta = {name, version, arch, depends, pre_depends, provides,
  conflicts, replaces, format, path, control_scripts}`.
- `PackageReader` interface:
  - `DebReader`: `ar` → `control.tar.gz` → `control` (RFC822); payload
    `data.tar.gz`.
  - `ApkReader`: gzip-concatenated tar; metadata from `.PKGINFO`; data segment
    payload. Validated against a synthetic fixture only.
- Arch derived from control/filename: `universal-`, `i386-`, `ppc-apple-rhapsody`.

### 2. Selection & dependency solve (`solve.py`)
- Input: `PackageIndex`, target arch (`i386`), root set. Output: ordered list.
- Root set: named preset (`minimal-base`) or a user list file. `minimal-base` =
  closure to boot to a shell: `kernel, boot, files, libsystem(+obj),
  libc(+obj), objc4/objc, system-cmds, shell-cmds, bash/tcsh, dpkg(+deps),
  diskdev-cmds` plus their `Depends`.
- Variant preference: arch-specific (`i386`) over `universal` when both satisfy
  a name; universal fat binaries run on i386 as-is (no `lipo` thinning).
- Resolution: honor `Depends`/`Pre-Depends`/`Provides`/`Conflicts`/`Replaces`;
  topological order, `Pre-Depends` first. Fail loudly on unsatisfiable/conflict.

### 3. Rootfs staging (`stage.py`)
- Extract each payload in install order into `staging/`, preserving path,
  symlink, mode, uid/gid, mtime; later packages overwrite earlier.
- Record `FileManifest`: path → owning package + md5.
- Fix-up: ensure `mach_kernel` at `/mach_kernel` (kernel deb ships it at
  `/private/tftpboot/mach_kernel`; `boot` loads it from the FS root).

### 4. dpkg DB + device nodes + deferred scripts (`dpkgdb.py`, `devnodes.py`)
- Synthesize `/var/lib/dpkg/status` (`install ok installed` per package),
  `/var/lib/dpkg/info/<pkg>.{list,md5sums,preinst,postinst,...}`, `available`.
- Static `/dev`: minimal device inodes (`console, tty, null, zero, mem, kmem,
  sd0*/hd0*, fd`) written directly into the image (UFS writer supports special
  files). Table derived from the `kernel` deb's `private/dev/MAKEDEV`. Rationale:
  early boot needs nodes before `/dev` is mounted; `files` postinst later
  remounts fdesc-union `/dev`.
- Maintainer scripts: cannot run Rhapsody `/bin/sh` on the host. Queue
  `postinst`s into a one-shot `/etc/rc.firstboot` run by `rc.boot` on first
  boot in the guest. For `minimal-base` these are trivial. **Assumption to
  verify during implementation.**

### 5. UFS1 writer (`ufs.py`) — approach (A)
- Input: staging tree. Output: big-endian UFS1 image blob + size.
- Geometry from `newfs` defaults: bsize 8192, fsize 1024, `FS_MAGIC 0x011954`,
  boot block `BBSIZE 8192` at offset 0, superblock at `SBOFF 8192`.
- Walk tree: inode 2 = root; assign inodes to dirs/files/symlinks/devices;
  build directory blocks (`.`/`..` + entries); allocate data blocks with direct
  + single/double indirect pointers; write cylinder-group headers, inode/block
  bitmaps, and summary info consistently.
- All multi-byte fields written big-endian (mirror `ufs_byteorder.c`).
- Sized to contents + configurable slack, rounded to cylinder groups.
- Ships with a matching **UFS reader** for round-trip validation.

### 6. Disk assembler (`disk.py`)
- Input: UFS image + boot bits from staging
  (`usr/standalone/i386/{boot0,boot1,boot}`). Output: raw `.img`.
- Sector 0: `boot0` + fdisk table (one `0xA7`, active, `relsect`=LBA), `0xAA55`.
- Partition: `boot1` in boot sector; `boot` into reserved ~29 sectors; NeXT
  `disk_label` (×4) at partition sector 15 (`DL_V3`, `d_secsize=512`, `d_front`,
  `dl_part[]`, `dl_bootfile="mach_kernel"`).
- Splice UFS image at `dl_front + p_base`.

### 7. Convert & run (`build.py` CLI + reuse `vm/`)
- CLI: `python build.py --repo vm/debs --arch i386 --preset minimal-base
  --out rhapsody-i386.img`.
- Optional `qemu-img.exe convert` to qcow2/vmdk; emit a `qemu.exe` command
  (reuse the `vm/start-vm.cmd` pattern) to boot the raw image.

## Error handling
Fail-fast with clear messages on: unsatisfiable deps, conflicts, missing boot
bits, content exceeding image size, malformed packages. No silent fallbacks.

## Testing (goal-driven ladder)
1. `ufs.py` round-trip: Python UFS reader parses the written image and diffs it
   against the staging tree (byte + metadata equality).
2. Optional read-only `fsck`/`dumpfs` sanity by attaching the built image to the
   golden guest (does not gate the build).
3. End-to-end: boot the raw image in `qemu.exe`, reach `/etc/rc` → login shell.

Per-stage unit tests on fixtures: a small `.deb`, a synthetic `.apk`, a tiny
staging tree for the UFS writer/reader.

## Module layout
```
vm/imgbuild/
  build.py        # CLI / orchestrator
  repo.py         # index + PackageReader (DebReader, ApkReader)
  solve.py        # selection + dependency resolution
  stage.py        # payload extraction -> staging tree + manifest
  dpkgdb.py       # dpkg status/info synthesis
  devnodes.py     # static /dev table (from MAKEDEV)
  ufs.py          # big-endian UFS1 writer + reader (round-trip)
  disk.py         # MBR + fdisk + NeXT label + boot blocks + splice
  formats/        # on-disk structs (fs, disklabel, disktab, fdisk), big-endian
  tests/
```

## Out of scope (this spec)
- PowerPC image path (APM + Open Firmware + `qemu-system-ppc`) — later phase.
- Interactive installer / install ISO — direct bootable disk only.
- `lipo` thinning of universal binaries.
- Indexed apt-style repository generation / remote mirrors.
