# drvAHCI: Bootable AHCI Core for i386

**Date:** 2026-07-29  
**Status:** Approved design, pending written-spec review  
**Components:** `src/drivers-i386/ide/drvAHCI`, `src/kernel-7/bsd/dev`, `src/drivers-i386/ide/drvEIDE`, `src/kernel-7/machdep/i386/swapgeneric.m`  
**Primary reference:** [Serial ATA AHCI 1.3.1 specification](https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/serial-ata-ahci-spec-rev1-3-1.pdf)

## Problem

RhapsodiOS has an i386 `drvEIDE` driver for legacy ATA controllers but no native
AHCI transport. Modern SATA controllers in AHCI mode expose memory-mapped HBA
and per-port registers, DMA command lists, command tables, PRDTs, and received
FIS buffers. Those mechanisms do not fit `drvEIDE`'s task-file I/O ports and
SFF-8038i bus-master engine.

The new driver must boot RhapsodiOS from a SATA disk on QEMU's q35/ICH9 AHCI
controller. It must also detect and read an AHCI-attached ATAPI CD/DVD device.
It must follow the AHCI 1.3.1 rules for the subset it implements while keeping
the existing EIDE hardware path intact.

## Decisions

- Implement a new standalone `drvAHCI` bundle under
  `src/drivers-i386/ide/drvAHCI`.
- Keep `drvEIDE` and `drvAHCI` as separate controller transports.
- Add one kernel-resident `hd` registry shared by EIDE and AHCI disks, following
  NetBSD's separation between controller transports and its common ATA disk
  frontend.
- Target QEMU q35's Intel ICH9 AHCI function (`8086:2922`) first.
- Use AHCI command slot 0 only and do not use NCQ. Each port has at most one
  active command, but different ports execute concurrently.
- Enumerate every set bit in the 32-bit Ports Implemented (`PI`) register.
- Support SATA disks with 512-byte logical sectors, including 512e media.
- Support LBA28 and LBA48. The inherited 32-bit `IODisk` API limits the visible
  capacity to `UINT_MAX` sectors, just under 2 TiB at 512 bytes per sector.
- Support enough ATAPI/SCSI packet behavior to detect, mount, and read CD/DVD
  media after boot.
- Use 32-bit DMA addresses and the shared legacy PCI line interrupt.
- Preserve the existing `hd` device namespace and major numbers 3/15.

## Scope

### Required SATA behavior

- Discover directly attached SATA disks on every implemented port.
- Read IDENTIFY DEVICE data and publish model, serial, firmware, capacity, and
  supported addressing information.
- Execute reads and writes through AHCI DMA using LBA28 or LBA48 as required.
- Flush volatile device write caches.
- Publish physical disks and partitions through DriverKit and the BSD block/raw
  interfaces.
- Boot an FFS root filesystem from `hd0a` on QEMU q35.
- Recover from command, task-file, interface, and timeout failures using bounded
  waits and port-local reset before any controller-wide reset.

### Required ATAPI behavior

- Detect an ATAPI signature and issue IDENTIFY PACKET DEVICE.
- Publish one `IOSCSIController` child for each ATAPI port.
- Support the packet commands needed by the inherited SCSI CD layer: INQUIRY,
  TEST UNIT READY, REQUEST SENSE, READ CAPACITY, READ(10), MODE SENSE, START STOP
  UNIT, and PREVENT/ALLOW MEDIUM REMOVAL.
- Mount an attached ISO image and read known files from it.
- Treat ATAPI media as removable and report media absence or removal cleanly.

### Explicit non-goals

- Native Command Queuing and `PxSACT`.
- More than one outstanding command per port.
- Port multipliers or FIS-based switching.
- Runtime hot-plug child creation. Link removal is detected and handled, but a
  newly attached device is published only after reboot.
- MSI or MSI-X.
- Native 4 KiB logical-sector disks.
- DMA addresses above 4 GiB.
- Aggressive link power management, Partial/Slumber policy, and DEVSLP.
- Enclosure management, command-completion coalescing, and activity LEDs.
- A capacity API wider than the existing 32-bit `IODisk` interface.
- Booting directly from ATAPI media in the first release.

## Architecture

### AHCIController

`AHCIController : IOPCIDirectDevice` owns one PCI AHCI function and only
HBA-global state:

- PCI validation and BAR5/ABAR mapping.
- PCI memory-space and bus-master enablement.
- BIOS/OS ownership handoff when `CAP2.BOH` is advertised.
- AHCI enablement, HBA reset, version/capability capture, and global interrupt
  control.
