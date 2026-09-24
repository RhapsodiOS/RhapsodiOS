# Bootable install media for RhapsodiOS i386

**Date:** 2026-09-22
**Status:** Design approved, pending spec review
**Scope:** umbrella design. Six phases, each gets its own implementation plan.

## Goal

A bootable installer that boots, runs a simple interactive text script,
partitions and formats a disk, makes it bootable from both BIOS and UEFI,
installs every one of our apks onto it with `apk`, and writes the configuration
the bare system needs to boot to a text console with SSH running.

**Milestone B (end of phase 5):** a hard-disk-image installer, attached to QEMU
as a second disk, installs onto a blank disk. That disk then boots on its own
under SeaBIOS and under IA32 OVMF to a console `login:`, and accepts
`ssh root@` with the password chosen during install.

**Done (end of phase 6):** the same, from an El Torito CD booted with
`qemu -cdrom` under both firmwares.

## Decisions

| Question | Decision |
|---|---|
| Target hardware | QEMU first. Old real PCs later: the design must not rule them out, but only QEMU is verified. |
| Scope | This umbrella spec, then one implementation plan per phase. |
| Package install | `apk add --root <target> --initdb`, so the installed system has a real apk database. apk-tools joins the world build. |
| Boot setup | Always both: `boot0` in the MBR, a FAT ESP holding `BOOTIA32.EFI`, and the `0xA7` Rhapsody partition. The installer asks no firmware question. |
| Media | The El Torito CD is the goal. It is reached through a hard-disk-image form built by the same tool (milestone B). |
| Remote access | SSH on by default. OpenSSL and OpenSSH join the world build, and root gets a password during install. |
| Architecture | i386 only. ppc is out of scope. |

## Constraints from the tree

Each fact below is anchored to source or to a measured image.

**Root filesystem and CD root**
- **Root is always UFS on i386.** `setconf()` sets `mountroot = ffs_mountroot`
  for every local root (`src/kernel-7/machdep/i386/swapgeneric.m`). cd9660 is
  compiled in (`conf/MASTER.i386` RELEASE) but nothing mounts it as root.
- **`rootdev=cdrom` scans `sd0`–`sd15`** for the first device whose inquiry type
  is `DEVTYPE_CDROM` (`swapgeneric.m`). Both IDE drivers present ATAPI drives as
  SCSI controllers: `AtapiController : IOSCSIController`
  (`drivers-i386/ide/drvEIDE/.../AtapiCnt.h`) and
  `AHCIATAPIController : IOSCSIController`
  (`drivers-i386/ide/drvAHCI/.../AHCIATAPI.h`).
- **The BIOS booter has no CD support.** boot-2 has no El Torito or 2048-byte
  sector code.

**Labels on fdisk disks**

Inside an `0xA7` partition, the label's *location* is relative to the partition,
but its *contents* are absolute. The booters, the kernel and `disk` all agree:
- **`disk -i -b` writes absolute values.** Once `disk -i` finds an `0xA7` entry
  it clears `force_blocksize` (`disk.tproj/disk.c:445`), so the label's
  `secsize` is 512. `p_base` and `d_boot0_blkno[]` both include `dosbase`
  (`hd.c`, `inferdisktab.c`), and boot1 goes at `dosbase`.
- **boot1** reads the label at `relsect + 15`, then loads boot2 from
  `d_boot0_blkno × secsize / 512`, counted from disk sector 0
  (`src/boot-2/i386/boot1/boot1.asm`).
- **boot2** reads the label at `part_offset + 15` and sets
  `boff = dl_front + p_base` (`src/boot-2/i386/libsaio/disk.c` `read_label`,
  which boot2 and `bootefi` both compile).
- **The kernel** uses the fdisk offset only to find the label
  (`IODiskPartition.m` `-readLabel`). The partition base it computes is
  `(p_base + d_front) × d_secsize / physBlockSize`, which is absolute.
- **`check_label` rejects a misplaced copy.** A copy whose `dl_label_blkno`
  isn't the physical block it was read from fails with "Label in wrong
  location" (`driverkit-3/libDriver/label_subr.c`).
