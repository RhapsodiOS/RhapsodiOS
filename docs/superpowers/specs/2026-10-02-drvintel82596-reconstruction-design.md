# drvIntel82596 i386 reconstruction

## Intent and approval state

Complete the decompilation and reconstruction of
`src/drivers-i386/network/drvIntel82596` using `tools/binrecon` and IDA.
The result must be readable, buildable C/Objective-C whose interfaces,
data layouts, and behavior are accounted for against Apple's shipped
i386 kernel driver.

On 2026-10-02 the user selected the kernel driver and package scope, excluding
the separate Configure.app inspector. The user then approved the proposed
architecture: recover all five driver classes and hardware paths, restore
the build and package, and maintain function-by-function reconstruction
evidence with reference/rebuilt comparisons. This spec records that design.
Written-spec review and implementation planning follow; implementation has
not started.

Completion requires all 84 handwritten reference functions implemented and
reviewed, the two generated methods checked in the rebuild, a successful
i386 guest build, and explained comparison differences. Resolving names or
compiling the existing stubs does not meet this standard. Hardware operation
is a separate validation claim requiring a compatible device or emulator.

## Reference and observed baseline

Authoritative kernel reference:

`C:\Users\raynorpat\Downloads\test\Drivers\i386\Intel82596NetworkDriver.config\Intel82596NetworkDriver_reloc`

| Property | Verified value |
| --- | --- |
| Architecture / byte order | i386 / little endian |
| File size | 69,108 bytes |
| SHA-256 | `BE6AED4264AB64119188AEE6A82AAB415940010DCF5705B6C241266AF45D0A11` |
| Text section | `__TEXT,__text`, address `0x0`, size `0x4240` (16,960 bytes) |
| Defined text symbols / IDA functions | 86 / 86 |
| Handwritten Objective-C methods | 75 |
| Handwritten C functions | 9 |
| Generated methods | 2 |
| Loaded Server name | `Intel82596NetworkDriver` |
| Loaded Server instance symbol | `Intel82596NetworkDriver_instance` |
| Loaded Server version | `2` |
| Load commands | No MIG handler/interface; `WIRE` |

The function partition and binary identity were checked independently with
binrecon's Mach-O reader and IDA enumeration. Initial IDA pseudocode was
inspected for `_init596`, `coldInit`, buffer-pool initialization, and PRO/10
PCI initialization. The `_init596` disassembly was also inspected: its
physical-address calls illustrate why decompiler argument lists need
assembly review rather than literal transcription.

Binrecon's Objective-C metadata walker currently returns 76 method addresses
for this artifact because it omits the valid address-zero
`+[CogentEMaster probe:]`. The text symbol and IDA both identify that function.
Include it explicitly in the inventory; the correct total is 77 Objective-C
methods including the two generated methods. A metadata omission must not
reduce the required partition.

The current directory contains five `.m` files, a `Default.table`, and flat
makefiles. It has no headers, Project Builder manifests, nested driver/kernel
projects, package metadata, or reconstruction evidence. The preamble lists
`Intel82596NetworkDriver.m` and `.h`, neither of which exists, and the wrapper
uses the old `/NextDeveloper/Makefiles/app` bundle mechanism.

The source imports `driverkit/IOEthernetDriver.h`, which is absent from this
tree. DriverKit provides `IOEthernet.h`. Current inline class declarations
also disagree with the shipped metadata, including invented subclass fields
and repeated incomplete base declarations. Several base methods are explicit
stubs even though the reference inherits those methods from DriverKit.

## Scope and source organization

Retain the repository directory and the five existing implementation
filenames. Restore a Project Builder Aggregate containing
`Intel82596NetworkDriver.drvproj`, with a nested
`Intel82596NetworkDriver.lksproj` Kernel Server. Move the implementation units
into the kernel project as part of this necessary build repair; register the
same files in Makefile and `PB.project` lists.

| Source unit | Responsibility |
| --- | --- |
| `Intel82596.h` / `.m` | Shared base class, lifecycle, public DriverKit methods, queues, receive/transmit, multicast, power management, debugger entry points |
| `Intel82596Private.h` | Recovered chip descriptors, constants, helper declarations, and the reference `Private` category |
| `Intel82596Buf.h` / `.m` | Buffer-pool class, spinlock, page allocation, netbuf wrapping and recycling |
| `CogentEMaster.h` / `.m` | Cogent EISA probe, initialization, IRQ latch, channel attention, port commands |
| `IntelEEFlash32.h` / `.m` | Flash32 EISA probe, initialization, interrupt handling, connector detection and checksum |
| `IntelPRO10PCI.h` / `.m` | PRO/10 PCI probe, initialization, PLX bridge, connectors, interrupt gating and reset |

