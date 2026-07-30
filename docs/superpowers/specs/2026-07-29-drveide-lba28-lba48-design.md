# drvEIDE: LBA28 and LBA48 disk addressing

**Date:** 2026-07-29

**Status:** Approved

**Component:** `src/drivers-i386/ide/drvEIDE`

## Problem

`drvEIDE` already emits 28-bit LBA taskfiles when its configuration selects
LBA, and every shipped driver table does so. However, that behavior is implicit,
has no boundary tests, obtains capacity only from IDENTIFY words 60-61, and has
no support for 48-bit ATA commands. The result is a practical ceiling of
`0x10000000` 512-byte sectors (128 GiB) even though the surrounding DriverKit
block interfaces can represent almost 2 TiB.

Make LBA28 behavior explicit and tested, and add read and write support through
the 32-bit DriverKit sector ceiling on LBA48-capable drives. Preserve CHS and
legacy LBA28 behavior for existing hardware.

## Goals

- Preserve CHS support for drives that do not advertise LBA.
- Preserve the existing LBA28 command path for requests it can represent.
- Detect LBA48 and obtain its capacity from IDENTIFY DEVICE.
- Support PIO, multiple-sector PIO, bus-master DMA, and read-verify operations
  above the LBA28 boundary.
- Advertise at most `0xffffffff` sectors until DriverKit and filesystem block
  interfaces are widened.
- Preserve the public `IDEDIOCREQ` structure and existing retry, recovery, and
  transfer-mode fallback behavior.
- Add deterministic tests for capacity parsing, command selection, taskfile
  construction, and register-write order.

## Non-goals

- More than `0xffffffff` sectors, or exactly 2 TiB at 512 bytes per sector.
- Widening DriverKit, disklabel, filesystem, or user-facing ioctl block types.
- Native Command Queuing, SATA, or AHCI support.
- Increasing the existing 256-sector maximum transfer size.
- Adding an LBA48 replacement for the obsolete SEEK command.
- Changing ATAPI addressing or capacity behavior.

## Selected approach

Follow NetBSD's per-request model in a form appropriate to this older driver.
Record both LBA28 and LBA48 capabilities and capacities, retain the legacy
command when a request fits in LBA28, and use an EXT command only when the
request crosses the LBA28 boundary. Centralize both command conversion and
taskfile emission.

This is preferred to always using EXT commands because the boot area and every
small disk continue through the existing, well-exercised path. It is preferred
to separate LBA48 transfer routines because the data, interrupt, retry, and
recovery behavior remains shared rather than duplicated.

## IDENTIFY data and capacity

Keep `ideIdentifyInfo_t` exactly 512 bytes while naming the fields needed by the
feature:

- command-set word 86 supplies the enabled LBA48 bit (`0x0400`);
- words 100-103 supply the LBA48 user-addressable sector count;
- words 60-61 remain the LBA28 sector count.

Split the existing reserved arrays around those words rather than inserting
new storage. Treat LBA48 as usable only when the enabled bit is present and the
reported words 100-103 form a nonzero capacity. If the value exceeds the
DriverKit representation, publish `0xffffffff` sectors and log the clamp once.
If the LBA48 value is invalid, fall back to the existing valid LBA28 or CHS
capacity rather than exposing a zero-sized disk.

Each drive records whether LBA48 is usable. `ideDriveInfo_t.total_sectors` and
`IODisk`'s disk size remain 32-bit, preserving their current ABI. A drive may
therefore expose at most `0xffffffff` 512-byte sectors, one sector short of
2 TiB.

## Private taskfile model

Do not enlarge `ideRegsVal_t`, because it is embedded in the public
`IDEDIOCREQ` ioctl. Add a private ATA taskfile value containing:

- the existing low-order register image;
- high-order feature, sector-count, LBA-low, LBA-mid, and LBA-high bytes; and
- an LBA48 flag.