- **Why the old hybrid disk failed.** `vm/build_uefi_image.build()` copied a
  whole-disk image, whose label holds whole-disk-relative values (`p_base` = 0,
  `dl_label_blkno` = 15), into a partition at a nonzero LBA. The failure was in
  that image, not in the booter.

**UEFI loader**
- **It only finds whole-disk labels.** `bootefi` picks its boot disk by probing
  for `dlV3` at LBA 15 of each whole disk (`src/bootefi-1/efi_disk.c`
  `looks_like_rhapsody`), and takes the first match. (Before phase 1; now it
  boots from the disk the loader was read from and finds its label inside an
  fdisk partition — commit `0f3be4d36`.)
- **It ignores `Kernel Flags`.** It hard-codes `"rootdev=hd0a -v"`
  (`efi_memory.c` `BOOTEFI_BOOT_STRING`). Only boot2's `boot.c:199` reads the
  `Kernel Flags` key, and `bootefi` excludes `boot.c`. (Before phase 1; now
  `bootefi` appends `Instance0.table`'s `Kernel Flags` after that compiled-in
  string — commit `5bc2870ed`.)
- **It rejects media with 2048-byte blocks** (`efi_disk.c`, `BlockSize != BPS`).
- **It zeroes `diskInfo`** in `KERNBOOTSTRUCT`.

**BIOS boot path**
- **boot0** loads the active partition's boot sector using the CHS start from
  its MBR entry (`int 13h/02h`), always from drive `0x80`
  (`src/boot-2/i386/boot0/boot0.asm` `found_active`).
- **boot1** reads boot2 with CHS arithmetic based on `int 13h/08h` geometry
  (`boot1/boot1.asm` `readSectors`, `getinfo`).
- **So the MBR's CHS fields must match the BIOS's translation.**

**Disk tools**
- **`fdisk` needs BIOS geometry.** It reads `kernbootstruct.diskInfo[unit]`
  through `/dev/kmem` and exits with "Bogus disk information in BIOS" when that
  entry is empty (`Commands/diskdev_cmds/fdisk.tproj/fdisk.c:219-250`).
- **`fdisk -dosplusufs` creates type `0x06`** (`fdisk.c:1263`), at cylinder
  boundaries.
- **`disk` falls back to `useAllSectors`** when `diskInfo` is missing
  (`disk.tproj/disk.c`).
- **`newfs` takes its geometry from the label** via `DKIOCGLABEL`
  (`newfs.tproj/newfs.c`).
- **Only the `0xA7` partition gets device nodes** (`hdNa`–`h`). A FAT ESP has
  no node through which it could be formatted.

**Packages**
- **The only install scripts are live-system `/dev` handling.** `files`
  (`src/files-5/apk/.pre-install`, `.post-install`) unmounts and remounts
  `/dev`. No other apk carries scripts.
- **rbuild writes no runtime `depend`,** only `makedepends`
  (`src/rbuild-1/pkginfo.c`).
- **apk 2.0_pre12 takes file paths.** `apk add` accepts `.apk` paths
  (`apk_db_pkg_add_file`), and `--initdb` creates
  `var/lib/apk/{world,installed,scripts}` under `--root`
  (`src/apk-tools-1/apk-tools/src/add.c`, `database.c`).
- **apk-tools, OpenSSL and OpenSSH are in no manifest.** OpenSSL 0.9.5a has
  `openssl passwd -crypt` (`apps/passwd.c`).

**Kernel**
- **UFS mounts in either byte order,** because the i386 config enables `revfs`.
- **`/dev/random` works:** the Xoodyak CSPRNG at character major 17
  (`bsd/dev/i386/conf.c`).

**Startup**
- **The DR2 installer hook.** `rc` runs `/etc/rc.cdrom` and halts when both
  `/System/Installation` and `/etc/rc.cdrom` exist. `rc.boot` uses the same test
  to skip fsck (`src/files-5/private/etc/rc`, `rc.boot`).
- **The text console is already the default:** `ttys` runs `getty` on the
  console.
- **Root can't log in as shipped.** `master.passwd` ships `root:*`.
- **Root is remounted read-write by `mount -vat ufs`** in `0100_LocalMounts`.
- **SSH is already wired up.** `1700_IPServices` generates the host keys and
  starts `sshd` when `SSHSERVER=-YES-`, which is `files`' default.
