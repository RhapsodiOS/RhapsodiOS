# msdosfs (FAT12/FAT16/FAT32) Design

**Date:** 2026-07-23  
**Status:** Approved for implementation planning  
**Goal:** Full classic Mac OS X–era msdosfs parity on RhapsodiOS — FAT12/16/32 + VFAT long names, with matching mount, format, fsck, and Workspace Manager / autodiskmount integration.

## Context

RhapsodiOS (Darwin 0.3 / Rhapsody-era fork) already has a 4.4BSD-style VFS with UFS/FFS, HFS, CD9660, NFS, and miscfs. There is **no** msdosfs implementation today — only scaffolding:

- `vfs_conf.c` `#if MSDOS` entry for `"msdos"` (typenum 4)
- `VT_MSDOSFS` in `vnode.h`
- malloc types `M_MSDOSFSMNT`, `M_MSDOSFSFAT`, `M_MSDOSFSNODE`
- Historical `loadable_fs.h` example path `/usr/filesystems/dos.fs/`

Host floppy scripts under `cdis-3` already assume host-side `newfs_msdos` / `mkfs.msdos` when *authoring* images; they are out of scope for this work.

## Decisions

| Decision | Choice |
|---|---|
| Capability bar | Full R/W FAT12/16/32 + VFAT LFNs + mount/newfs/fsck + WSM util |
| Primary source | FreeBSD **4.11-RELEASE** `sys/msdosfs` + matching `sbin/mount_msdos`, `sbin/newfs_msdos`, `sbin/fsck_msdos` (pin the release tag at import; do not mix files across 4.x point releases) |
| Packaging | Dedicated `src/msdosfs-1/` product (mirror `hfs-1/`); kernel under `kernel-7` |
| Kernel enablement | Compile-time `options MSDOS` in `MASTER` (same class as HFS/CD9660) |
| VFS identity | Keep name `"msdos"`, typenum **4**, existing vnode/malloc tags |
| WSM bundle name | `/usr/filesystems/msdos.fs/` (not historical `dos.fs` example in `loadable_fs.h`) so the bundle matches the VFS type string |
| Approach | Port FreeBSD 4.11 end-to-end; adapt to this tree’s VFS; borrow Darwin/WSM details only where this tree already has precedents (`hfs.util`, autodiskmount, `loadable_fs.h`) |

## Architecture

```text
                    ┌─────────────────────────────────────┐
                    │  Workspace / autodiskmount          │
                    │  /usr/filesystems/msdos.fs/         │
                    │         msdos.util  (-p/-m/-r/…)    │
                    └──────────────┬──────────────────────┘
                                   │ exec / use
          ┌────────────────────────┼────────────────────────┐
          ▼                        ▼                        ▼
   mount_msdos              fsck_msdos               newfs_msdos
   (mount(2) "msdos")       (offline repair)         (create FS)
          │
          ▼
   ┌──────────────────────────────────────────────────────┐
   │ kernel-7  bsd/msdosfs/   (FreeBSD 4.11 port)         │
   │  vfsops + vnode ops  ←→  VFS (vfs_conf typenum 4)     │
   │  FAT cache / denode  ←→  buffer cache + disk vnode    │
   └──────────────────────────────────────────────────────┘
```

**Placement**

- **Kernel:** `src/kernel-7/bsd/msdosfs/`
- **Userland product:** `src/msdosfs-1/` aggregating mount, newfs, fsck, and util subprojects
- **Not in scope for v1:** turning UFS `fsck` into a type multiplexer; changing host `cdis-3` floppy authoring scripts

**Capability bar (v1)**

- Mount R/W and R/O; create/delete/rename files and directories; read/write data
- VFAT long filenames with 8.3 aliases
- FAT12/16/32 autodetection from the BPB
- Short-name / codepage behavior: keep FreeBSD 4.x defaults (typically CP437-style) unless a concrete Rhapsody locale need appears later

## Components

### Kernel (`src/kernel-7/bsd/msdosfs/`)