- Enumeration of the `PI` bitmap.
- Shared-interrupt dispatch to asserted implemented ports.
- A controller recovery lock used only when a failed port cannot be quiesced and
  an HBA reset becomes unavoidable.

The configuration table autoloads the mandatory ICH9 device ID. Probe then
requires PCI class/subclass/programming-interface `01:06:01` before claiming
the device. The transport itself contains no Intel-specific register logic. It
accepts AHCI 1.0 through 1.3.1 and uses the common core subset on later versions,
logging an unrecognized version without assuming optional behavior.

### AHCIPort

One `AHCIPort` object exists for each set `PI` bit. It owns:

- The port queue, condition lock, and active slot-0 request.
- Command-list, received-FIS, command-table, and PRDT memory.
- PxCMD engine state and PxIS/PxIE/PxTFD/PxSIG/PxSSTS/PxSCTL/PxSERR/PxCI state.
- Device classification, IDENTIFY data, online/offline state, and child object.
- Command construction, submission, completion, timeout, diagnostics, and
  recovery.

Ports do not share request queues or command memory. A disk or ATAPI worker may
block waiting for its port while workers on other ports continue to issue and
complete commands.

### AHCIDisk

`AHCIDisk : IODisk` is the SATA disk frontend. It follows the proven `IdeDisk`
behavior for request pooling, asynchronous completion, partition publication,
statistics, and low-memory safety, but uses AHCI-specific class and request
types. It never accesses MMIO registers directly; it submits typed ATA requests
to its `AHCIPort`.

### AHCIATAPIController

`AHCIATAPIController : IOSCSIController` is the ATAPI frontend. It adapts the
existing `AtapiController` SCSI-to-packet behavior under new class names and
submits packets through its `AHCIPort`. There is one target at LUN 0 per ATAPI
port. It does not turn AHCI itself into a SCSI transport; only the ATAPI child
uses the SCSI-facing API.

### Shared ATA `hd` registry

A new kernel-resident `ata_hd_registry` owns the Unix namespace common to
`IdeDisk` and `AHCIDisk`:

- Block major 3 and character major 15 are installed once with common callbacks.
- Thirty-two `IODevAndIdInfo` entries cover minors 0 through 255: 32 units with
  eight partitions each.
- Each slot owns its raw-I/O `struct buf`, registered disk object, and lifecycle
  state.
- Registration allocates the lowest free global unit and returns both the unit
  number and its `IODevAndIdInfo` entry.
- Open, close, read, write, strategy, size, and generic disk ioctls dispatch
  through the registered `IODisk` object.
- EIDE-specific diagnostic ioctls dispatch through an optional transport
  callback and remain unavailable on an AHCI disk unless explicitly supported.
- Duplicate registration is rejected. A unit cannot be removed or reused while
  it or one of its partitions is open.
- Registry allocation, lookup, and removal are serialized by a kernel lock.

`drvEIDE` loses only its private four-entry unit map, private raw-I/O buffers,
unit counter, and device-switch ownership. Its controller, ATA command, timing,
DMA, retry, and recovery paths remain unchanged. Both disk frontends register
with the common layer, producing one collision-free `hd0` through `hd31`
namespace across mixed EIDE and AHCI controllers.

Unit numbering follows controller/device discovery order. QEMU q35 has only the
mandatory AHCI controller, so its first SATA disk is deterministically `hd0`.

## HBA and Port Initialization

Initialization uses bounded waits at every hardware state transition:

1. Match `8086:2922`, verify class `01:06:01`, enable PCI memory and bus-master
   decoding, and map BAR5 as the ABAR.
2. Read VS, CAP, CAP2, and PI. Reject a missing/invalid ABAR or an invalid PI
   value before allocating per-port resources.
3. If `CAP2.BOH` is set, set OS ownership in BOHC and wait for BIOS ownership and
   BIOS-busy state to clear. A timeout fails attach rather than racing firmware.
4. Enter AHCI mode, request `GHC.HR`, wait for reset completion, and reassert
   `GHC.AE` because reset state may clear it.
5. Disable global interrupts and clear stale global interrupt state.
6. For each `PI` bit, stop the command engine by clearing `PxCMD.ST` and waiting
   for `PxCMD.CR` to clear, then clear `PxCMD.FRE` and wait for `PxCMD.FR` to
   clear.
7. Allocate and validate the port DMA arena, then program PxCLB/PxCLBU and
   PxFB/PxFBU with zero upper addresses.
8. Clear PxIS and PxSERR with write-one-to-clear writes. If staggered spin-up is
   advertised, request spin-up for the implemented port.