- **`iftab` configures every interface over BOOTP** (`bootpc`).

**Measured layouts**
- **`golden.img`:** label `secsize` 1024 and `dl_front` 160. Label copies at
  sectors 15/30/45, two `boot2` copies at sectors 64 and 192 (512-byte units),
  UFS at byte 163840.
- **DR2 CD:** label `secsize` 2048 at byte 7680, UFS at byte 655360 with
  bsize 8192, fsize 2048 and 10 cylinder groups. Packages are under
  `/System/Installation/Packages`.
- **`vm/ufs_build.py`** clones a template's geometry, handles one cylinder group
  only, has no double-indirect blocks, and refuses symlinks, hard links and
  device nodes.

## Architecture

```
 rbuild apks (i386 kernel/drivers + universal world, incl. apk-tools,
              OpenSSL, OpenSSH, installer)
        │
        ▼
 host builder  vm/instmedia/  (pure Python, Windows host)
   ├─ live root   : UFS = every apk unpacked + live overlay
   │                + /System/Installation/Packages/*.apk (the full set)
   ├─ ESP image   : FAT32 with /EFI/BOOT/BOOTIA32.EFI
   └─ wrapper     : (B) hard-disk image: MBR boot0 │ ESP │ 0xA7 UFS
                    (A) El Torito CD: label │ ISO9660 + catalog │ UFS
        │
        ▼  boot under QEMU (BIOS or IA32 UEFI)
 live environment (read-only root) ── rc → /etc/rc.cdrom → rhapinstall
        │
        ▼  mbrinst / disk -i -b / newfs / apk add --root
 installed disk: boot0 │ ESP (BOOTIA32.EFI) │ 0xA7 UFS root → login: + sshd
```

## Phases

| # | Phase | Done when | Needs |
|---|---|---|---|
| 1 | **Partitioned-disk boot.** Fix the hybrid test disk: `boot0`, an active flag, LBA-assisted CHS, and the copied label rebased to absolute addresses. In `bootefi`, boot from the disk the loader was read from, and read `Kernel Flags` (see *Booter changes*). Also make this Windows host able to do all of that: `vm/fat32.py` replaces mtools, `bootefi` builds with the local LLVM, and `vm/qemu_boot.py` runs SeaBIOS and QEMU's bundled IA32 edk2 firmware. | The rebased hybrid disk reaches `rootdev 300` and userland under SeaBIOS and under IA32 UEFI, and the old two-disk layout still boots | none |
| 2 | **Packages missing from the world build.** Add `apk-tools-1`, OpenSSL and OpenSSH to `src/Manifest`, build them universal, and check off apk-tools' `PORTING.md` target list. | On a Rhapsody guest, `apk add --root <scratch> --initdb <all apks>` succeeds and `var/lib/apk/installed` lists every package; `sshd` starts and accepts a password login | none |
| 3 | **General host UFS writer** (`vm/instmedia/ufs.py`). | Round-trips through `rhap_image` with label `secsize` 512 (fdisk disk) and 2048 (CD); `fsck -n` passes on its output in a guest | none |
| 4 | **Pure-apk live root and hard-disk install media**, plus a pre-installed image. | The media reaches the installer menu under BIOS and UEFI. The pre-installed image boots multi-user to `login:` and accepts SSH | 1, 3 |
| 5 | **Installer**: `src/installer-1/` with `mbrinst` and `rhapinstall`. | Milestone B, as defined under *Goal* | 2, 4 |
| 6 | **El Torito CD**: ISO/El Torito writer, 2.88 MB BIOS floppy image, EFI catalog entry, 2048-byte reads in `bootefi`, `rootdev=cdrom`. | *Done*, as defined under *Goal* | 5 |

Phases 1–3 are independent. Phase 4 answers whether a system built only from our
apks boots at all, which has never been shown. Every later phase depends on that
answer.

## Media layouts

### Hard-disk form (milestone B), 512-byte sectors

The installed disk uses exactly this layout, and `mbrinst` writes the same MBR
and ESP that `hdimage.py` does.