A pure builder takes the drive addressing mode, block, and sector count and
returns either a CHS, LBA28, or LBA48 taskfile. It also validates that the
request is nonempty, fits the selected address format, and does not exceed the
32-bit advertised sector range. Validation must use subtraction/comparison,
not `block + count`, so a direct ioctl cannot wrap a 32-bit addition.

For a 256-sector LBA28 request, the low sector-count byte remains zero. For a
256-sector LBA48 request, the 16-bit sector count is `0x0100`, so the previous
count byte is one and the current count byte is zero.

A single taskfile writer performs the hardware programming. LBA48 writes the
high-order (previous) feature, count, and three LBA bytes first, then the
low-order (current) feature, count, and three LBA bytes, then issues the
command. The device/head register contains only the fixed bits, selected drive,
and LBA bit for an LBA48 command; it does not carry address bits 24-27.

The writer mirrors the low-order values into the existing `ideRegsVal_t`
error-reporting field so public ioctl behavior remains compatible.

## Per-request command selection

The request's last sector determines its addressing format. Use LBA48 only when
the end-exclusive range is greater than `0x10000000`; otherwise preserve LBA28
or CHS. A request that requires LBA48 is rejected before hardware access when
the selected drive does not support it.

After the existing DMA and multiple-sector capability requalification,
`ideExecuteCmd` maps commands as follows when LBA48 is required:

| Existing command | LBA48 command |
|------------------|---------------|
| READ `0x20` | READ SECTORS EXT `0x24` |
| WRITE `0x30` | WRITE SECTORS EXT `0x34` |
| READ MULTIPLE `0xc4` | READ MULTIPLE EXT `0x29` |
| WRITE MULTIPLE `0xc5` | WRITE MULTIPLE EXT `0x39` |
| READ DMA `0xc8` | READ DMA EXT `0x25` |
| WRITE DMA `0xca` | WRITE DMA EXT `0x35` |
| READ VERIFY `0x40` | READ VERIFY SECTORS EXT `0x42` |

The PIO, multiple-sector, and DMA routines issue the selected opcode and use
the common taskfile writer, but retain their current data phases, interrupt
handling, and error checks. `performDMA:` must no longer reconstruct a legacy
taskfile or hard-code only the legacy DMA opcodes.

SEEK remains a legacy CHS/LBA28 operation and rejects addresses beyond the
LBA28 boundary. Normal disk reads and writes do not depend on SEEK.

## Retries and fallback

Each retry rebuilds the taskfile after the existing command requalification.
If DMA is demoted to PIO, or multiple-sector operation is disabled, the request
keeps the same logical block range and LBA28/LBA48 choice while receiving the
corresponding replacement opcode. No retry may silently truncate an LBA48
address to LBA28.

Existing reset, interrupt recovery, data-transfer, and mode-demotion behavior
is otherwise unchanged. Diagnostic logging should include whether a failed
request used LBA28 or LBA48 and its logical block/count, while retaining the
current low-order register dump.

## Range handling

Both normal disk I/O and `IDEDIOCREQ` must reject a zero-length or out-of-range
request before issuing a command. Replace the overflow-prone
`deviceBlock + blocksReq` check in the disk path with an equivalent
subtraction-based check. Requests partially beyond the advertised end retain
the existing short-transfer behavior only when their starting block is valid;
requests beginning beyond the end are rejected.

The LBA28 maximum address is `0x0fffffff`, so a one-sector request there uses
the legacy command. A request beginning there with two sectors crosses the
boundary and uses LBA48. The upper DriverKit boundary receives the same explicit
overflow and end-of-device checks.

## Validation

### Host-side deterministic tests

Keep address calculation and opcode conversion in small C helpers that can be
compiled without DriverKit hardware access. Test:

- IDENTIFY word 86 capability detection;
- words 60-61 and words 100-103 capacity assembly;
- zero/invalid LBA48 capacity fallback and `0xffffffff` clamping;
- CHS and representative LBA28 taskfiles;
- the last LBA28 sector, a request crossing the boundary, and the first pure
  LBA48 request;
- single-sector and 256-sector count encoding in LBA28 and LBA48;
- every PIO, multiple, DMA, and read-verify opcode conversion in the table;
- rejection of unsupported LBA48, zero count, arithmetic wrap, and requests
  beyond advertised capacity; and
- exact high-order-then-low-order port-write sequences using a recording test
  callback rather than real `outb` instructions.

Tests must verify the full taskfile byte sequence, not only the reconstructed
numeric LBA, so reversed high/current write order is detectable.

### Target and emulator checks

Use disposable sparse images, as required by the repository debugging policy:

1. Boot and exercise the existing small reference disk through PIO,
   multiple-sector PIO, and DMA where available. Transfer modes and command
   opcodes must remain unchanged.
2. Attach a 16 GiB image and read/write known patterns near its beginning and
   end, confirming the LBA28 path handles the historical 8 GiB boundary.
3. Attach an image larger than 128 GiB and read/write known patterns immediately
   below and above sector `0x10000000`, confirming legacy and EXT opcodes on the
   respective sides.
4. Confirm that a request spanning the boundary completes without truncation or
   wrap and that a request beyond the advertised end is rejected without disk
   access.

Filesystem or partition-format limitations are not evidence of an ATA command
failure. Where necessary, use the raw disk or controller request interface to
validate boundary sectors independently of filesystem support.

## Expected implementation scope

The implementation should be surgical and is expected to touch:

- `ata_extern.h` for IDENTIFY field names, capability bits, EXT opcodes, and the
  private/public boundary declarations appropriate to the current layout;
- `IdeCnt.h` for per-drive LBA48 state and a private taskfile type if that type
  does not live in the Commands category header;
- `IdeCntCmds.h` and `IdeCntCmds.m` for taskfile construction, command mapping,
  PIO/multiple command issue, retries, and direct-request validation;
- `IdeBMIDE.m` for LBA48 DMA command issue through the shared taskfile path;
- `IdeCntInit.m` for capability and capacity selection;
- `IdeDiskInternal.m` for overflow-safe disk range checking; and
- a focused host-side addressing test source and its test build entry.

Do not change configuration tables, ATAPI code, chipset timing back-ends, or
unrelated disk behavior.

## Risks and mitigations

- **High/current register halves are reversed.** One writer owns the sequence,
  and recording tests compare every port write in order.
- **A retry loses the EXT opcode.** Rebuild addressing and opcode selection after
  every transfer-mode fallback and test DMA/multiple demotion above the boundary.
- **The ioctl ABI changes accidentally.** Keep `ideRegsVal_t`, `ideIoReq_t`, and
  `ideDriveInfo_t` sizes unchanged; use a private taskfile structure.
- **Capacity arithmetic wraps.** Clamp IDENTIFY capacity before publication and
  use subtraction-based request bounds checks.
- **Old disks regress.** Do not use EXT commands below the boundary, and run the
  existing small-disk and 16 GiB LBA28 checks.
- **Filesystem limits obscure driver validation.** Use raw-sector tests on
  disposable images before interpreting mount or partition failures.

## References

- [NetBSD per-request LBA48 selection](https://github.com/NetBSD/src/blob/trunk/sys/dev/ata/wd.c#L699-L707)
- [NetBSD IDENTIFY capability and capacity parsing](https://github.com/NetBSD/src/blob/trunk/sys/dev/ata/wd.c#L363-L401)
- [NetBSD legacy-to-EXT opcode conversion](https://github.com/NetBSD/src/blob/trunk/sys/dev/ata/atareg.h#L133-L167)
- [NetBSD high-order/current taskfile writer](https://github.com/NetBSD/src/blob/trunk/sys/dev/ic/wdc.c#L1744-L1805)