Implement the `Intel82596(Private)` category in `Intel82596.m`; a separate
source unit is unnecessary. Place the nine standalone C helpers with their
consuming driver or buffer/adapter source. Preserve reference symbol names
and linkage after accounting for the Mach-O C underscore prefix:

| Mach-O symbol | Source name | Linkage |
| --- | --- | --- |
| `_IOIsPhysicallyContiguous` | `IOIsPhysicallyContiguous` | external |
| `_IOMallocPage` | `IOMallocPage` | external |
| `_IOMallocNonCached` | `IOMallocNonCached` | external |
| `__resetFunc` | `_resetFunc` | external |
| `_getNetBuffer` | `getNetBuffer` | external |
| `_recycleNetbuf` | `recycleNetbuf` | local |
| `_card_irq` | `card_irq` | local |
| `_get_connector_type` | `get_connector_type` | local |
| `_set_connector_type` | `set_connector_type` | local |

Use direct Objective-C class references for imported kernel classes, matching
the reference's class linkage. Share real headers between subclasses instead
of redeclaring the base class in each implementation.

The separate 26,328-byte `Intel82596NetworkDriver` user-space executable,
its four `Intel82596Inspector` methods, and its inspector nib are outside
the approved scope. Do not ship the original executable as reconstructed
source or leave an inspector resource dependency on an absent implementation.
Kernel configuration, localizable strings and help resources are in scope.
Other network drivers and general kernel/DriverKit changes are outside scope
except a demonstrated compatibility blocker documented for review.

## Objective-C ABI and instance layouts

The required function groups are:

| Owner | Handwritten methods |
| --- | --- |
| `CogentEMaster` | 5 |
| `Intel82596` main class | 32 |
| `Intel82596(Private)` | 13 |
| `Intel82596Buf` | 4 |
| `IntelEEFlash32` | 8 |
| `IntelPRO10PCI` | 13 |
| Total | 75 |

Recover selectors, return types, argument encodings, superclass calls and
category ownership from metadata and instruction use. Use the symbol
inventory to supplement the address-zero metadata omission. IDA display
names that omit category names are aliases of the same function, not extra
entries.

The reference defines these layouts:

| Class | Superclass | Reference instance size | Own fields |
| --- | --- | --- | --- |
| `Intel82596` | `IOEthernet` | `0x200` | 38 fields beginning at `0x174` |
| `CogentEMaster` | `Intel82596` | `0x200` | none |
| `IntelEEFlash32` | `Intel82596` | `0x200` | none |
| `IntelPRO10PCI` | `Intel82596` | `0x208` | `connector` at `0x200`, `RJ45Only` at `0x204`, `autoDetectedPort` at `0x205` |
| `Intel82596Buf` | `Object` | `0x28` | 10 fields beginning at `0x4` |

Important base fields include 16-bit `ioBase` at `0x174`, signed `irq` at
`0x178`, the six-byte `myAddress` at `0x17c`, `chipRev` at `0x184`,
`networkInterface` / `bufferPool` / `xmtQueue` at `0x188` / `0x18c` / `0x190`,
and six one-byte flags at `0x194` through `0x199`.

Shared-memory state occupies `0x19c` through `0x1b0`; SCP, ISCP, SCB and
self-test pointers occupy `0x1b4` through `0x1c0`. Transmit-list state occupies
`0x1c4` through `0x1d4`; debugger TCB, packet and physical address occupy
`0x1d8` through `0x1e0`. Receive-list state begins at `0x1e4`; descriptor
zeroing sizes occupy `0x1f0` through `0x1f8`, followed by `fullDuplexMode`
at `0x1fc`.

The buffer pool has `initFlag` / `freeInProgress` at `0x4` / `0x5`,
`freeList` / `numFree` at `0x8` / `0xc`, `bufSize` / `bufSizeUser` at
`0x10` / `0x14`, `bufCount` at `0x18`, allocation pointer / size at
`0x1c` / `0x20`, and `freeListLock` (`NXSpinLock`) at `0x24`.