Port FreeBSD 4.11-RELEASE modules; rename/adapt only as required for this VFS:

| Piece | Role |
|---|---|
| `msdosfs_vfsops.c` | `vfs_mount` / `unmount` / `root` / `statfs` / `sync` / `vget` / fh ops / `init` |
| `msdosfs_vnops.c` | Lookup, create, open/close, read/write, readdir, setattr, remove, rename, mkdir/rmdir, etc. |
| `msdosfs_fat.c` | FAT12/16/32 chain alloc/free, fat cache |
| `msdosfs_denode.c` + `denode.h` | In-memory file node ↔ vnode |
| `msdosfs_lookup.c` | Dirent + VFAT LFN assembly |
| `msdosfs_conv.c` | 8.3 ↔ Unicode/LFN conversion |
| `msdosfs_mount.h` | User↔kernel `struct msdosfs_args` |

**VFS / build wiring**

1. Enable `#if MSDOS` entry in `bsd/vfs/vfs_conf.c`
2. Register `msdosfs_vnodeop_opv_desc` in `vfs_opv_descs[]` (missing today even under `#if MSDOS`)
3. Add `OPTIONS/msdos` and sources in `conf/files`
4. Enable `options MSDOS` in `conf/MASTER`
5. Adjust `conf/Makefile.template` include paths if needed (same pattern as hfs/cd9660)

Best structural templates in-tree: `bsd/isofs/cd9660/` (smallest complete local FS) and HFS registration lines in `vfs_conf.c` / `conf/files`.

### Userland (`src/msdosfs-1/`)

Mirror `src/hfs-1/` layout:

| Subproject | Install path | Role |
|---|---|---|
| `msdos_mount` | `/sbin/mount_msdos` | Fill `msdosfs_args`, call `mount("msdos", …)` |
| `msdos_newfs` | `/sbin/newfs_msdos` | Create FAT12/16/32 on a device/image |
| `msdos_fsck` | `/sbin/fsck_msdos` | Standalone scavenger (not dispatched by UFS `fsck`) |
| `msdos_util` | `/usr/filesystems/msdos.fs/msdos.util` | WSM / autodiskmount probe/mount/repair |

`mount -t msdos` already execs `/sbin/mount_TYPE` via `diskdev_cmds/mount.tproj`; the type string must remain `"msdos"`.

### Autodiskmount / WSM

Extend autodiskmount the same way HFS/CD9660 foreign volumes are handled:

- Probe: `msdos.util -p`
- Mount: `msdos.util -m` → `mount_msdos`
- Repair: `msdos.util -r` → `fsck_msdos`

Follow `kernserv/loadable_fs.h` protocol and `hfs.util` precedents; do not invent a private util API.

### Shared contracts

- VFS type string: `"msdos"`
- Mount-args struct kept consistent between kernel header and `mount_msdos`
- `.util` verbs and status codes match existing HFS/`loadable_fs` behavior

## Data flow

### Mount

1. User or WSM: `mount -t msdos /dev/… /mnt` → `/sbin/mount_msdos`
2. Helper fills `msdosfs_args`, calls `mount("msdos", …)`
3. `msdosfs_mount` opens the block device, reads BPB, classifies FAT12/16/32, validates FATs, builds mount private data + fat cache, creates root denode/vnode
4. Optional: `msdos.util -m` wraps the same path after a successful probe

### Read / write

1. Lookup walks directory clusters; VFAT slots combine into a long name; 8.3 alias always present
2. Read/write map file offsets → cluster chains via FAT, through the buffer cache on the device vnode
3. Extend allocates clusters and updates FAT + directory entry; truncate frees chains
4. `vfs_sync` / unmount flush dirty fat cache and denode metadata

### Format

1. `newfs_msdos` writes BPB + FATs + root directory (FAT32 root cluster) via raw device I/O only
2. FAT type chosen from geometry/size or explicit flags (FreeBSD 4.x semantics)
3. Volume is mountable immediately after format (no journal)

### Fsck

