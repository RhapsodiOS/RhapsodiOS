# PPC MacRISC Platform Support Design

## Purpose

Extend `src/drivers-ppc/bus/drvPExpert` so RhapsodiOS can boot to
userspace on the later New World PowerPC G3 and G4 platform families. The
target families are later Power Mac G4 and Cube systems, later iMac G3 and
iMac G4 systems, G3 and G4 iBooks, PowerBook G4 systems, eMac systems, the
G4 Mac mini, and G4 Xserve systems. PowerPC G5 systems are explicitly out
of scope.

This is a platform bring-up milestone, not a promise of complete peripheral
support. A supported machine reaches a userspace shell with stable core
platform services. Separate drivers may still be needed for individual
graphics, network, audio, storage, battery, and thermal devices.

## Existing State

The current platform expert recognizes a short list of post-Yosemite model
identifiers and routes them through `sawtooth_init`. That route assumes a
Sawtooth-era KeyLargo layout, a fixed 64-source MPIC table, fixed DBDMA
channel assignments, and a VIA cascade. Several resource lookup functions
also panic when legacy devices such as MESH SCSI or audio are absent.

Recent work has made KeyLargo discovery and direct MPIC interrupt identities
testable. The new design builds on those mechanisms instead of replacing
them. Apple’s published AppleMacRISC2PE and AppleKeyLargo sources and the
corresponding Linux PowerMac platform code are hardware references, but are
not transplanted because their surrounding kernel and driver architectures
differ substantially from this Darwin 0.3-derived tree.

## Scope

### Included

- New World G3 and G4 machines later than the configurations already handled
  by the Yosemite and Sawtooth paths.
- UniNorth host bridges paired with KeyLargo, Pangea, or Intrepid Mac-IO.
- Root model and compatibility discovery.
- Physical I/O range and child-resource discovery.
- MPIC source setup and optional VIA/PMU cascade setup.
- DBDMA channel discovery for devices present in the firmware tree.
- CPU, cache, clock, BAT, and decrementer setup needed for boot.
- Safe uniprocessor boot on multiprocessor machines.
- Host-side parser, classifier, validation, and interrupt tests.
- Validation on a `PowerMac5,1` Cube, `PowerBook3,4`, and dual-processor
  `RackMac1,1`.

### Excluded

- PowerPC 970, U3, K2/Shasta G5 platforms, and 64-bit kernel support.
- Starting secondary processors or providing symmetric multiprocessing.
- Sleep, wake, battery management, CPU frequency switching, and full power
  management.
- Thermal and fan-control policy.
- Accelerated graphics and model-specific display handling.
- New peripheral drivers solely to provide audio, networking, USB, FireWire,
  or storage support.
- Guaranteed operation of every peripheral required for full Mac OS X feature
  parity.

## Support Definition

A target machine is platform-supported when it:

1. Completes early platform discovery without unsafe fallback addresses.
2. Initializes CPU 0, BAT mappings, clocks, decrementer, Mac-IO, and MPIC.
3. Keeps any additional CPUs parked without receiving interrupts.
4. Provides a usable serial or firmware-initialized framebuffer console.
5. Mounts a supported root-storage device read/write.
6. Reaches a userspace shell.
7. Maintains stable time and interrupts during sustained root-disk activity.
8. Reboots or powers off without corrupting the test disk.

An optional peripheral may remain unavailable without failing this definition.
Its absence must not cause an early panic or an invalid MMIO access.

## Architecture

### MacRISC family

Add a `macrisc` family beside the existing platform families. The existing
Yosemite and Sawtooth paths remain intact for known machines unless the new
classifier positively selects the MacRISC descriptor. This preserves a clear
regression boundary and avoids changing legacy behavior merely because a
model name shares a prefix with a later machine.

The family exposes the existing `powermac_init_t` interface. Internally it
uses a validated `PEMacRISCPlatform` descriptor rather than fixed per-model
global assumptions.

### Platform descriptor

`PEMacRISCPlatform` is fixed-size and allocation-free because it is created
before VM initialization. It records:

- A bounded copy of the root model identifier.
- CPU family, processor count, and boot CPU identifier.
- Host-bridge kind and UniNorth revision when available.
- Mac-IO kind: KeyLargo, Pangea, or Intrepid.
- Mac-IO physical base and span.
- MPIC physical base, source capacity, and cascade topology.
- PMU or CUDA presence and interrupt source.
- Clock and cache properties required by early boot.
- Present DBDMA channels and their logical uses.
- Optional physical resources used by existing legacy drivers.
- Quirk flags selected from a small documented model table.

