# QEMU debug loop for i386 (offline image injection + kernel serial console)

## Goal

Make the Rhapsody DR2 guest debuggable under modern QEMU, where it currently
hangs during disk driver initialisation and never reaches userland.

Two capabilities, in dependency order:

1. **Get bytes into a disk image that will not boot.** Replace the installed
   `drvEIDE` binary, its config table, and `mach_kernel` by writing the image
   offline from Windows — because a guest that cannot boot cannot be reached
   over SSH, and cannot be used to install anything.
2. **See what the kernel is doing.** Route `printf`, `panic`, and `IOLog` to a
   serial port so output can be captured with scrollback and copy-paste,
   instead of scrolling off a VGA console at the exact moment of failure.

Success = the guest boots to a login prompt under `qemu-system-i386` 11.x, and
kernel diagnostics appear in the terminal that launched QEMU.

## Current failure, from evidence

The boot log establishes what is *not* wrong. `drvEIDE` attaches, `hd0`
registers at 8063 MB, the disk label reads, and `rootdev 300` is set. The boot
loader, the kernel, and driver matching all work. This is not the attach
failure described in §1 of `docs/drivers/drvEIDE-issues.md`.

The wedge is on the primary channel:

```
hd0: using multisector (16) transfers.
hc0: interrupt timeout, cmd: 0xc4
hc0: Read Multiple: error=0x0 secCnt=0x30 secNum=0xe0 cyl=0x373 drhd=0xe0 status=0x58
hc0: ATA command c4 failed. Retrying...
hc0: Resetting drives...
hc0: interrupt timeout, cmd: 0xec
hc0: ATA drive 0 is not present.
```

`0xC4` is READ MULTIPLE. `status=0x58` is DRDY | DSC | **DRQ** with `error=0x0`:
the drive holds data ready and reports no error. The device is healthy; the
driver timed out waiting for an interrupt.

`0xEC` is IDENTIFY DEVICE. That it *also* times out after the reset shows
interrupts on IRQ 14 are permanently dead from the first miss onward, not
merely mishandled for one command. The driver then declares the boot disk
absent, which is unrecoverable.

**Leading hypothesis.** ISA IRQ 14 is edge-triggered, and an ATA device
deasserts INTRQ only when the host reads the Status register. If READ
MULTIPLE's interrupt accounting is off — the device interrupts once per
16-sector block while the driver expects one per sector, or the reverse — a
single interrupt goes unacknowledged, INTRQ stays asserted, and no further
rising edge is ever produced. Every later command times out. The driver's
recovery path does not clear the stuck assertion, which is what
commit 248d3167 addresses.

This is §2 of the issues doc, and it predicts that disabling multisector
restores correct per-sector accounting and unwedges the boot.

**The `hc1` errors are unrelated.** `cmd: 0x0` is the ATAPI packet opcode TEST
UNIT READY and `error=0x20` is sense key 0x2, NOT READY — QEMU's default empty
DVD-ROM with no disc, consistent with `sd0: Disk Not Ready`. That the driver
escalates this to `FATAL` is a real robustness bug, but it is not the boot
blocker and is not addressed here.

## Scope

**In scope:** QEMU invocation changes; a Python image inspector and in-place
writer; the i386 kernel serial console.

**Out of scope:**

- **A general UFS/FFS writer.** Block and inode allocation, cylinder-group
  bitmap maintenance, superblock summary updates, and directory-entry
  insertion are several hundred lines of exacting code whose failure mode —
  silent filesystem corruption — is indistinguishable from a disk driver bug.
  That is the worst possible failure mode for a tool built to diagnose a disk
  driver. Every write in this design is in-place into already-allocated space.
- **KDP / interactive kernel debugging.** `kern/kdp.c`, `kern/kdp_udp.c`, and
  `machdep/i386/kdp_machdep.c` are already compiled into the i386 kernel, but
  nothing on i386 calls `kdp_register_send_receive()` — only PPC's
  `bsd/if/ppc/if_en.c` does. A host-side client exists in
  `src/gdb-1/gdb/gdb-next/`. Tracked as follow-on work.
- **Serial input, a serial getty, or `cngetc` routing.** Output only. A tty on
  COM1 is a convenience, not a debug channel: it is live only after DriverKit
  autoconf, so it sees nothing during early boot, boot-disk driver failure, or
  panic — the entire window that matters.
- **Automating artifact transfer from the PPC build machine.** Artifacts are
  fetched by hand with `pscp`.
- **Fixing the `hc1` ATAPI FATAL escalation.**

This spec fills the i386 kernel console gap noted as follow-on work in
`docs/specs/2026-07-24-virtio-drivers-design.md`.

## Constraints and decisions

