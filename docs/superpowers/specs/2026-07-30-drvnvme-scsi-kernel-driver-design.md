# drvNVMe: Bootable NVMe-to-SCSI Kernel Driver for i386

**Date:** 2026-07-30

**Status:** Approved

**Component:** `src/drivers-i386/scsi/drvNVMe`

**Primary references:**

- [NVM Express Base Specification 1.4c](https://nvmexpress.org/wp-content/uploads/NVM-Express-1_4c-2021.06.28-Ratified.pdf)
- [QEMU NVMe emulation documentation](https://www.qemu.org/docs/master/system/devices/nvme.html)

## Problem

RhapsodiOS has no NVMe storage driver. The first kernel milestone must support
QEMU's standard NVMe controller on i386 and expose its namespace through the
inherited DriverKit SCSI stack. The existing `SCSIDisk` layer must perform disk
probing, partition discovery, and BSD device publication so the new driver does
not duplicate a disk frontend.

The kernel must be capable of mounting an FFS root filesystem from the NVMe
namespace. During this milestone, a legacy helper disk may load the bootloader
and kernel before the kernel switches to an NVMe root. A future, separately
designed boot system will make the entire boot chain NVMe-native.

## Decisions

- Add a standalone i386 `drvNVMe` loadable driver under
  `src/drivers-i386/scsi/drvNVMe`.
- Implement `NVMeSCSIController : IOSCSIController` and expose namespace ID 1
  as SCSI target 0, LUN 0.
- Target QEMU's default Red Hat/QEMU NVMe PCI identity (`1b36:0010`) and require
  PCI class, subclass, and programming interface `01:08:02` before claiming it.
- Target one controller and one active namespace in the first milestone.
- Use one depth-16 admin queue pair and one depth-16 I/O queue pair.
- Serialize execution so only one I/O command, using CID 0, is active at a time.
- Use a preallocated 128 KiB DMA bounce buffer instead of mapping arbitrary
  SCSI client pages directly into NVMe PRPs.
- Accept only namespaces whose active LBA format has 512-byte logical blocks
  and no metadata or protection information.
- Limit the visible namespace to `UINT_MAX` logical blocks, just under 2 TiB,
  while attaching larger namespaces with an explicit truncation warning.
- Use polling for controller initialization and the legacy shared PCI interrupt
  for normal command completion.
- Reuse `SCSIDisk` without introducing a new shared disk registry or changing
  existing SCSI controller drivers.

## Scope

### Required behavior

- Discover, initialize, disable, reset, and reinitialize the QEMU NVMe 1.4
  controller through its mandatory PCI/MMIO interface.
- Identify the controller and namespace ID 1.
- Publish one non-removable, direct-access SCSI disk at target 0, LUN 0.
- Support the SCSI discovery and disk commands needed by the inherited
  `SCSIDisk` layer.
- Translate SCSI reads, writes, and cache synchronization into NVMe NVM
  commands.
- Mount an FFS root filesystem from `sd0a` when the kernel itself was loaded
  from a temporary legacy helper disk.
- Bound every controller state transition and command wait.
- Recover once from a timeout or corrupt/fatal controller state, then leave the
  namespace stably offline if recovery fails.

### Explicit non-goals

- A bootloader or an entirely NVMe-native boot chain.
- Physical NVMe-controller compatibility beyond behavior exercised by QEMU.
- Multiple NVMe controllers or namespaces.
- More than one active I/O command.
- MSI or MSI-X.
- Direct client-buffer DMA or general scatter/gather PRP construction.
- Native 4 KiB logical blocks.
- Namespace metadata, protection information, or end-to-end data protection.
- Namespace or controller hot-plug.
- Power management or autonomous power-state transitions.
- SMART/health, firmware, security, reservation, or vendor admin commands.
- Dataset Management/TRIM, Write Zeroes, Compare, or Copy.
- A user-facing NVMe admin passthrough interface.
- A capacity interface wider than the inherited 32-bit SCSI disk path.

## Architecture

### NVMeSCSIController

`NVMeSCSIController : IOSCSIController` owns the DriverKit-facing and
controller-wide state:

- PCI identity and class validation.
- PCI memory-space and bus-master enablement.
- BAR0 mapping and MMIO access.
- Controller enable, disable, ready waits, and fatal-status detection.
- Admin and I/O queue allocation, initialization, and doorbells.
- The serialized request worker and one active request.
- Shared PCI interrupt dispatch.
- Timeout detection and controller recovery.
- SCSI target count, maximum-transfer reporting, command execution, and
  `resetSCSIBus`.

The class reports one target. Only target 0, LUN 0 is valid; all other target or
LUN values complete with selection-style failure and are never submitted to
hardware.

### NVMeNamespace

`NVMeNamespace` is internal state owned by the controller rather than a
separately registered DriverKit object. It contains:

- Namespace ID 1 and online/offline state.
- Native and visible logical-block counts.
- Active LBA format and validated 512-byte logical-block size.
- Controller model, serial number, and firmware revision used to synthesize
  SCSI identity data.
- Write-protection and volatile-write-cache information when advertised.
- The last fixed-format SCSI sense value.

The driver records enough identity across reset to ensure that the recovered
namespace remains compatible. A changed namespace size, LBA format, metadata
format, or identity leaves the target offline rather than silently exposing a
different disk beneath mounted filesystems.

### NVMeSCSI translation layer

`NVMeSCSI` is a focused translation unit with no MMIO or PCI responsibilities.
It parses supported CDBs, validates their fields, builds software replies,
constructs typed read/write/flush operations, and maps NVMe completion status
to SCSI status and sense.

### NVMeCommand layer

`NVMeCommand` is plain C where practical. It defines byte-exact command and
completion builders/parsers, queue phase helpers, doorbell offset calculation,
and PRP list construction from an already validated contiguous DMA arena. This
keeps the register-level logic independently testable on the host.

## Controller Initialization

Every hardware transition uses a deadline. Initialization proceeds as follows:

1. Match PCI ID `1b36:0010`, verify class tuple `01:08:02`, enable PCI memory
   decoding and bus mastering, and map BAR0.
2. Read and validate `CAP`, `VS`, and the doorbell-stride information. Require
   the NVM command set, a 4 KiB host page size within `MPSMIN` and `MPSMAX`, and
   the standard 64-byte submission and 16-byte completion entry sizes.
3. If `CC.EN` is set, clear it and wait for `CSTS.RDY` to clear. Treat
   `CSTS.CFS` as fatal.
4. Allocate page-aligned, physically contiguous memory below 4 GiB for the
   depth-16 admin submission and completion queues, depth-16 I/O submission and
   completion queues, fixed PRP list, and 128 KiB bounce buffer.
5. Zero queue memory, set the expected initial completion phase, program `AQA`,
   `ASQ`, and `ACQ`, and configure `CC` for the NVM command set, 4 KiB pages,
   round-robin arbitration, and standard entry sizes.
6. Set `CC.EN` and wait for `CSTS.RDY` without `CSTS.CFS`.
7. Poll admin completions while issuing Identify Controller, Set Features /
   Number of Queues for one I/O pair, and Identify Namespace for NSID 1.
8. Reject an absent or inactive namespace, an invalid active LBA format,
   metadata or protection information, or a logical block size other than 512
   bytes.
9. Create I/O completion queue 1, then I/O submission queue 1. Both have 16
   entries; the completion queue uses the controller's legacy interrupt vector.
10. Enable normal interrupt handling and register the SCSI controller only
    after the namespace is fully validated.

The timeout for ready transitions is derived from `CAP.TO`, whose units are
500 ms. The implementation applies named defensive lower and upper bounds so a
zero, unreasonable, or malformed value cannot create an unbounded or
impractically long boot wait.

## DMA and Queue Model

All controller-visible addresses must fit below 4 GiB. The driver verifies the
virtual-to-physical translation, contiguity, size, and alignment of each queue
and data allocation before programming any address register or command.

The queue arrays have 16 entries so the hardware layout is not tied to a
single-entry queue. The first release nevertheless keeps only CID 0 active.
Submission and completion head/tail values and completion phase are tracked
explicitly and wrapped modulo 16.

The 128 KiB bounce buffer is page-aligned and physically contiguous. PRP1
addresses its first page at the correct byte offset. PRP2 directly addresses a
second page when the transfer fits there; otherwise PRP2 addresses the fixed
PRP-list page containing each remaining data-page address. The PRP list is
rebuilt and validated before each data command. Zero-length DMA, an address
above 4 GiB, an unaligned sector transfer, arithmetic overflow, or a transfer
larger than 128 KiB is rejected before the submission doorbell is rung.

For writes, `IOSimpleMemoryDescriptor` reads exactly the requested bytes from
the supplied client task into the bounce buffer before command submission. For
reads, it writes exactly the successfully transferred bytes back to the client
after completion. A short or failed client copy fails the request without
issuing hardware I/O or reporting untransferred data.

The driver performs the platform's required I/O and memory ordering before
ringing a submission doorbell and before consuming controller-written
completion or data memory. No allocation occurs on the command fast path.

## SCSI Command Translation

The controller implements the following software-only commands:

| SCSI command | Behavior |
|---|---|
| TEST UNIT READY | GOOD when the namespace is online; NOT READY otherwise |
| INQUIRY | Direct-access, non-removable disk with synthesized vendor/product/revision |
| REQUEST SENSE | Return and clear the cached fixed-format sense value |
| READ CAPACITY(10) | Return the last visible LBA and 512-byte block length |
| MODE SENSE(6) | Return the minimal supported header/pages needed by `SCSIDisk` |
| START STOP UNIT | Validate fields and succeed as a no-op for the fixed namespace |
| PREVENT/ALLOW MEDIUM REMOVAL | Validate fields and succeed as a no-op |

The following commands issue NVMe I/O:

| SCSI command | NVMe command |
|---|---|
| READ(6), READ(10) | NVM Read |
| WRITE(6), WRITE(10) | NVM Write |
| SYNCHRONIZE CACHE(10) | NVM Flush |

READ/WRITE(6) uses the SCSI rule that transfer length zero represents 256
blocks. READ/WRITE(10) length zero is a successful zero-block operation. Every
request validates CDB length, reserved fields, direction, byte count, starting
LBA, ending LBA, visible-capacity bounds, and multiplication/addition overflow.
The maximum data transfer is 128 KiB, or 256 logical blocks. The controller's
`maxTransfer` reports that limit so `SCSIDisk` splits larger transfers.

Unsupported commands or unsupported service actions complete with CHECK
CONDITION and ILLEGAL REQUEST sense. Software commands never touch the NVMe
queues.

## Submission and Completion

`executeRequest:buffer:client:` initializes the output fields, validates the
target and LUN, and serializes the request through a controller worker. The
worker performs software translation or prepares the bounce buffer and one I/O
submission entry. Before submission it clears the destination queue slot,
assigns CID 0, records the expected request state and deadline, executes the
required ordering primitive, advances the SQ tail, and rings its doorbell.

The normal interrupt handler examines the I/O completion entry at the current
CQ head. An entry is new only when its phase bit matches the expected phase. A
valid completion must name I/O SQ 1, contain the expected SQ head, and carry CID
0 for the active request. The handler snapshots the completion, advances and
wraps the CQ head, toggles phase at wrap, rings the CQ-head doorbell, and wakes
the worker. A shared interrupt with no matching completion is ignored safely.

The worker parses the completion status, copies read data to the client only
after successful completion, records exact transferred bytes, and completes the
SCSI request once. It never reports more bytes than requested.

Initialization admin commands use the same completion parsing and phase rules
but poll with deadlines before normal interrupts are enabled.

## Status and Sense Mapping

Successful commands return `SR_IOST_GOOD`, SCSI GOOD status, and an exact byte
count. NVMe errors map to stable fixed-format sense categories:

| NVMe/result category | SCSI sense |
|---|---|
| Invalid opcode, invalid field, invalid namespace, or LBA range | ILLEGAL REQUEST |
| Namespace unavailable or not ready | NOT READY |
| Namespace write protected | DATA PROTECT |
| Media or unrecovered read/write failure | MEDIUM ERROR |
| Internal error or PCI/data-transfer failure | HARDWARE ERROR |
| Aborted command | ABORTED COMMAND |

CHECK CONDITION includes valid sense data in `IOSCSIRequest.senseData` and
caches the same value for REQUEST SENSE. The translator sets the most specific
available additional-sense code without exposing raw NVMe status values as a
new ABI.

## Timeout and Recovery

Normal SCSI command deadlines honor a positive `IOSCSIRequest.timeoutLength`.
When the caller supplies no usable timeout, named defaults apply: ten seconds
for reads and writes and thirty seconds for Flush. Controller-ready and admin
command waits have separate named deadlines.

A normal NVMe command error completes the SCSI request without resetting the
controller. A command timeout, `CSTS.CFS`, malformed completion, wrong queue or
CID, or inconsistent queue state triggers one controller recovery:

1. Mask controller interrupts and prevent new submissions.
2. Fail the active SCSI request exactly once.
3. Clear `CC.EN` and wait for `CSTS.RDY` to clear.
4. Clear queue and PRP memory and reset software head, tail, and phase state.
5. Reprogram and enable the admin queue.
6. Re-identify the controller and namespace.
7. Require the namespace identity, capacity, active 512-byte format, metadata
   configuration, and protection configuration to remain compatible.
8. Recreate the I/O completion and submission queues and re-enable interrupts.
9. Resume queued work only after all validation succeeds.

`resetSCSIBus` invokes the same serialized recovery path. A failed recovery
leaves the namespace offline and later commands return NOT READY. Recovery is
not retried in a loop; unloading or rebooting is required for another attach
attempt.

## Capacity

The driver reads the namespace's native size from Identify Namespace data and
validates that it is nonzero. It exposes the smaller of that value and
`UINT_MAX` logical blocks. READ CAPACITY(10) returns visible-block-count minus
one as the last LBA and 512 as the block length.

A larger namespace attaches with one explicit warning that includes native and
visible capacities. All request bounds are checked against the visible count,
so no CDB can access truncated blocks through this driver.

## Source Layout

`src/drivers-i386/scsi/drvNVMe/NVMe.drvproj/NVMe.lksproj` contains:

| File | Responsibility |
|---|---|
| `NVMeRegs.h` | Register offsets, masks, opcodes, status codes, and packed hardware structures |
| `NVMeCommand.h/.c` | Command/completion encoding, queue phase helpers, doorbells, and PRP construction |
| `NVMeTypes.h` | Internal namespace, request, queue, and recovery state |
| `NVMeController.h/.m` | PCI/MMIO lifecycle, queues, worker, interrupt handling, and recovery |
| `NVMeSCSI.h/.m` | CDB parsing, synthetic replies, NVMe operation translation, and sense mapping |

The bundle also contains the standard ProjectBuilder makefiles, `PB.project`,
load commands, `DriverInfo`, `Default.table`, localized resources, and package
metadata. The configuration table includes the QEMU PCI ID; probe still checks
the NVMe class tuple before claiming the function.

No existing kernel or SCSI source is expected to change. If integration shows
that the driver cannot load early enough for root discovery, that is a design
issue requiring explicit review rather than an unplanned kernel modification.

## Verification

All emulator testing uses disposable disk images.

### Host-side tests

Plain-C and focused translation tests verify:

- Exact sizes, offsets, alignment, reserved-zero behavior, and byte ordering of
  submission and completion structures.
- Doorbell offsets for the reported `DSTRD` value.
- Admin Identify, Set Features, Create I/O CQ, and Create I/O SQ commands.
- NVM Read, Write, and Flush command encoding.
- Queue head/tail wrapping and completion phase toggling at depth 16.
- Rejection of wrong CID, SQ ID, phase, or impossible SQ head values.
- PRP1, direct PRP2, and PRP-list construction at page and 128 KiB boundaries.
- Rejection of zero, overlarge, overflowing, misaligned, and above-4-GiB DMA
  descriptions.
- READ/WRITE(6) and READ/WRITE(10) CDB decoding, including zero-length rules.
- LBA and byte-count overflow, final-visible-LBA access, and capacity truncation.
- Synthetic INQUIRY, READ CAPACITY, MODE SENSE, TEST UNIT READY, REQUEST SENSE,
  START STOP, and PREVENT/ALLOW behavior.
- NVMe-status-to-SCSI-sense mapping and cached-sense clearing.
- Recovery state transitions, one-shot request completion, successful rebuild,
  and stable offline behavior after forced rebuild failure.

### QEMU integration

1. Configure QEMU with one standard NVMe controller and one namespace backed by
   a disposable 512-byte-sector image. Load the kernel from a legacy helper
   disk, detect the namespace as `sd0`, and mount an FFS root from `sd0a`.
2. Create and verify files, issue sync, reboot, remount, and verify checksums.
3. Exercise 512-byte, page-crossing, 128 KiB, first-LBA, and final-visible-LBA
   reads and writes.
4. Attach test namespaces configured as native 4 Kn, metadata-bearing, absent,
   or malformed and confirm clean attach rejection with specific diagnostics.
5. Use a test build to suppress one completion or force fatal controller state.
   Confirm one bounded reset and successful later I/O, or a stable offline state
   when reset is forced to fail.
6. Attach a sparse namespace larger than 2 TiB. Confirm the truncation warning,
   the READ CAPACITY result, successful I/O to the final visible LBA, and
   rejection of any request whose end exceeds it.

## Success Criteria

The milestone is complete when the new bundle builds in the repository's
historical driver environment; all host-side tests pass; QEMU exposes one
512-byte namespace as SCSI target 0/LUN 0; RhapsodiOS mounts, modifies, syncs,
and cleanly remounts an FFS root on `sd0a`; boundary transfers are data-correct;
and timeout/fatal recovery either restores I/O once or leaves a deterministic
offline target without hangs or repeated resets.