1. Offline only; refuse if mounted
2. Check BPB/FATs/directories: chain integrity, cross-links, lost clusters, basic LFN consistency
3. Repair modes follow FreeBSD 4.x-style `-y` / preen flags where practical
4. Exit codes follow existing fsck conventions so autodiskmount can decide mount-vs-fail

### Probe (WSM)

`msdos.util -p` reads the boot sector; if the BPB looks like FAT12/16/32, report type `msdos` (and label if present) without mounting.

## Error handling

### Mount

- Bad/missing BPB, unknown type, or inconsistent FATs → fail `mount(2)` with `EINVAL` / `EIO`; `mount_msdos` prints a short diagnostic
- Dirty/unclean unmount: follow FreeBSD 4.x behavior (typically still allow mount); rely on `fsck_msdos` when WSM/autodiskmount requests repair
- Do not invent a journal or a stricter forced read-only policy than 4.x / existing foreign-FS autodiskmount precedent in this tree

### Runtime I/O

- Device and corruption errors return `EIO` from VOPs; do not panic on bad FAT entries
- `ENOSPC` on allocation failure; `EROFS` on writes to R/O mounts; normal directory errno values (`EEXIST`, `ENOENT`, `ENOTEMPTY`, …)
- Invalid or too-long names / failed OEM mapping → `ENAMETOOLONG` / `EINVAL` (no silent 8.3 corruption)

### Fsck / format

- Check-only vs repair; uncorrectable damage → non-zero exit, leave unmounted for WSM
- Never repair a mounted volume
- `newfs_msdos` refuses a mounted device; only add a force flag if FreeBSD 4.x already has that pattern

### WSM util

- Probe “not FAT” is a clean non-fatal result so autodiskmount can try the next util
- Mount/repair failures return the same `loadable_fs` status codes HFS uses

### Explicit non-goals

- No kernel-enforced fsck-on-every-mount
- No automatic repair daemon

## Testing and success criteria

### Test media

Prefer disk images over physical floppies:

- FAT12 1.44M floppy image
- FAT16 small disk image (~20–100MB)
- FAT32 larger image (size at/above FreeBSD 4.x `newfs_msdos` FAT32 threshold)
- Images with VFAT LFNs, nested directories, and a volume label

### Verification matrix

| Check | Expectation |
|---|---|
| Format | `newfs_msdos` produces correct FAT type; `fsck_msdos` clean |
| Mount R/O & R/W | create/read/write/delete/rename; clean unmount; `df` sane |
| VFAT | Long names survive remount; 8.3 aliases present |
| Fsck clean | Fresh + after normal use → clean |
| Fsck repair | Deliberate FAT/dir corruption repaired or reported sanely |
| WSM path | `-p` / `-m` / `-r` behave like HFS for FAT volumes |
| Negative | Non-FAT probe fails softly; garbage BPB mount fails; R/O writes fail |
| Integration | Kernel builds with `MSDOS`; `mount -t msdos` finds helper; UFS/HFS/CD9660 smoke OK |

### Done means

On RhapsodiOS, without host-side mount workarounds, you can format, fsck, mount R/W, use VFAT names, and have autodiskmount recognize FAT12, FAT16, and FAT32 volumes.

## Implementation order (high level)

1. Import/adapt FreeBSD 4.11-RELEASE kernel `msdosfs` + VFS/build wiring; smoke mount R/O then R/W on images
2. `mount_msdos` in `msdosfs-1`
3. `newfs_msdos`
4. `fsck_msdos`
5. `msdos.util` + autodiskmount wiring
6. Full verification matrix above

Detailed task breakdown belongs in the implementation plan (next step after this spec is accepted as written).

## Out of scope

- Rewriting the UFS-only `fsck` dispatcher into a multi-type multiplexer
- Host `cdis-3` floppy image authoring changes
- Non-FAT filesystems (exFAT, NTFS)
- Loadable kernel FS module packaging (v1 is compiled into the kernel via `options MSDOS`)
- Locale/codepage expansion beyond FreeBSD 4.x defaults