9. Enable FIS reception before starting command processing.
10. Require an active, present link (`PxSSTS.DET = 3`) before classification.
    Use COMRESET only when the initial link state requires recovery.
11. Use PxSIG plus IDENTIFY DEVICE or IDENTIFY PACKET DEVICE to classify and
    validate the device. Publish the appropriate child only after identification
    succeeds.
12. Enable the selected per-port interrupt mask, then enable global interrupts.

Empty ports remain allocated but stopped and unpublished. Holes in `PI` are
never accessed.

## DMA Memory Model

Each implemented port receives one page-aligned, physically contiguous DMA
arena at attach time. Fixed aligned regions within it contain:

- A 1 KiB command list aligned to 1 KiB.
- A 256-byte received-FIS area aligned to 256 bytes.
- A slot-0 command table aligned to 128 bytes.
- Enough PRDT entries to describe a completely fragmented 128 KiB transfer.

The arena is zeroed and each substructure's virtual-to-physical translation,
alignment, range, and 32-bit addressability are checked before programming the
HBA. PxCLBU, PxFBU, and command-table DBAU stay zero.

Data buffers remain scatter/gather. The PRDT builder walks resident physical
pages, coalesces contiguous ranges, splits entries before AHCI's per-entry byte
limit, writes `DBC = byte_count - 1`, and sets IOC only on the final entry. A
zero-length request, an address above 4 GiB, too many fragments, arithmetic
overflow, or a request larger than 128 KiB is rejected before `PxCI` is set.

No allocation occurs on the command fast path. Request objects, DMA arenas, and
command metadata are preallocated. The driver uses the platform's I/O ordering
primitive before command issue and before consuming HBA-written completion
state.

## Command Construction and Submission

`AHCICommand.c` contains DriverKit-independent builders for hardware structures.
For every command it:

1. Waits with a deadline for PxTFD BSY and DRQ to clear.
2. Zeroes the slot-0 command header and table.
3. Builds a 20-byte Register H2D FIS with the command bit set.
4. Selects LBA28 or LBA48 from the requested ending LBA and device capability.
5. Builds the PRDT and sets command-header CFL, W, A, PRDTL, and CTBA fields.
6. For ATAPI, copies the 12- or 16-byte packet into ACMD and sets the header's
   ATAPI flag.
7. Clears stale PxIS/PxSERR state, initializes PRDBC to zero, enables the chosen
   interrupts, executes the I/O barrier, and sets only bit 0 in PxCI.

The first release uses these ATA commands:

| Purpose | LBA28 | LBA48 |
|---|---:|---:|
| Read | READ DMA (`0xC8`) | READ DMA EXT (`0x25`) |
| Write | WRITE DMA (`0xCA`) | WRITE DMA EXT (`0x35`) |
| Flush | FLUSH CACHE (`0xE7`) | FLUSH CACHE EXT (`0xEA`) |
| Identify | IDENTIFY DEVICE (`0xEC`) | n/a |
| Identify ATAPI | IDENTIFY PACKET DEVICE (`0xA1`) | n/a |
| Packet | PACKET (`0xA0`) | n/a |

The driver does not change device write-cache policy automatically. It uses the
EXT variants whenever a request cannot be represented safely in LBA28 and uses
the flush variant appropriate to the identified device.

## Interrupt Completion

The controller's shared interrupt handler reads the global IS register and
dispatches only bits that are also set in `PI`. For each asserted port, the port
handler:

1. Snapshots PxIS, PxTFD, PxSERR, PxCI, command-header PRDBC, and relevant
   received FIS data before clearing status.
2. Clears the port's write-one-to-clear interrupt bits and acknowledges the
   corresponding global bit.
3. Treats slot 0 as complete only when PxCI bit 0 is clear.
4. Classifies task-file and interface errors before waking the waiter.
5. Records actual transferred bytes without reporting more than the request.

Expected D2H, PIO Setup, descriptor-processed, and ATAPI completion interrupts
are enabled. Task-file error, host-bus fatal/data error, interface fatal/nonfatal
error, overflow, and link-change conditions are always observed. A spurious
interrupt with no active slot is cleared and logged under debug mode without
waking an unrelated request.

## Error Handling and Recovery

All waits use explicit deadlines. There are no unbounded BSY, CR, FR, CI, link,
handoff, or reset loops.

On a timeout or command error, the driver first captures diagnostics and fails
the active request. Recovery then proceeds as follows:

1. Mask the affected port's interrupts.
2. Clear command issue state by stopping the command engine and waiting for CR.
3. Stop FIS reception and wait for FR.
4. Clear PxIS and PxSERR.
5. Perform a port COMRESET through PxSCTL.DET and wait for a valid link.
6. Reprogram the port DMA bases, restart FIS reception and the command engine,
   and re-identify the device.