Reconcile these historical absolute offsets with the target's inherited
DriverKit layout before implementing. Preserve each class's own field order,
widths and alignment; do not overwrite inherited storage or insert guessed
padding to force a historical total. If the repository's superclass layout
differs, record its effect on offsets and rebuilt instructions as an explicit
compatibility divergence, with evidence that the recovered driver-owned
layout and behavior are preserved.

Remove invented overrides only after confirming their absence from the
reference and their inherited implementation in the target. This includes
the current base initialization, timeout, running-state and generic
interrupt-control stubs. Actual reference no-op methods must remain present.

Use compile-time size/offset checks supported by the historical C compiler
for hardware descriptors and buffer headers. Verification must use a
32-bit target; native 64-bit host pointers cannot validate this ABI.

## Hardware structures and memory ownership

Recover SCP, ISCP, SCB, command blocks, TCB/TBD and RFD/RBD layouts from
allocation sizes, pointer arithmetic, physical-address conversions,
initializers, and interrupt/debugger paths. Give named fields to recovered
offsets; preserve access widths and volatile hardware-visible accesses.
Resolve ambiguous packing and pointer/integer use with disassembly.

Initial facts from decompilation, to cross-check during implementation:

- `_init596` zeroes a 12-byte SCP, an 8-byte ISCP and a 40-byte SCB,
  writes the SCP configuration word `0x54`, marks ISCP busy, supplies
  physical addresses, and polls the busy byte with 1 ms delays.
- `coldInit` allocates noncached shared memory, reserves 28 bytes for
  a 16-byte-aligned SCP and 24 bytes for a 16-byte-aligned self-test area,
  allocates 864 bytes for TCBs, 108 bytes for the debugger TCB, 1,024 bytes
  for RFDs, and 1,514 bytes for the debugger packet buffer.
- `Intel82596Buf` rounds the requested user buffer size to at least
  1,514 bytes and then four-byte alignment, adds 24 bytes of overhead,
  and packs buffers into pages without letting a buffer cross a page.
- Each buffer's prefix holds its owning pool, guard word, wrapped netbuf,
  free-list link and end-guard pointer. The trailing guard and leading
  guard use `0xcafe2bad`. The reference uses `NXSpinLock` for pool access.

Do not infer complete descriptors or ring counts from allocation sizes alone;
review both initialization and consumption. Recover the actual owner and
lifetime of shared memory, wrappers, queued packets, free/active/pending TCBs
and receive buffers. Review allocation failure, pool shutdown, delayed recycle,
interrupt concurrency, reset and free paths together.

Preserve the implementations of the contiguous/page/noncached allocation
helpers, their kernel calls, page masks and returned ownership information.
Check all physical-address call arguments against the calling convention:
the initial IDA pseudocode folds parameters around `IOVmTaskSelf` and
`IOPhysicalFromVirtual` and is not a reliable prototype on its own.

## Driver behavior

Reconstruct the complete reference flow:

1. Adapter probe validates its bus/device identity and resources, obtains
   the MAC and hardware settings, and invokes the inherited DriverKit
   initialization in the reference order.
2. `coldInit`, `swInit`, `hwInit`, self-test and `_init596` prepare memory,
   buffers and the chip. `config`, `iaSetup` and `mcSetup` submit the
   reference command formats and apply the reference timeout/error rules.
3. Transmit queues and `_transmitPacket:` build descriptors and maintain
   free, active and pending TCB lists. Completion updates statistics,
   disposes of packet ownership and services queued packets.
4. Receive processing consumes completed descriptors, handles errors and
   filtering, passes packets to the network layer, replaces/recycles
   buffers and maintains receive-unit links and restart conditions.
5. Interrupt handling acknowledges chip status, coordinates adapter IRQ
   latches and command/receive units, and preserves shared-IRQ handling.
6. Timeout/reset paths quiesce hardware, preserve the reference scheduling
   and enable-state rules, and recover queues without double freeing.
7. Debugger send/receive uses its reserved descriptors and packet storage,
   with the reference locking, polling and restoration behavior.

Also reconstruct promiscuous/multicast transitions, multicast address
handling, throttle timers, power state and power-management methods. Recover
exact success/failure conventions instead of assigning `BOOL` returns
from method names. Every flag, statistic, call, branch, timeout count and
state update must be covered by evidence.