| Where | Contents |
|---|---|
| LBA 0 | `boot0` plus the fdisk table. Entry 1: type `0xEF`, LBA 2048, 131072 sectors (64 MB). Entry 2: type `0xA7`, active, LBA 133120 to the last sector. CHS fields as described under *CHS values*. |
| LBA 2048 | ESP: FAT32, 64 MB, containing only `/EFI/BOOT/BOOTIA32.EFI`. 64 MB because EDK2's FAT driver silently ignores a FAT32 volume with too few clusters (`build_uefi_image.py`). |
| LBA 133120 | `0xA7` partition, with the interior `disk -i -b` writes on an fdisk disk: `boot1` at LBA 133120; label copies at LBA 133120 + 15/30/45 with `secsize` 512 and absolute `p_base` and `d_boot0_blkno`; two `boot2` copies at those `d_boot0_blkno` locations; UFS at `(dl_front + p_base) × 512`. |

- **BIOS boot:** `boot0`, the active `0xA7` entry, `boot1`, `boot2`, then
  `read_label` (unchanged). The kernel and boot drivers come from
  `/private/Drivers/i386/System.config/Instance0.table`.
- **UEFI boot:** `BOOTIA32.EFI` from the ESP, then the same disk and the same
  files.
- **QEMU harness:** the blank target is IDE `hd0`. The media is `hd1` with
  `bootindex` set, and its `Kernel Flags` say `rootdev=hd1a`.

### CD form (phase 6), 2048-byte sectors

| Where | Contents |
|---|---|
| bytes 0–32767 | ISO 9660 system area. NeXT label (`secsize` 2048) at byte 7680, the same offset DR2 used. |
| byte 32768 on | ISO 9660 primary volume descriptor, El Torito boot record, terminator, path tables, root directory, boot catalog. |
| BIOS boot image | 2.88 MB floppy emulation: `boot1f`, `boot2`, `mach_kernel.rcz`, `sarld`, the boot drivers, and `Instance0.table` with `rootdev=cdrom`. |
| UEFI boot image | FAT ESP image containing `BOOTIA32.EFI`. |
| `dl_front` × 2048 onward | UFS, fsize 2048, holding the same live-root contents as the hard-disk form. |

The ISO 9660 directory lists only the boot images. The UFS isn't visible to ISO
readers.

- **BIOS boot:** floppy emulation, so the booter reads the kernel from the
  emulated `fd0`. The kernel attaches the ATAPI drive through EIDE or AHCI as
  `sd*`, and `rootdev=cdrom` mounts the UFS read-only.
- **UEFI boot:** the EFI catalog entry starts the loader, which reads the kernel
  and drivers from the CD's UFS through BLOCK_IO at 2048 bytes, then roots with
  `rootdev=cdrom`.

## Booter changes

**Phase 1.** boot0, boot1, boot2 and the kernel need no change; see *Labels on
fdisk disks*.
- **`bootefi` boot-disk selection:** prefer the disk the loader was read from.
  Take `LOADED_IMAGE->DeviceHandle` (the ESP partition handle), find the
  whole-disk handle whose device path is its parent, and map that disk to
  biosdev `0x80`. The label probe walks the fdisk table to `relsect + 15`. If
  the loaded-from disk carries no label, fall back to the first labelled disk.
  The two-disk runner still depends on that fallback, because there the loader
  sits on an ESP-only disk.
- **`bootefi` boot string:** appends `Instance0.table`'s `Kernel Flags`, read
  after `loadSystemConfig()`, to the compiled-in default `rootdev=hd0a -v`
  (`efi_bootargs.c` `efi_append_boot_flags`). This is the opposite order from
  boot2's `boot.c`, which *prepends* the config value ahead of whatever was
  typed at the `boot:` prompt, so there a typed line's `rootdev=` wins;
  `bootefi` has no `boot:` prompt, so appending after its own default means
  the config's `rootdev=` wins instead, because the kernel's `getargs()`
  (`src/kernel-7/machdep/i386/i386_init.c`) keeps the last `rootdev=` it sees.
  Caveat: `getargs()` also overwrites `init_args` with each dash token in
  turn, so a `Kernel Flags` value such as `-s` replaces the compiled-in `-v`
  as init's argument rather than adding to it.