The descriptor distinguishes absent optional resources from malformed
boot-critical resources. It contains no pointers into unchecked property
storage after discovery finishes.

### Pure discovery helpers

Property decoding, string-list matching, address translation, classification,
and descriptor validation are implemented as pure C helpers with no MMIO.
They accept bounded property views so host tests can use compact synthetic
fixtures without emulating the kernel device-tree implementation.

The root `compatible` property is treated as a sequence of NUL-terminated
strings within a declared byte length. Firmware-owned data is never modified.
Address and size cells are decoded with bounds and overflow checks, including
translation through parent `ranges` where required.

## Classification Rules

Classification is based on capabilities rather than a whitelist alone:

1. A supported 32-bit PowerPC G3/G4 CPU node must be present.
2. A supported UniNorth-compatible host bridge must be present.
3. A `mac-io` node compatible with `Keylargo` whose `device-id` is 0x22
   (KeyLargo), 0x25 (Pangea), or 0x3e (Intrepid) must expose a valid register
   range. Pangea and Intrepid do not carry their own `compatible` strings;
   K2 (0x41) and Shasta (0x4f) are rejected.
4. An OpenPIC-compatible interrupt controller must expose a valid register
   range and supported source count.
5. The root model must belong to a New World desktop, portable, all-in-one,
   mini, or rack family rather than a known unsupported platform.

The known-model catalog is used for test coverage and quirks, not as the sole
acceptance gate. It covers later identifiers in the `PowerMac`, `PowerBook`,
and `RackMac` series that contain G3 or G4 CPUs. This includes later iMac,
iBook, PowerBook, eMac, Mac mini, and Xserve marketing families even when the
firmware model begins with `PowerMac` or `PowerBook`.

PowerPC 970 CPU versions and U3-class host bridges are rejected explicitly.
A machine is not accepted merely because its model starts with `PowerMac`.

## Initialization Flow

1. `identify_machine1` reads the device tree and invokes MacRISC discovery.
2. Discovery builds and validates the descriptor without touching hardware.
3. The classifier selects `macrisc_init` and publishes only validated I/O
   base and span values.
4. Processor initialization installs safe BAT mappings and leaves non-boot
   CPUs parked.
5. `identify_machine2` copies firmware CPU, cache, and clock properties and
   applies only CPU-family-safe fallbacks.
6. MacRISC configuration constructs MPIC and DBDMA runtime state from the
   descriptor.
7. Existing console and root-device drivers receive only resources that were
   actually discovered.
8. Interrupt initialization programs the validated MPIC sources and enables
   a VIA/PMU cascade only when the descriptor identifies one.

The original `sawtooth_init` remains available for its established machines.
Shared behavior may call common helpers, but the work does not refactor
unrelated legacy family implementations.

## Resource Handling

Legacy lookup functions currently make devices such as MESH SCSI and audio
mandatory. For the MacRISC path, each optional resource is represented with
an explicit presence bit. Missing MESH, floppy, audio, Ethernet, or secondary
ATA nodes produce an absent resource rather than a panic or a base-plus-zero
alias.

Mac-IO base and size come from validated device-tree properties. The old
Sawtooth span is retained only for the existing `PowerMac3,1` quirk. Later
machines never inherit that fallback.

DBDMA assignments are associated with discovered child nodes. Legacy logical
channel names are filled only when the matching device and a valid channel
are present. Consumers therefore retain their current interface without
assuming every Mac-IO generation contains every channel.

## Interrupt Handling

The OpenPIC is the `interrupt-controller@40000` child of Mac-IO on every
KeyLargo-family chip; its base is published as an absolute physical address
because the existing MPIC register macros use it as one.

The MacRISC family owns fixed-capacity early-boot arrays for 64 primary MPIC
sources plus the validated VIA/PMU cascade children. Discovery rejects a
primary source count larger than 64 or a cascade width larger than the
compiled child table.

Firmware interrupt source numbers populate the runtime table. Existing
logical `PMAC_DEV_*` identifiers remain for drivers that depend on them.
Unrecognized but valid firmware sources use the existing
`PMAC_DEV_MPIC_DIRECT_BASE` identity mechanism.