7. Return the port online only when identification succeeds; otherwise mark it
   offline and fail queued requests.

Healthy ports are not stopped during port-local recovery. If CR or FR cannot be
cleared, or the HBA reports a controller-wide fatal condition, recovery takes a
controller lock, prevents new submissions, fails every active request, performs
one bounded HBA reset, rebuilds every implemented port, and republishes only
devices that re-identify. Failure of that HBA reset leaves the controller
offline; it does not loop.

A runtime link removal fails the active request and marks the child offline.
The initial release clears and contains link-change interrupts but does not
publish a newly inserted device until reboot.

## Disk Capacity and Sector Format

Only 512-byte logical sectors are published. A disk reporting a different
logical sector size is rejected with a clear log message. A 512e disk remains
valid because its logical sector size is 512 bytes.

IDENTIFY words 60-61 supply LBA28 capacity. When LBA48 is supported, words
100-103 supply the native capacity. The driver validates the values and exposes
the smaller of the identified capacity and `UINT_MAX` sectors because
`IODisk` stores disk size and read/write offsets in 32-bit `unsigned` fields.
A larger device attaches with the truncation explicitly logged.

The request path validates both starting block and ending block without
overflow before choosing LBA28 or LBA48.

## Root and Device Namespace

The existing names and majors are preserved:

- Block devices: `/dev/hd0` through `/dev/hd31`, block major 3.
- Raw devices: `/dev/rhd0` through `/dev/rhd31`, character major 15.
- Eight minors per unit, preserving the current partition encoding and live
  partition convention.

Device-node creation becomes idempotent and covers all 32 units. The i386
`swapgeneric.m` root parser accepts one- or two-digit units 0 through 31 plus an
optional partition letter `a` through `h`. Existing names such as `hd0a` retain
their exact meaning.

ATAPI optical devices remain in the inherited SCSI CD namespace and do not
consume `hd` units.

## Source Layout

### New AHCI bundle

`src/drivers-i386/ide/drvAHCI/AHCI.drvproj/AHCI.lksproj` contains:

| File | Responsibility |
|---|---|
| `AHCIRegs.h` | AHCI register offsets, masks, FIS types, and DMA layouts |
| `AHCICommand.h/.c` | FIS, task-file, ATAPI packet, header/table, and PRDT builders |
| `AHCIController.h/.m` | PCI/HBA lifecycle and shared interrupt dispatch |
| `AHCIPort.h/.m` | Port lifecycle, queue, command execution, and recovery |
| `AHCIDisk.h/.m` | Exported `IODisk` behavior |
| `AHCIDiskInternal.h/.m` | Request pools, worker, disk initialization, and transfer splitting |
| `AHCIATAPI.h/.m` | `IOSCSIController` frontend and packet translation |
| `AHCIShared.h` | AHCI-local request/result types and constants |

The bundle also includes normal ProjectBuilder makefiles, load commands,
DriverInfo, localized resources, an ICH9 PCI table, and an idempotent post-load
device-node helper.

### Shared kernel files

| File | Responsibility |
|---|---|
| `src/kernel-7/bsd/dev/ata_hd_registry.h/.m` | Common 32-unit map, devsw callbacks, registration API, and generic disk ioctls |
| `src/kernel-7/machdep/i386/swapgeneric.m` | Parse `hd0` through `hd31` roots |

### Focused EIDE changes

`IdeDisk.m`, `IdeDiskInternal.m/.h`, and `IdeKernel.m/.h` change only enough to
register EIDE disks through `ata_hd_registry` and remove the superseded private
map/devsw state. No EIDE controller or command-engine file changes.

## Verification

All emulator tests use disposable images.

### Host-side command-builder tests

Tests for the plain-C command builder verify:

- Exact structure sizes, field offsets, alignments, and byte ordering.
- LBA28 and LBA48 Register H2D FIS bytes at boundary values.
- Sector-count encoding and the 256-sector per-command limit.
- Read, write, flush, identify, and ATAPI header flags.
- PRDT coalescing, splitting, DBC encoding, IOC placement, fragmentation limits,
  zero length, overflow, and addresses above 4 GiB.
- Sparse PI iteration, including bit 31.
- Registry unit allocation, exhaustion, duplicate registration, lookup, and safe
  removal with mixed mock EIDE/AHCI objects.
- Root parser acceptance of `hd0a`, `hd9h`, `hd10a`, and `hd31h`, plus rejection
  of out-of-range units and invalid partitions.

### QEMU q35 integration