**Phase 6**
- **2048-byte media in `bootefi`:** `ebiosread` accepts BLOCK_IO media with
  2048-byte blocks by reading the containing block into a bounce buffer and
  returning its 512-byte sectors.

## Host builder (`vm/instmedia/`)

```
python vm/instmedia/build.py --repo out/apks/i386 --efi BOOTIA32.EFI \
       --form disk|cd [--preinstalled] --out <image>
```

**Rules**
- **No Apple bits.** Every byte on the media comes from our apks or our own
  builds: boot0, boot1, boot1f and boot2 from the `boot` apk, and the kernel
  and drivers from the i386 apks. No DR2 media and no `golden.img` are used,
  not even as templates.
- **Stage in memory, never on NTFS.** apk payloads are read straight from the
  tar stream into a node tree, and the tree goes directly into the UFS writer.
  The Windows filesystem can't hold device nodes or reliable symlinks, and it's
  case-insensitive.
- **Standard library only.** `vm/fat32.py` writes the ESP, because mtools isn't
  available on the Windows host.
- **Deterministic output:** sorted walks, apk mtimes preserved, no host
  timestamps.

| Module | Job | Reuses |
|---|---|---|
| `apkrepo.py` | Index a flat apk directory and parse `.PKGINFO`. Prefers the `i386` variant over `universal`, and refuses packages available only for `ppc`. | none |
| `rootfs.py` | Build a node tree from apk payloads: mode, uid/gid, mtime, symlinks, hard links, device nodes. Apply an overlay directory. Report every path claimed by two packages, since `apk add` would refuse them later. | none |
| `live.py` | Compose the live root: every apk (`files` first), then the live overlay, then `/System/Installation/Packages/*.apk` and `/System/Installation/esp.img.gz`. With `--preinstalled`, it skips the overlay and applies the installed-system templates for `hd0` instead. | `rootfs` |
| `ufs.py` | Phase 3 writer. Computes geometry the way `newfs` would (bsize 8192, fsize 1024 or 2048), handles several cylinder groups and single and double indirect blocks, and supports symlinks, hard links and device nodes. Little-endian by default, like DR2 media. | `ufs_cg.py` for cylinder-group tables |
| `label.py` | NeXT `dlV3` label: three copies, checksum, boot-block locations. On an fdisk disk it writes what `disk -i -b` writes: `secsize` 512, absolute `p_base` and `d_boot0_blkno`, and `dl_label_blkno` = `relsect` + 15/30/45. On the CD: `secsize` 2048 with no fdisk table. | the label helpers in `ufs_build.py`, the rebase in `build_uefi_image.py` |
| `hdimage.py` | Hard-disk form: MBR, ESP, `0xA7` partition interior. | `vm/fat32.py`; the MBR and CHS helpers in `build_uefi_image.py` |
| `iso.py` | Phase 6: ISO 9660 and El Torito writer, plus the 2.88 MB floppy boot image. | `rcz.py` for `mach_kernel.rcz` |

**Inputs**
- **The apks:** `vm/fetch-apks.ps1` pulls them from the build guest into a flat
  local directory, using the tar-over-ssh transport of `sync-src.ps1` in
  reverse. `/build/repo` holds the universal apks, and the rbuild destination
  directories hold the i386 kernel and drivers.
- **`BOOTIA32.EFI`:** comes from the host clang/lld-link build (`bootefi-1` is
  in no manifest), so it's passed in as a file.

**Checks:** `rhap_image.py` reads every UFS image back and the builder diffs it
against the node tree. `ufs_check.py` verifies the allocation accounting.

**Left as it is:** `vm/ufs_build.py` and the injection tooling. They serve the
DR2-media workflows.

## Live environment

**Contents**
- **The live root is every apk unpacked,** in the order the installer uses, plus
  a small overlay. The live environment is then the same userland the installer
  is about to install, so reaching the installer menu proves it.
- **Cost:** every file is stored twice, once installed and once inside its apk.
  If the CD form outgrows 650 MB, the fallback is a `live.list` subset of
  packages. That fallback is phase 6's concern only.

