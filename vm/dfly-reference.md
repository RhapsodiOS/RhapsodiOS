# DragonFly BSD reference guest for HAMMER

DragonFly BSD is the reference implementation for the HAMMER port
(`docs/superpowers/specs/2026-10-17-hammer-design.md`). It makes and fills
reference volumes, and it checks volumes that our code wrote.

## Image

- DragonFly BSD **6.4.2** x86_64 live ISO, from
  `https://mirror-master.dragonflybsd.org/iso-images/`.
  - `dfly-x86_64-6.4.2_REL.iso.bz2`: 272,173,564 bytes, MD5 `906095312c4a4ac0577fb91d5eb87033`.
  - `dfly-x86_64-6.4.2_REL.iso`: 783,974,400 bytes, MD5 `fdab09ac37cf427b8c01de5d54bfd1d7`.
  - Both MD5s match `http://avalon.dragonflybsd.org/iso-images/md5.txt`.
  - The download was approved by the user on 2026-10-17.
- It is kept in the main checkout at `vm/work/dfly/iso/` and is never
  committed. The reference volumes and run directories live in
  `vm/work/dfly/` too, because worktrees can be cleaned up while idle.

## Running it

```sh
python vm/dfly_guest.py run ISO VOLUME SCRIPT OUTDIR [NAME=FILE...]
```

`dfly_guest.py` boots the ISO single-user with `-accel whpx` (set
`DFLY_ACCEL=tcg` where WHPX is unavailable; TCG is far slower). The sequence:

1. Press ESC at the loader countdown, then send `console=comconsole` and
   `menu`, then choose `s`. The loader already mirrors its console on serial.
2. Mount a tmpfs `/tmp` and the FAT transfer disk (`/dev/ad1`) at `/tmp/x`.
3. Type SCRIPT and the FILEs into `/tmp/in` over the serial shell, checking
   each one's MD5.
4. Run SCRIPT in `/tmp/x` with output to `OUT.TXT`.
5. Unmount, then quit through QMP after `query-name` confirms the guest.

VOLUME is the first IDE disk, `/dev/ad0`, and is written in place.

Inputs travel over serial because DragonFly's msdosfs misreads files
pre-written onto `vm/fat32.py`'s one-sector-cluster images. It returns the
right size but wrong bytes. Files DragonFly writes itself read back correctly,
so results come back on the FAT disk.

Ports default to 4761 (serial) and 4762 (QMP). Override them with
`DFLY_SERIAL_PORT` and `DFLY_QMP_PORT`. Each run uses a fresh `-name`.

## Reference volumes (2 GiB raw images)

| Volume | Script | Manifest | Contents |
| --- | --- | --- | --- |
| `ref-main.img` | `vm/dfly-populate-main.sh` | `ref-main.walk` | See below. |
| `ref-dedup.img` | `vm/dfly-populate-dedup.sh` | `ref-dedup.walk` | 32 identical 1 MiB files after `hammer dedup`. |

Each manifest is a second run on the populated volume:

```sh
python vm/dfly_guest.py run ISO VOLUME vm/dfly-walk.sh OUTDIR walk.c=src/hammer-1/tests/hammer_walk.c
```

That run writes `TREE.WLK` to the transfer disk, `OUTDIR/xfer.img`. Copy it
out with `fat32.read_file(xfer, 'TREE.WLK')` to `vm/work/dfly/<volume>.walk`.

`ref-main` contents:

- Directories of 0, 1, 100 and 20,000 entries.
- Names of length 1 and 255.
- Files of 0, 1, 16383, 16385, 1048577 and 64 MiB bytes.
- A 512 MiB sparse file with data at 0, 256 MiB and its last byte.
- 24-byte and 200-byte symlinks.
- A file with three hard links.
- Owner `1234:5678`.
- Modes 0, 4755, 1777 and 0644.
- Files `old` and `future`, given 1970-01-01 and 2100-01-01 mtimes with
  `touch -t`. The times are on disk. `run-diag-4` and `run-diag-5` seemed to
  show `utimes()` lost after a remount, but those remounts were read-only, and
  DragonFly then reports ctime as atime and mtime (`HAMMER_INODE_RO`). The
  manifest is therefore taken from a read-write `noatime` mount. HAMMER
  cannot represent a time before 1970 at all: mtime is unsigned
  microseconds, and DragonFly refuses earlier times.
- A file rewritten three times and a file created then deleted. These are
  separated by `hammer synctid`, so history records exist.

Both populate scripts finish with `hammer show` and `hammer checkmap` on
DragonFly. `vm/dfly-walk.sh` mounts the volume read-only and runs
`hammer_walk`, compiled on DragonFly. Name the input `walk.c` in lower case:
DragonFly's `cc` treats `.C` as C++. The walker clamps mtimes to the 32-bit
range, so DragonFly and Rhapsody manifests compare equal.

`vm/dfly-check.sh` checks a volume another system wrote: `show`,
`checkmap`, then a read-only mount and `ls`.

## Results

| Run | Volume | Result | Date |
| --- | --- | --- | --- |
| `run-main-6` populate | `ref-main.img` | `show` and `checkmap` clean | 2026-10-17 |
| `run-walk-main-2` | `ref-main.img` | read-only mount, mtimes show ctime; kept as `ref-main-ro.walk` | 2026-10-17 |
| `run-walk-dedup-rw` | copy of `ref-dedup.img` | `ref-dedup.walk`, read-write `noatime` mount; identical to the read-only manifest | 2026-10-19 |
| `run-walk-main-rw` | copy of `ref-main.img` | `ref-main.walk`, 20,128 lines (`big/` has 20,000), read-write `noatime` mount | 2026-10-19 |
| `run-dedup-1` populate | `ref-dedup.img` | 1,984 dedup records, 32,505,856 bytes deduplicated; `show` and `checkmap` clean | 2026-10-17 |
| `run-walk-dedup-1` | `ref-dedup.img` | `ref-dedup.walk`, 33 entries, all 32 files with CRC 482699967 | 2026-10-17 |
| `run-check-ours-1` | `ours-newfs.img` (our `newfs_hammer`, Task 3) | DragonFly `show` and `checkmap` clean; read-only mount OK | 2026-10-17 |