Adapter-specific review must include:

- Cogent EISA ID-to-board/IRQ tables, resource selection, IRQ latch,
  channel attention and port-command ordering.
- Flash32 IRQ and connector helpers, checksum, connector autodetection,
  reset/initialization and interrupt latch behavior.
- PRO/10 PCI configuration-space probes, device/variant handling,
  RJ-45-only detection, MAC acquisition, PLX initialization/reset,
  adapter interrupt gating, connector selection/detection and reset.

Preserve register offsets, byte/word/dword accesses, masks, operation order,
delays, retry limits, tables and initial global values. Reconstruct from
the binary; controller manuals or other drivers may explain evidence but
cannot replace observed reference behavior.

## Evidence and comparison

Create `tools/binrecon/profiles/intel82596.json`, initially reference-only,
using `BINRECON_REFERENCE`, i386/little endian, normalized-function acceptance,
and output directory `../out/intel82596`. Enable IDA. Another supported
i386 analyzer may supply corroborating evidence where it runs successfully;
record its failures and boundary disagreements without treating a majority
vote as proof. Changes to shared Binrecon code require a demonstrated blocker.

Track driver-local `reconstruction/source-map.json`, `ledger.json`, and
`divergences.md`. Keep binaries, IDA databases, pseudocode/disassembly exports,
analyzer reports, build logs and generated evidence under ignored paths.
Record identities, reproducible commands and evidence locations in the
tracked reconstruction documents.

The ledger must have exactly 86 unique reference-function entries. Map all
84 handwritten functions to real definitions with valid source locations.
Every handwritten function must reach at least `control-flow-confirmed`,
with reviewed branches, calls, widths, constants, state updates and returns.
Use `assembly-matched` only when the recorded comparison/disassembly
supports it. Names or signatures alone do not satisfy behavioral coverage.

The only default generated-code exceptions are:

- `+[Intel82596NetworkDriverKernelServerInstance kernelServerInstance]`
  at `0x4228`.
- `+[Intel82596NetworkDriverVersion driverKitVersionForIntel82596NetworkDriver]`
  at `0x4234`.

Record them as generated exceptions with reasons and check that the rebuilt
server emits their expected identities and behavior. Do not hand-write those
classes or classify missing handwritten behavior as an intentional mismatch.

After a successful build, analyze and compare the actual rebuilt binary,
bind its SHA-256 into the ledger, and retain the machine-readable comparison.
Resolve behavioral mismatches. Explain remaining compiler, inherited-layout
or generated-build differences with instruction/ABI evidence and their
practical limits. Report the actual global acceptance result independently
from per-function review; an explained difference does not turn a failed
machine comparison into a passing comparison.

A reference-only run can return 1 because no rebuilt comparison exists.
Inspect its summary and published evidence rather than interpreting that
exit as proof of either failed analysis or completed reconstruction.
Source-map semantic/schema validation, selector/class/symbol/import checks
and resource comparisons supplement function review.

## Build and package

Use the repository's existing Aggregate / Driver / Kernel Server conventions
and `pb_makefiles` framework. Set emitted driver and server names to
`Intel82596NetworkDriver`; register the five implementation units and new
headers consistently. Use DriverKit's real headers and kernel netbuf APIs
instead of invented extern signatures or nonexistent headers.

Provide `Load_Commands.sect` with the reference `WIRE` semantics and no
invented MIG interface. Preserve Loaded Server version `2`, while configuration
`Version` is `5.00`; these are separate metadata fields. Allow generated
compiler/project-version timestamps to differ with documentation.

Restore all five shipped configuration tables:

| Table | Class / bus | Auto Detect IDs |
| --- | --- | --- |
| `Default.table` | `CogentEMaster` / EISA | `0x0de79002` |
| `EM932.table` | `CogentEMaster` / EISA | `0x0de79001 0x0de79003 0x0de79004` |
| `EM945.table` | `CogentEMaster` / EISA | `0x0de79005` |
| `EEFlash32.table` | `IntelEEFlash32` / EISA | `0x25d41010` |
| `IntelPRO10PCI.table` | `IntelPRO10PCI` / PCI | `0x12268086` |