**The live overlay holds only:**
- `/private/etc/rc.cdrom`, copied by the builder from the installer apk's inert
  `/usr/share/installer/rc.cdrom`. It runs `/usr/sbin/rhapinstall`, then offers
  **reboot / shell / halt**. No apk ships it at the live path; if one did,
  `apk add` would put it on the target too.
- `/Installation/Target`, the mount point for the target
- `/private/Drivers/i386/System.config/Instance0.table`, whose values depend on
  the medium:

| Key | Disk form | CD form |
|---|---|---|
| `Kernel Flags` | `rootdev=hd1a` | `rootdev=cdrom` |
| `Boot Drivers` | `EISABus PCIBus PS2Keyboard EIDE AHCI` | same |

**Startup**
- `rc.boot` sees `/System/Installation` plus `rc.cdrom`, skips fsck, and leaves
  root read-only.
- `rc` sees the same pair, runs `rc.cdrom` on the console instead of
  `/etc/startup/*`, and halts when it returns.
- Both media forms behave identically.

**Read-only root rules**

The kernel has no MFS, so nothing is writable until the target is mounted:
- The installer uses no here-documents, because `sh` writes those to `/tmp`.
- It uses no temp files.
- It writes nothing outside `/Installation/Target`.

**`/dev`** is the static set of nodes from the `files` apk. Phase 4 checks their
majors against the kernel: `sd` = 6 from `conf.c`, and `hd` = 3 and `fd` = 1
registered by DriverKit at runtime. A wrong major gets fixed in `MAKEDEV`, not
in the builder.

## Installer (`src/installer-1/`)

One project, built by rbuild into one apk. It carries:
- `/usr/sbin/mbrinst`
- `/usr/sbin/rhapinstall`
- `/usr/share/installer/rc.cdrom`
- `/usr/share/installer/templates/`, the installed-system templates

Everything sits at inert paths. The apk lands in the live root and on the
target like any other; only the builder's overlay copies `rc.cdrom` into place,
and only on the live root.

### `mbrinst`

About 150 lines of C. It never reads `/dev/kmem` or BIOS geometry.

- **`mbrinst -list`** prints every `/dev/rhd[0-3]h` and `/dev/rsd[0-7]h` it can
  open, with its size from `DKIOCNUMBLKS`.
- **`gzip -dc esp.img.gz | mbrinst /dev/rhdNh`** does the following:
  - writes `boot0` from `/usr/standalone/i386/boot0` and the fdisk table of the
    hard-disk layout
  - copies the ESP from stdin to LBA 2048, refusing it unless it is exactly
    131072 sectors
- **It replaces `fdisk`,** which can't run when the installer was booted from
  UEFI and can't create type `0xEF`.
- **It replaces `newfs_msdos`,** which has no device node to format through.
  msdosfs stays out of the world build.
- **For testing,** a regular file is accepted as the target, with its size taken
  from the file.

### CHS values

Start and end CHS use SeaBIOS's `TRANSLATION_LBA` rule, the standard LBA-assisted
translation:
- `spt` = 63
- `heads` = 255, 128, 64, 32 or 16, chosen by how many sectors per 63 × 1024
  cylinders the disk has
- entries past cylinder 1023 are written as 1023/254/63

The installer refuses disks under 1 GB, but size alone doesn't guarantee the
BIOS picks LBA translation for a given disk — see the CHS-translation risk
under *Risks*.

### `rhapinstall`

POSIX `sh`, with no here-documents.