- **The guest does not boot.** This is the binding constraint. Anything
  requiring a booted guest — seeding placeholder files, in-guest `cksum`,
  `fsck`, `pscp` install — is unavailable until step 2 succeeds. The design
  must not depend on it.
- **Cheapest-first.** Steps are ordered by cost and gated on results. A
  one-byte config edit may make the guest boot, which restores every
  guest-side capability and makes later steps far easier. Building the full
  injector first would be work done in the dark.
- **The disk is NeXT-labelled, not MBR-partitioned.** The MBR partition table
  in `vm/rhapsody.vmdk` is entirely zero; sector 0 holds only boot0 code.
  A `dlV3` label sits at byte 7680 (sector 15), with the expected duplicates
  at 15360 and 23040, matching `NLABELS 4` in
  `src/kernel-7/bsd/dev/disk_label.h`.
- **Filesystem start = `dl_front + dl_part[n].p_base`**, in `d_secsize`
  sectors. This is not inferred; it is what the boot loader does at
  `src/boot-2/i386/libsaio/disk.c:381`. The inspector's read path is a
  transcription of `libsaio`, which is the reference implementation.
- **Raw working image, no qcow2.** Writing qcow2 from Python would mean
  implementing refcount tables, L1/L2 mapping, and cluster copy-on-write.
  A raw image is directly addressable. `vm/rhapsody.vmdk` is never opened for
  write.
- **Kernel console on COM2 (0x2f8).** COM1 is occupied: the boot log shows
  `ISASerialPort0: Base=0x03f8, IRQ=4, Type=16550AF/C/CF, FIFO=16`. The kernel
  must not squat on a port DriverKit owns.
- **Verification host is `qemu-system-i386` 11.0.50**, whose trace backend is
  `log` — `-trace enable=ide_*` emits plain text with register names decoded,
  needing no `simpletrace.py` post-processing.

## The ladder

Each step is gated: run it, read the result, decide whether the next is still
needed.

| # | Step | Cost | Gate |
|---|------|------|------|
| 0 | QEMU flag changes | minutes | Does removing the CD-ROM change the failure? |
| 0.5 | IDE tracing | minutes | Is QEMU asserting IRQ 14, and does the driver ack it? |
| 1 | Read-only inspector | hours | How much slack do the target files have? |
| 2 | `"Multiple Sectors" = "No"` | hours | **Does the guest boot?** |
| 3 | New `EIDE_reloc` binary | hours | Does the fixed driver boot unaided? |
| 4 | Serial-console kernel | days | — |

**If step 2 boots the guest, steps 3 and 4 become far cheaper**, because
placeholder seeding, `fsck`, in-guest checksums, and `pscp` install all become
available again.

## Step 0 — QEMU invocation

Edit `vm/start-vm.cmd`; do not replace it.

- **Boot `work/test.img`** (raw) instead of `rhapsody.vmdk`.
- **`-nodefaults`**, with `-vga cirrus` and the NIC added back explicitly. This
  removes QEMU's default empty DVD-ROM, eliminating the `hc1` ATAPI TEST UNIT
  READY failures from the log entirely. Verified by `hc1` no longer reporting
  a detected ATAPI drive.
- **`-serial null -serial stdio`.** Port order matters: the first `-serial` is
  COM1 (null, leaving 0x3f8 to `drvISASerialPort`), the second is COM2 at
  0x2f8, which lands in the launching terminal. Inert until step 4.
- **`-rtc base=1999-01-01`**, silencing `WARNING: preposterous time in Real
  Time Clock`. Cosmetic, but it also keeps file timestamps sane.

**Image topology.** `vm/rhapsody.vmdk` stays as the original artifact and is
never opened for write. `vm/golden.img` is produced once by
`qemu-img convert -O raw rhapsody.vmdk golden.img` and is read-only thereafter.
`vm/work/test.img` is what QEMU boots and what Python writes;
`vm/reset-image.cmd` recreates it from `golden.img` with `qemu-img convert -O raw`,
which elides zero ranges.

## Step 0.5 — IDE tracing

`-trace enable=ide_*` plus `-d int`, which together answer the open question
in the hypothesis without modifying the image:

- `ide_ctrl_write` — writes to 0x3F6, showing whether the driver sets `nIEN`
  and leaves it set.
- `ide_status_read` — whether the driver reads Status, which is what deasserts
  INTRQ.
- `-d int` — whether QEMU raises IRQ 14 at all.

This distinguishes "QEMU never raised the interrupt" from "the driver never
acknowledged it". Enabled by a `-Trace` switch, off by default.

## Step 1 — Read-only image inspector

`vm/rhap-image.py`, standard library only. No write path exists in this
component at all.

Three layers:

1. **Label** — read sector 15, unpack `disk_label_t` from
   `src/kernel-7/bsd/dev/disk_label.h` and `struct disktab` from
   `src/kernel-7/bsd/sys/disktab.h`, and compute
   `dl_front + dl_part[n].p_base`.
2. **Superblock** — at partition start + 8192, verifying `fs_magic` 0x011954
   little-endian, then reading `fs_bsize`, `fs_fsize`, `fs_frag`, `fs_ipg`,
   `fs_fpg`, `fs_inopb`, and the cylinder-group geometry.
3. **Path lookup** — root inode 2, walking directory entries, resolving an
   inode's block list across the 12 direct and 3 indirect levels.

Commands: `ls PATH`, `stat PATH`, `cat PATH`, and `slack PATH` — the last
reporting file size, allocated size, and whether the block list contains holes.

It answers three questions the writer depends on, and which cannot currently
be answered any other way:

- Which table the running system actually reads: the bundle's
  `EIDE.config/Instance0.table`, or one under `/private/Devices/System.config/`.
- How much slack `/mach_kernel` and `EIDE_reloc` have.
- Which large files are hole-free, should step 4 need a sacrificial inode.

## Step 2 — Config table edit

Flip `"Multiple Sectors" = "Yes"` to `"No"` in the installed table located by
step 1. `Default.table` in the source tree ships `"Yes"`, which is what
produced `using multisector (16) transfers` and command `0xC4`.

This is the smallest write that could plausibly unwedge the boot: it *shrinks*
the file by one byte, so it fits its existing allocation trivially, and needs
no recompilation, no new kernel, and no allocator.

The writer is `vm/rhap-inject.py`, which imports `vm/rhap-image.py` from step 1
for label, superblock, and path resolution rather than reimplementing them; it
adds only a write path. It rewrites existing blocks and updates `di_size` and
`di_mtime`. **Nothing else is ever mutated** — no cylinder-group bitmaps, no
summary counts, no directory entries, no allocation.

Four safety rules, each failing the run rather than the filesystem:

- Refuse if the payload exceeds the target's allocated size.
- Refuse to open anything but `work/test.img`; path and format are checked.
- Open exclusively. A running QEMU holds the file, so the open fails — this is
  the guard against writing a live image.
- Read back through the same parser after every write and compare bytes;
  a mismatch is a hard error.

The read-back check shares a parser with the writer, so it cannot catch a bug
common to both. The independent check is the guest itself: if the boot loader
finds and loads the kernel and the driver reads its table, the on-disk
structures are correct. Until the guest boots, that check is unavailable, which
is the reason step 2 targets the smallest and most reversible write available.

## Step 3 — New driver binary

Overwrite `EIDE_reloc` inside `/private/Drivers/i386/EIDE.config` with the
build from the PPC machine, fetched by hand with `pscp`.

Gated on step 1's slack report. A rebuilt binary will not generally fall within
one block of the original, so this may not fit in place; if it does not, it
uses the sacrificial-inode mechanism described under step 4.

## Step 4 — i386 kernel serial console

Four files in `src/kernel-7`, one of them new.

**New: `machdep/i386/serial_dbg.c`, `serial_dbg.h`.** A polled 8250/16550
driver — no interrupts, no locks, no allocation, because it must work with
paging disabled, inside an interrupt handler, and after the machine is
otherwise dead.

```
void serial_dbg_init(void);      /* 115200 8N1, FIFO on, IER = 0 */
void serial_dbg_putc(char c);    /* bounded spin on THRE; '\n' -> "\r\n" */
```

`serial_dbg_putc` spins on Line Status Register bit 5 with a **bounded** retry
count and drops the character on expiry. An absent or wedged UART must never
hang the kernel; a debug tool that can deadlock the system is worse than none.

**Port selection.** A global `int serial_dbg_port = 0x2f8;` gets an entry in
the `kernargs[]` table at `machdep/i386/i386_init.c:64`, giving `serial=0x3f8`
or `serial=0` at the boot prompt with no rebuild. `serial_dbg_init()` is called
from `i386_init()` immediately after `getargs()` at line 122 and before
`machine_configure()`, so it is live for effectively the whole kernel.

**Changed: `bsd/dev/i386/cons.c`.** `kprintf()` is currently an empty stub —
`/* nop on intel */` — so every `kprintf` call site in the tree is silent on
i386 today, including the `dprintf` paths in `kdp_machdep.c`. It gets a real
body: format into a stack buffer, then push bytes to `serial_dbg_putc`. It
deliberately does not touch `cnputc` or the tty layer, keeping it safe where
the console is unusable.

**Changed: `bsd/kern/subr_prf.c`.** In `putchar()`, mirror any character
carrying `TOCONS` or `TOLOG`:

```c
#if defined(i386)
	if ((flags & (TOCONS|TOLOG)) && c != '\0' && serial_dbg_port)
		serial_dbg_putc(c);
#endif
```

`putchar()` is the single choke point: `printf`, `panic`, `log`, `addlog`, and
`IOLog` (via `vlog(LOG_INFO)` → `log()`) all pass through it, and `(*v_putc)()`
is the console tap.

The `TOLOG` half is what makes this design work rather than the simpler
alternative of repointing `v_putc`. Once syslogd opens `/dev/klog`, `log()`
stops falling back to `TOCONS`, so a `TOCONS`-only tap goes silent for driver
`IOLog` output — precisely when `drvEIDE` has something to say.

**Changed: `conf/files.i386`.** One line: `machdep/i386/serial_dbg.c standard`.

No new kernel config option and no `MASTER` edit; the boot argument covers
enable and disable.

### Installing a kernel that does not fit

The boot loader takes a kernel filename as the first token at its prompt when
that token is not `key=value` (`src/boot-2/i386/boot2/boot.c`), so a patched
kernel can be installed alongside the stock one and selected by typing
`mach_kernel.serial serial=0x2f8 -v`. Pressing Enter still boots the untouched
`/mach_kernel`.

If the guest boots by then, seed the placeholder from inside it and the problem
disappears:

```bash
dd if=/dev/zero of=/mach_kernel.serial bs=1024k count=8
```

Seed on `work/test.img`, then promote that image to `vm/golden.img` so every
later reset carries the placeholder. Thereafter the injector only ever rewrites
blocks that are already allocated.

If the guest still does not boot, no placeholder can be created and a rebuilt
kernel will not fit `/mach_kernel`'s roughly one block of slack. The fallback
needs no allocator either:

1. Overwrite the data blocks of a large, hole-free, boot-irrelevant file
   identified by step 1 — a swapfile is the natural candidate.
2. Set that inode's `di_size` to the kernel's size.
3. Patch the 4-byte `d_ino` of the `/mach_kernel` directory entry to point at
   it, and set `di_nlink` to 2 so it is a legitimate hard link rather than a
   link-count inconsistency.

Three small writes, no bitmaps, no `d_reclen` surgery, no allocation. The
injector refuses if the sacrificial file has holes.

## Verification

Every check is falsifiable and stated as an expected observation.

**Step 0.** `hc1` no longer reports a detected ATAPI drive; the `preposterous
time` warning is gone. The `hc0` timeout on `0xC4` is expected to persist —
if it disappears, the hypothesis is wrong and the ATAPI path was implicated
after all.

**Step 0.5.** The trace shows either no IRQ 14 assertion after the first
`0xC4` completion, or an assertion with no following Status read. Which one
determines whether the bug is interrupt accounting or acknowledgement.

**Step 1.** `ls /` and `cat` of a known text file (for example `/etc/hostconfig`)
return sensible content. Reading a file whose content is independently known
is what validates the parser before anything depends on it.

**Step 2.** The guest boots past `hd0`, or fails differently. Either outcome is
informative; a *different* failure still confirms the write landed and the
interrupt accounting hypothesis was at least partly right.

**Step 3.** The guest boots with `"Multiple Sectors"` restored to `"Yes"`,
demonstrating the driver fix rather than the workaround.

**Step 4.** In order:
1. The `serial_dbg_init()` banner appears in the terminal before any VGA
   output. If not, the UART setup is wrong and nothing downstream is
   trustworthy.
2. Booting `-s`, boot messages appear on both VGA and serial; a forced panic
   (a bogus `rootdev=`) puts the panic string on serial.
3. Booting multi-user with `"Debug" = "Yes"` in the driver's table, `drvEIDE`
   chatter appears on serial **after** login — that is, after `log_open` is
   true. This is the check that distinguishes this design from a `TOCONS`-only
   tap; if output appears on VGA but not serial, the `TOLOG` half is wrong.
4. Pressing Enter at the boot prompt boots stock `/mach_kernel` unchanged.

## Follow-on work

- **KDP transport for i386.** Wire `kdp_register_send_receive()` into an i386
  NIC driver, mirroring `bsd/if/ppc/if_en.c`, for source-level kernel
  debugging. A complete host-side client already exists in
  `src/gdb-1/gdb/gdb-next/` (`kdp-protocol.c`, `kdp-udp.c`, `remote-kdp.c`).
- **Serial getty on COM1**, for a headless shell once the guest boots.
- **`hc1` ATAPI FATAL escalation**, which turns an empty CD drive into a fatal
  driver error.
- **Automated artifact fetch** from the PPC build machine.