Match reference titles, class/server identity, resource fields, help keys,
PCI `Connector = AUTO` and `Share IRQ Levels = YES`, and configuration version.
The current Default title `CogentEM935vL` must become the reference
`CogentEM935XL`. Include the corresponding localizable strings and Help
resources, using the existing DriverHelp-to-Help packaging convention where
required. Register copied resources and verify their bytes against the supplied
reference. Exclude inspector resources from this kernel-only package.

Add `apk/pkginfo` for `drvintel82596`, initial `pkgver = 1`, arch `i386`, and the actual build
dependencies following adjacent driver packages. Preserve applicable source
notices and identify new source as reconstruction rather than original Apple
text. Package license metadata must follow the repository's established policy
and applicable notices; do not invent a license attribution.

Use the existing `vm/sync-src.ps1`, `vm/guest-remote.ps1` and rbuild facilities,
syncing only this driver and required task-specific build support. Use
separate object/destination directories and respect ongoing guest builds.
Stage the final kernel artifact at
`out/i386/drvIntel82596/Intel82596NetworkDriver_reloc`, outside Git, together
with the produced package and build evidence. Record compiler/linker versions,
architecture flags, diagnostics, exit status and artifact hashes.

A PPC build host is acceptable only if the result is verified as i386.
Do not repair doomed baseline scaffolding merely to claim a baseline build.
Fix final compile/link errors; if the guest is unavailable, continue source
and evidence work and report build/comparison gates as incomplete.

## Verification and completion gates

| Gate | Required result |
| --- | --- |
| Reference identity | Recorded i386 artifact and SHA-256 resolve through the profile |
| Partition | 86 unique function entries, including address-zero Cogent probe and exactly two generated exceptions |
| Source coverage | All 75 handwritten methods and 9 C helpers have real definitions and valid source locations |
| ABI | Recovered own ivars, inheritance, descriptors, buffer prefix/guard and callback signatures; 32-bit layout checks pass |
| Behavioral review | All 84 handwritten functions at least `control-flow-confirmed`; no unresolved behavioral omissions |
| Residue | Invented class declarations, nonexistent imports, placeholder bodies and erroneous inherited overrides are resolved |
| Build | Guest compiler/linker exit 0; staged artifact is i386; imports, generated methods and Loaded Server fields reviewed |
| Package | Correct nested build lists, five adapter tables, strings/help, DriverInfo and i386 package; inspector excluded |
| Rebuilt comparison | Reports use the actual rebuilt hash; each difference resolved or explained with evidence; actual acceptance result recorded |
| Status | README states exact coverage, build and comparison results and hardware-validation status |

Use focused tests for behavior that can be checked independently against
reference-derived expectations: descriptor sizes/offsets, alignment and
page packing, guard placement, buffer counts and recycle ownership,
queue-link transitions, and timeout bounds. Mock register traces may verify
recovered operation widths/order where the paths can be isolated without
changing production semantics. Such tests do not prove physical DMA or
network operation. Prefer direct assembly review where a useful independent
test cannot be isolated.

Run schema/source-map validation and relevant artifact/package checks. Run
shared Binrecon tests if shared tooling changes. Keep unrelated local changes
outside this task's commits. Update `src/drivers-i386/README` only after the
evidence exists; add a driver-specific status document only if necessary to
communicate results not already covered by `divergences.md`.

Completion requires every gate above. Missing build access, unresolved
decompilation or unavailable comparison must be reported precisely; partial
source recovery cannot be called a completed reconstruction. Hardware testing
is performed only on a compatible target and documented as its own result.
Any boot experiment must use a task-specific temporary disk image, as required
by `CLAUDE.md`.

## Dependencies for implementation planning

1. Establish the profile, full function/category inventory and ignored
   evidence exports; initialize the source map, ledger and divergences.
2. Recover superclass compatibility, own ivars, hardware structures,
   constants/tables, helper prototypes and ownership rules.
3. Reconstruct allocation/buffer management and chip/queue initialization,
   then transmit, receive, interrupts, reset, modes and debugger operations.
4. Reconstruct the three adapter implementations and remaining power/helper
   paths; review all 84 handwritten functions against IDA and disassembly.
5. Restore the nested build and configuration/resources/package; compile
   and resolve target compatibility and link defects.
6. Analyze the rebuild, reconcile differences, validate the source map and
   ledger, perform focused verification and publish accurate status.

The subsequent plan must supply concrete commands, per-function evidence
checkpoints and these acceptance criteria after the user reviews this spec.