| # | Step | Command |
|---|---|---|
| 1 | Pick a disk | Candidates are `mbrinst -list` minus the disk holding the live root (from `mount`'s `/` line). Refused if none are left, or if the chosen disk is under 1 GB. |
| 2 | Confirm | The user types `yes` to erase `hdN` or `sdN`. |
| 3 | Root password | Asked twice with `stty -echo`. It can't be empty; only the first 8 characters count, and the prompt says so. Hashed with `openssl passwd -crypt`. |
| 4 | MBR and ESP | `gzip -dc /System/Installation/esp.img.gz \| mbrinst /dev/rhdNh` |
| 5 | Label and boot blocks | `disk -i -b` on the `0xA7` partition: `boot1`, label, `boot2`. |
| 6 | Filesystem | `newfs /dev/rhdNa`, then `mount /dev/hdNa /Installation/Target` (called `T` below). |
| 7 | Packages | `apk add --root T --initdb /System/Installation/Packages/files-*.apk`, then `apk add --root T` with every other apk. Output goes to the console and to `T/private/var/log/rhapinstall.log`. |
| 8 | Configure | See *Installed-system configuration*. |
| 9 | Finish | `umount T`, `sync`, then offer reboot / shell / halt. |

**Error handling:** every step's exit status is checked. On failure the script
prints the command and its output, then stops at a menu offering **start over /
shell / halt**. It never continues past a failed step.

**Naming rule:** the installed `rootdev` is the name the target had during the
install. This requires the install media to sit on a later unit than the target,
or in a different namespace. The CD appears as `sd*` over ATAPI, and the
disk-form harness puts the media on `hd1`.

## Installed-system configuration

Written by `rhapinstall` step 8 from templates in the installer apk; only the
device name gets substituted. The builder's `--preinstalled` image renders the
same templates for `hd0`, so the configuration has a single source.

| File | Content | Why |
|---|---|---|
| `/private/etc/fstab` | `/dev/hdNa / ufs rw 1 1`, and nothing else | `0100_LocalMounts`' `mount -vat ufs` remounts root read-write. `fstab.hd`'s mfs `/tmp` line is left out because the kernel has no MFS. |
| `/private/Drivers/i386/System.config/Instance0.table` | `Default.table`'s keys, with overrides: `Boot Drivers` = `EISABus PCIBus PS2Keyboard EIDE AHCI`; `Active Drivers` = `Default.table`'s list plus `Intel1000`; `Kernel Flags` = `rootdev=hdNa`; `Boot Graphics` = `No` | Read by boot2, and by `bootefi` after phase 1. Graphics off gives a text boot. `Intel1000` drives QEMU's `-device e1000` and is loaded by `0700_Devices`. |
| `/private/etc/hostconfig` | `files`' copy with `APPLETALK`, `AUTOMOUNT` and `TIMESYNC` set to `-NO-`. `SSHSERVER=-YES-`, `HOSTNAME=-AUTOMATIC-` and `ROUTER=-AUTOMATIC-` are left as they are. | The network comes up over BOOTP. `1700_IPServices` makes the host keys on first boot and starts `sshd`. |
| `/private/etc/master.passwd`, then `chroot T /usr/sbin/pwd_mkdb -p /etc/master.passwd` | Root's password field set to the step 3 hash | `files` ships `root:*`, which allows no login on the console or over SSH. `pwd_mkdb` takes only `-p`/`-v` and always writes `/etc`, so it runs under `chroot` (`Commands/shell_cmds/chroot`). |

**Left alone because they're already correct:**
- `ttys`, which runs `getty` on the console
- `/dev`, which `apk` creates from the `files` apk
- the swapfile and the `/mach` symlink, which `0300_VirtualMemory` creates on
  first boot
- the rest of `/etc`

**Checked absent on the target:** `/etc/rc.cdrom` and `/System/Installation`.
Both come only from the live overlay. If either reached the target, `rc` would
run the installer again at every boot.

**Pre-installed image password:** a fixed test password, stored as a
precomputed DES crypt hash in the builder's test configuration. The builder
doesn't compute the hash, because Python 3.13 has no `crypt` module.

**Known noise, recorded and not fixed unless it blocks:**
- `rc` ends by running `/System/Installation/CDIS/popconsole`, a DR2 leftover.
- `rc.boot` calls `fbshow` and `fbalert`, which our build may not provide.

## Testing

**Isolation (CLAUDE.md §6):** every QEMU run boots throwaway copies of its disk
images in a per-run temp directory. Nothing boots or writes `golden.img` or
`vm/work/test.img`.

**Runner:** `vm/qemu_boot.py`, added in phase 1.
- Python, because Git Bash doesn't convert `-serial file:/d/…` paths for native
  QEMU.
- Boots with SeaBIOS or with the IA32 edk2 firmware QEMU ships
  (`share/edk2-i386-code.fd`).
- `-m 256`, which `bootefi`'s fixed `/base:0x08000000` requires, and
  `-cpu Nehalem` for UEFI.
- Two logs: the firmware and loader console, and the kernel console on COM2.
- Screenshots over QMP. Later phases add
  `-device e1000 -netdev user,hostfwd=tcp::2222-:22` for the SSH gates.

| # | Host tests | QEMU / guest gate |
|---|---|---|
| 1 | `fat32` round-trip; `rhap_image` reads a file back out of a rebased hybrid disk; `bootefi` host tests for the fdisk label walk, the device-path parent check and the boot-string append | The rebased hybrid disk reaches `rootdev 300` and userland under SeaBIOS and IA32 UEFI; the two-disk layout still boots |
| 2 | none | On the build guest: `apk add --root <tmp> --initdb <all>` succeeds and `installed` is complete; `sshd` accepts a login |
| 3 | `unittest`: `rhap_image` round-trip with label `secsize` 512 and 2048, with several cylinder groups, symlinks, hard links, device nodes and double-indirect files | `fsck -n` on the output, attached to a temp copy of an i386 guest |
| 4 | `hdimage` layout; `rootfs` reports conflicting paths | The media reaches the installer menu under BIOS and UEFI. The `--preinstalled` image reaches `login:` and `ssh -p 2222 root@localhost` succeeds |
| 5 | `mbrinst` compiled on the host against a file target: its MBR and ESP placement must be byte-identical to `hdimage.py`'s. `rhapinstall` runs under the host `sh` with stub tools on `PATH`, checking the command order and every failure-menu path | Install onto a blank temp disk, then boot that disk alone under BIOS and UEFI to `login:` and SSH with the step 3 password |
| 6 | ISO 9660 and El Torito structures read back; the floppy image fits in 2.88 MB | `-cdrom` boots under BIOS and UEFI, the install completes, and the installed disk boots |

## Risks

Most serious first.

1. **A pure-apk userland has never booted.** Phase 4 is designed to hit this
   first.
2. **The ATAPI CD root is untested:** `rootdev=cdrom` over EIDE or AHCI, and
   `docs/drivers/drvEIDE-issues.md` records past ATAPI command failures. Only
   phase 6 depends on it.
3. **apk 2.0_pre12 has never run on Rhapsody.** File-overlap refusals are
   possible. `files` must be installed first so that `var -> private/var`
   exists before apk creates `var/lib/apk`.
4. **OpenSSL 0.9.5a and OpenSSH 2.3.0p1 have never been through rbuild.**
5. **Real BIOSes that don't use LBA-assisted translation** will mis-read boot0's
   CHS values. Such machines can only boot the disk through UEFI.
6. **QEMU may not pick LBA translation for every target size** (unverified,
   from reading QEMU's source, not from a failing boot). SeaBIOS's own choice
   of CHS translation comes from `hd_geometry_guess()`, which infers it from
   the disk's total LBA count *and* the end-CHS fields already written in the
   MBR's boot partition entry, not from disk size alone. For a target roughly
   1-8 GB whose `0xA7` partition doesn't end on a cylinder boundary, that
   guess can land on LARGE or NONE translation instead of LBA, making boot0's
   LBA-assisted CHS values wrong for that disk. The phase 1 8 GB disk was
   safe because its partition's end CHS is 1023/254/63, which forces LBA.
   Mitigations: always end the `0xA7` partition on a cylinder boundary, pass
   `bios-chs-trans=lba` in the QEMU harness, and add a 1-4 GB target to the
   phase 5 gate.
7. **Unknowns in the environment:** whether QEMU's slirp answers Rhapsody's
   plain-BOOTP `bootpc`, and whether NetInfo, if `netinfod` brings up a local
   domain, takes precedence over `master.passwd` for logins.
8. **CD capacity:** installed tree plus apks might exceed 650 MB. The fallback
   is a `live.list` subset.

## Out of scope

- ppc, and x64 UEFI (the loader is IA32-only)
- testing on real hardware (the design only avoids ruling it out)
- keeping existing partitions or dual-boot; the installer erases the whole disk
- package selection, upgrades, and any GUI or network-configuration UI
- choosing NIC drivers for real hardware; the user edits `Instance0.table`
- booting the installer from USB