1. Attach a disposable SATA root disk to port 0. Boot to the normal system,
   mount read/write, create and verify a test file, sync, reboot, and remount
   cleanly.
2. Attach a second sparse disk containing a test partition beyond the LBA28
   boundary. Mount it, perform reads and writes, and verify the data so a live
   READ/WRITE DMA EXT path is exercised.
3. Attach an ISO containing known files as an ATAPI CD/DVD. Confirm SCSI CD
   detection, mount the media, and verify the files.
4. Run simultaneous I/O on two SATA ports while reading the CD. Confirm that a
   slow ATAPI command does not block another port and that all data matches.
5. Exercise empty and non-contiguous port layouts. Confirm that only `PI` bits
   are accessed.
6. Remove ATAPI media during a read. Confirm a bounded failure, offline state,
   and no panic or interrupt storm.
7. Repeat boots with debug logging enabled and check for leaked DMA arenas,
   stale interrupt status, unexplained resets, commands left active, or
   controller-wide recovery caused by a healthy port.

### EIDE and shared-namespace regression

- Boot the existing QEMU i440fx/PIIX configuration through `drvEIDE` and confirm
  unchanged disk behavior.
- Verify that EIDE-only and AHCI-only systems both allocate `hd0` first.
- In a mixed-controller configuration when supported by the emulator, attach
  disks through both transports and verify unique global `hd` units, correct
  dispatch, concurrent I/O, and no devsw collision.
- Confirm legacy EIDE diagnostic ioctls still reach EIDE disks and return a
  defined unsupported error on AHCI disks.

### Build acceptance

- Build the kernel changes and both driver bundles with the period i386
  ProjectBuilder/gnumake toolchain on a case-sensitive filesystem.
- Treat compiler warnings about packed layouts, pointer truncation, or implicit
  declarations as failures for the new files.

## Acceptance Criteria

The first release is complete only when all of the following are observed:

- QEMU q35 boots RhapsodiOS from an AHCI SATA `hd0a` root.
- SATA reads, writes, and cache flushes succeed across repeated boots.
- A live transfer beyond the LBA28 boundary proves LBA48 execution.
- An AHCI ATAPI CD is detected, mounted, and read successfully.
- Separate ports make forward progress concurrently.
- Every hardware and firmware wait is bounded.
- Port-local failures do not reset healthy ports unless the HBA itself cannot be
  recovered locally.
- All 32 PI bits and all 32 global `hd` units are handled safely.
- `drvEIDE` still boots the i440fx regression image.
- Mixed EIDE/AHCI publication cannot collide in major numbers or unit maps.

## Risks and Mitigations

### Period DriverKit DMA facilities are limited

The existing EIDE driver relies on direct virtual-to-physical translation and
page-aligned allocation. `drvAHCI` follows the same available mechanism but
validates every address and alignment before giving it to hardware. Preallocated
arenas and a 128 KiB transfer ceiling keep PRDT capacity deterministic.

### Shared `hd` registry touches the working EIDE publication path

The common registry is necessary for collision-free EIDE/AHCI coexistence. The
change is limited to unit allocation, devsw dispatch, and map ownership; EIDE's
hardware behavior stays unchanged. Host registry tests and the i440fx boot are
hard gates.

### HBA reset disrupts all concurrent ports

Controller-wide reset is a last resort protected by a recovery lock. Normal
command errors and timeouts recover the affected port only. If escalation is
necessary, all active requests are failed explicitly before DMA state is rebuilt.

### ATAPI behavior varies by device

The first release supports only the packet commands required for detection and
read-only optical media. It uses the existing RhapsodiOS translation behavior as
the compatibility reference and validates against QEMU's ATAPI device.

### Capacity exceeds the inherited API

LBA48 is implemented, but `IODisk` cannot publish more than `UINT_MAX` sectors.
The driver caps and logs capacity rather than wrapping it. Native support beyond
2 TiB is a separate storage-stack project.

### Optional AHCI features tempt accidental scope growth

Capability bits are recorded and logged, but NCQ, port multipliers, hot-plug
publication, advanced power management, and other optional features remain
disabled until separate designs define their state machines and validation.

## References

- Intel, *Serial ATA Advanced Host Controller Interface 1.3.1*.
- NetBSD `ahcisata(4)`: <https://man.netbsd.org/ahcisata.4>
- NetBSD `ata(4)`: <https://man.netbsd.org/ata.4>
- NetBSD `wd(4)`: <https://man.netbsd.org/wd.4>
- Existing RhapsodiOS EIDE implementation:
  `src/drivers-i386/ide/drvEIDE/EIDE.drvproj/EIDE.lksproj`.