Sense and polarity are obtained from validated firmware data where the
platform exposes them. Chipset defaults are used only for documented
KeyLargo-family cases. Cascade state includes the MPIC source, number of VIA
children, and PMU/CUDA topology; it is not enabled from a fixed Sawtooth
constant. The cascade source is the VIA node's own firmware interrupt (25 on
KeyLargo-family machines); the PMU's second line is the `extint-gpio1`
source (47). The OpenPIC pass-through
disable bit that the legacy code calls `MPIC_CASCADE` is unrelated and stays
set on every Mac.

The boot CPU is the only MPIC destination in this milestone. The second CPU
on a dual-processor `RackMac1,1` remains parked and is not advertised as
available to the scheduler; the existing `configure_platform()` already
advertises a single processor, so the scheduler view does not change.

## CPU, Cache, Clock, and BAT Handling

Firmware properties are authoritative for CPU frequency, bus frequency,
timebase frequency, cache sizes, and cache topology when present. Register
probing is selected by CPU family and is never performed using a 750-only
assumption on a 7400, 7410, 744x, or 745x processor.

The decrementer conversion uses the validated timebase or bus relationship
and checks for zero or overflow before division. Invalid clock data is a
boot-critical discovery failure unless a documented platform-specific
fallback exists.

BAT mappings cover only the physical ranges required for early boot and
discovered I/O. Existing mappings required by the bootloader contract remain,
but later platforms do not acquire speculative fixed mappings.

## Diagnostics and Failure Policy

Boot-critical validation fails before unsafe MMIO and prints one diagnostic
containing:

- Root model.
- Detected CPU and chipset families.
- The missing, unsupported, or malformed capability.

Unsupported G5 configurations receive a distinct diagnostic. Optional
services print at most one concise disabled-service message. An unknown
G3/G4 model whose capabilities match a supported descriptor may proceed, but
the boot log identifies it as an unlisted compatible configuration.

No error path silently substitutes the Sawtooth register span, interrupt
source, or peripheral offset.

## Testing

### Host tests

Host tests exercise the pure helpers and runtime mappings:

- Known model catalog classification across Power Mac, iMac, iBook,
  PowerBook, eMac, Mac mini, and Xserve G3/G4 families.
- Representative KeyLargo, Pangea, and Intrepid trees.
- NUL-separated `compatible` lists, including missing final terminators.
- One- and multi-cell address and range decoding.
- Truncated, oversized, unaligned, and overflowed properties.
- Missing optional peripherals.
- Missing or malformed boot-critical nodes.
- Explicit PowerPC 970 and U3 rejection.
- MPIC direct-source allocation and collision rejection.
- VIA/PMU cascade selection and no-cascade configurations.
- DBDMA association for present and absent children.
- Cache and clock validation for G3 and G4 CPU families.
- Regression fixtures for current Yosemite and Sawtooth selection.

Tests use the repository’s C89 host-test conventions and run through the
existing `tests/Makefile.host` entry point.

### Build verification

- Build and run all `drvPExpert` host tests with warnings treated as errors.
- Build the PPC driver and kernel using the historical supported toolchain.
- Inspect the linked image for unresolved platform symbols and early-boot
  storage growth beyond configured limits.

### Hardware verification

Hardware boots use temporary or dedicated test disk images:

1. `PowerMac5,1` Cube validates that existing early KeyLargo support does not
   regress.
2. `PowerBook3,4` validates the portable UniNorth/KeyLargo path, PMU topology,
   absent optional desktop devices, and portable ATA root I/O.
3. Dual-processor `RackMac1,1` validates rack classification, CPU parking,
   MPIC routing to CPU 0, and sustained server disk interrupts.

For each system, preserve a serial or photographed verbose boot log, record
the root model and relevant device-tree properties, reach a shell, confirm
advancing wall time, exercise sustained root-disk reads and writes, and then
perform a clean reboot or power-off.

## Implementation Boundaries

Every source change must trace to discovery, initialization, diagnostics, or
tests required by this boot milestone. Later Apple platform code is used as a
behavioral reference with its license retained where code is adapted. The
implementation does not introduce a later IOKit platform-expert framework or
perform adjacent driver refactors.

If a validation target fails because the required root device, console, or
bootloader lacks a separate driver feature, that dependency is reported and
split into its own design rather than folded silently into `drvPExpert`.
