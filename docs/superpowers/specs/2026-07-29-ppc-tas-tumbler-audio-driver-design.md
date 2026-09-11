# PPC TAS/Tumbler Audio Driver Design

**Status:** Approved design

**Date:** 2026-07-29

## Summary

Add a PowerPC onboard-audio driver family for Apple I2S systems using the
Texas Instruments TAS3001C (Tumbler) and TAS3004 (Snapper) codecs. The driver
will use the existing DriverKit `IOAudio` interface, KeyLargo-family DBDMA,
Open Firmware descriptions, and small new Platform Expert services for shared
KeyLargo/Pangea/K2 resources.

The implementation will be one `drvPPCTASAudio` bundle with two codec
backends. It will provide full-duplex 16-bit stereo PCM, output volume and
mute, input gain and source selection, automatic speaker/headphone/line-out
routing, and sleep/wake restoration. It will guarantee 44.1 kHz and expose
other firmware-advertised rates only when the I2S clock calculation is exact.

The initial release is code-supported but hardware-unvalidated. Physical
hardware validation and QEMU device emulation are separate follow-up work.

## Goals

- Support both `tumbler`/TAS3001C and `snapper`/TAS3004 device-tree nodes.
- Integrate with the same `IOAudio` framework used by PPCAwacs and
  PPCBurgundy.
- Provide full-duplex playback and capture with one shared I2S sample clock.
- Provide volume, mute, input selection, input gain, and automatic output
  routing.
- Quiesce safely for `PM_STANDBY`, `PM_SUSPENDED`, and `PM_OFF`, then restore
  all hardware and user-visible state on `PM_READY`.
- Attach unknown models conservatively when their device-tree resources are
  complete and unambiguous.
- Centralize access to shared KeyLargo-family I2C, GPIO, and feature-control
  resources in the Platform Expert.
- Make hardware-independent logic testable on the development host.
- Preserve clear source provenance and retain required BSD attribution when
  adapting OpenBSD code.

## Non-goals

- Do not add TAS EQ, user-selectable bass/treble, biquad, or DRC controls in
  the first release. Initialization will use neutral EQ and disabled DRC.
- Do not support DACA, Burgundy, AWACS/Screamer, Onyx, or other codec families.
- Do not refactor the existing PPCAwacs or PPCBurgundy bundles.
- Do not implement QEMU Tumbler/Snapper emulation in this project.
- Do not claim audible output, capture quality, or working physical
  sleep/wake until each machine has passed the hardware validation checklist.
- Do not guess missing MMIO addresses, interrupt numbers, I2C endpoints, GPIO
  roles, or GPIO polarity.

## Sources and provenance

The implementation will use these sources in descending order of authority:

1. Texas Instruments TAS3001C and TAS3004 documentation for codec registers,
   payload sizes, reset timing, and serial format.
2. Apple's published AppleOnboardAudio sources for Apple platform behavior,
   I2S clock programming, device-tree conventions, power sequencing, and
   machine-specific expectations.
3. BSD-licensed OpenBSD macppc sources for compact implementations of I2S,
   KeyWest I2C, GPIO discovery, Tumbler, and Snapper behavior.
4. Other operating-system sources may corroborate behavior, but GPL-derived
   code, tables, or comments will not be copied into this tree.

Any source adapted from OpenBSD will retain its copyright and license notice
in the resulting file. New project code will use the repository's normal
license header. The implementation plan must identify the provenance of each
hardware table before it is added.

Primary published references:

- Apple AppleOnboardAudio:
  <https://github.com/apple-oss-distributions/AppleOnboardAudio>
- OpenBSD Tumbler:
  <https://github.com/openbsd/src/blob/master/sys/arch/macppc/dev/tumbler.c>
- OpenBSD Snapper:
  <https://github.com/openbsd/src/blob/master/sys/arch/macppc/dev/snapper.c>
- OpenBSD I2S:
  <https://github.com/openbsd/src/blob/master/sys/arch/macppc/dev/i2s.c>
- OpenBSD KeyWest I2C:
  <https://github.com/openbsd/src/blob/master/sys/arch/macppc/dev/kiic.c>
- OpenBSD GPIO:
  <https://github.com/openbsd/src/blob/master/sys/arch/macppc/dev/macgpio.c>

## Architecture

### Driver bundle

`drvPPCTASAudio` is one DriverKit bundle with one `IOAudio` subclass. Shared
code owns probing, I2S setup, DBDMA, interrupts, IOAudio controls, routing, and
power transitions. A codec-operations table selects TAS3001C or TAS3004
behavior after device-tree discovery.

The two codec backends are not separate loadable modules. They expose the same
internal operations:

- validate the codec-specific configuration;
- reset and initialize the codec;
- encode and apply output volume and mute;
- encode and apply input gain and input source;
- restore the complete codec shadow after wake;
- force the codec into a muted safe state.

This keeps DMA and power behavior unified without forcing TAS3001C and TAS3004
register differences into conditional statements throughout the driver.

### Platform Expert boundary

The Platform Expert will be the single owner of stateful KeyLargo-family
global resources. It will expose a narrow C interface for:

- serialized KeyWest I2C transfers with a selected port and slave address;
- active-state-neutral GPIO reads and writes using validated descriptors;
- enabling, resetting, clocking, and disabling I2S cell 0 or cell 1;
- read/modify/write feature-control operations that preserve unrelated bits.

The shared header will declare these interfaces, returning `kern_return_t`:

- `PEKeyWestI2CTransfer(const PEKeyWestI2CRequest *request)`;
- `PEAudioGPIORead(const PEAudioGPIO *gpio, boolean_t *active)`;
- `PEAudioGPIOWrite(const PEAudioGPIO *gpio, boolean_t active)`;
- `PEI2SSetCellState(unsigned int cell, PEI2SCellState state)`.

`PEKeyWestI2CRequest` contains port, 7-bit slave address, register/subaddress,
direction, buffer, length, and deadline. `PEAudioGPIO` contains the validated
KeyLargo-relative register offset and active polarity. `PEI2SCellState` has
three states: disabled/reset, enabled with clock held, and enabled/running.
The implementation can adjust C spelling only when the target compiler or
existing exported-symbol convention requires it; semantics and ownership do
not change. All waits have fixed deadlines.

The Platform Expert will not interpret audio routes, TAS registers, volume,
mute, or IOAudio state. The audio driver will not issue uncoordinated KeyWest
or feature-control MMIO. I2C transfers are forbidden from DMA and GPIO
interrupt context.

## Internal components

The implementation uses focused source units with these responsibilities:

- `PPCTASAudio`: DriverKit probe, lifecycle, IOAudio methods, controls, and
  coordination.
- `TASDeviceTree`: property decoding and immutable machine configuration.
- `PPCI2S`: rate validation, serial format, word size, clock setup, and I2S
  register access.
- `PPCDBDMAAudio`: descriptor construction, input/output rings, start, stop,
  reset, and completion processing.
- `TASCodec`: common backend interface and shared register-transaction rules.
- `TAS3001C` and `TAS3004`: codec-specific register maps and sequences.
- `TASRouting`: jack debounce, route calculation, and mute-before-switch
  policy.

These names describe boundaries rather than mandating one file per item. Small
units can share a file when that reduces code without blurring ownership.

## Configuration and runtime state

### Immutable machine configuration

Probe will parse Open Firmware once into an immutable `tas_machine_config`.
It will contain:

- codec kind and compatible string;
- I2C port and slave address;
- I2S cell number, MMIO ranges, and interrupts;
- input and output DBDMA resources;
- validated sample rates;
- GPIO descriptors indexed by logical role, including active state;
- available input and output routes;
- model, layout, and sound-object identifiers for diagnostics.

Runtime code will consume this structure and will not repeatedly traverse or
reinterpret the device tree.

### Codec state

`tas_codec_state` will hold only the selected backend's required shadows plus
logical volume, mute, input gain, and input source. A shadow changes only after
the corresponding I2C transaction succeeds. A separate validity flag records
whether hardware is known to match the shadow. Reset, I2C failure, and power
loss invalidate hardware state without discarding the desired logical state.

### DMA state

Input and output each have an independent `tas_dma_state` containing ring
memory, physical addresses, producer/consumer indices, active state, and stop
status. No process-wide singleton will route interrupts; the interrupt
argument will identify the owning device and direction.

## Device discovery

The bundle will match an I2S device whose sound-codec child advertises
`tumbler` or `snapper`. Probe will then validate all mandatory resources
before allocating or publishing an audio device.

Mandatory resources are:

- a recognized TAS codec compatible string;
- one valid I2S register range;
- input and output DBDMA register ranges and interrupts;
- a resolvable KeyWest I2C controller, port, and TAS slave address;
- an audio reset GPIO when the advertised codec/layout requires it;
- a mute GPIO for every advertised physical output;
- active-state information for every detect or mute GPIO used by the profile.

Optional inputs, outputs, and detects are omitted when absent. A missing
optional route does not prevent attachment. A present route with incomplete
control information is ambiguous and prevents attachment because it cannot be
made fail-safe.

Unknown machine models attach in generic mode only when all required resources
are complete. Model identifiers select only documented workarounds; they are
not the primary allowlist.

The firmware `sample-rates` property is treated as untrusted input. The driver
always attempts 44.1 kHz. Additional rates are retained only when they are
between 8,000 and 48,000 Hz inclusive and an exact supported I2S
clock-source/divisor combination exists. If 44.1 kHz cannot be generated
exactly, probe fails.

## Initialization

Initialization is transactional and follows this order:

1. Parse and validate the complete machine configuration.
2. Acquire Platform Expert services and map I2S/DBDMA resources.
3. Drive every known external output mute to its safe state.
4. Enable the selected I2S cell and release its reset through the Platform
   Expert.
5. Program I2S for 16-bit stereo at 44.1 kHz.
6. Reset the selected TAS codec with documented delays and bounded waits.
7. Program neutral filters, disabled DRC, routing defaults, input state,
   logical volume, and codec mute.
8. Allocate and validate input/output DBDMA rings.
9. Install DMA and GPIO-detect interrupt handlers.
10. Read stable jack state and calculate the initial output route.
11. Publish the IOAudio device and controls.
12. If user mute is clear, unmute only outputs selected by the route mask.

Failure at any step unwinds acquired resources in reverse order. The unwind
first stops DMA, disables interrupts, and mutes every known output. Probe does
not publish a partially initialized device.

## PCM and DBDMA behavior

The first release exposes 16-bit stereo linear PCM. Playback and capture have
separate rings but share one I2S clock domain. Full-duplex streams therefore
must use the same sample rate. A rate change is rejected while it would
conflict with an active stream; it is never applied to only one direction.

The descriptor builder will not assume that a virtually contiguous IOAudio
buffer is physically contiguous. It will split commands at:

- physical discontinuities;
- DBDMA transfer-count limits;
- IOAudio interrupt/block boundaries.

Each ring terminates in a branch to its first descriptor. Descriptor fields
will use the hardware-required byte order, and descriptor cache lines will be
flushed before the channel is started or updated. Completion handling will
acknowledge status before notifying IOAudio.

DMA interrupt handlers do the minimum required work: validate and acknowledge
completed descriptors, advance the direction's ring state, count completed
IOAudio blocks, and notify the owning audio object. They do not perform I2C,
GPIO routing, allocation, or device-tree access.

Stopping a stream uses a bounded DBDMA stop followed by reset. A timeout marks
that direction faulted and prevents restart until a complete device reset or
power-cycle restore succeeds.

## Controls and routing

The initial IOAudio controls are:

- stereo output volume;
- output mute;
- input gain when supported by the selected codec/layout;
- input source drawn only from parsed, available inputs.

Jack and route state remain internal in the first release and are reported in
transition diagnostics; no new IOAudio control ABI is introduced for them.

Codec-specific volume conversion will be monotonic, clamp endpoints, and map
framework mute to a true zero/mute representation. Unsupported inputs and
controls will not be advertised.

GPIO edges only acknowledge the interrupt and schedule deferred routing work.
Deferred work debounces each detect until repeated active-state-normalized
reads agree. It then:

1. mutes every advertised output;
2. computes a route mask from stable detects;
3. leaves all outputs muted when user mute is set;
4. otherwise unmutes detected headphone and/or line-out routes;
5. unmutes internal speakers only when neither external route is detected.

This permits headphone and line-out simultaneously when both detects are
active, matching the route-mask behavior used by OpenBSD. Every route change
uses mute-before-switch ordering.

## Power management

The driver will implement DriverKit power callbacks, including
`setPowerState:`, and track its current logical power state.

Entering `PM_STANDBY`, `PM_SUSPENDED`, or `PM_OFF` will:

1. block new stream starts and deferred route changes;
2. mute every external output;
3. stop and reset input/output DBDMA with bounded waits;
4. apply the selected backend's documented mute/power-down sequence; when the
   codec has no documented power-down command, leave it muted before gating
   the I2S clock;
5. preserve desired logical controls and codec shadows;
6. disable GPIO-detect interrupts;
7. disable the I2S clock/cell through the Platform Expert.

Returning to `PM_READY` will:

1. keep every external output muted;
2. enable and release the I2S cell;
3. reapply I2S format and the previously selected validated rate;
4. reset the TAS codec;
5. replay the complete selected-backend shadow in defined order;
6. rebuild/rearm DMA state without automatically restarting old client
   transfers;
7. re-enable detects and debounce current jack state;
8. restore route, volume, input source, and gain;
9. unmute the selected route only when logical user mute is clear.

A failed resume leaves the device stopped and all known outputs muted. IOAudio
operations return an error until a later complete restore succeeds.

## Concurrency and error handling

- Platform Expert serializes the KeyWest controller across all clients.
- The audio device serializes control, route, rate, and power transitions with
  one device-state lock.
- Non-interrupt transitions suspend the affected DMA interrupt source before
  changing ring state. DMA handlers run at the device interrupt priority and
  touch only their direction's completion fields.
- Interrupt handlers never wait for I2C or acquire a lock held across I2C.
- All register polling and reset waits have fixed deadlines.
- I2C NACK, busy, arbitration, and timeout errors propagate to the caller.
- A codec/control write failure invalidates hardware shadow state and forces
  all output routes muted.
- A GPIO routing failure keeps every output muted.
- A DMA fault stops only the affected direction unless shared I2S state is no
  longer trustworthy; in that case both directions stop.
- Logs identify subsystem, operation, model/layout, and status without
  flooding per-descriptor success messages.

## Verification strategy

Because physical hardware is unavailable, the first phase relies on PPC
cross-builds and deterministic host-side tests around pure logic and mocked
MMIO/I2C boundaries.

### Device-tree tests

- TAS3001C and TAS3004 fixtures based on published Apple/OpenBSD machine
  descriptions.
- Missing and malformed ranges, interrupts, addresses, rates, and GPIO data.
- Unknown model with complete compatible resources attaches in generic mode.
- Unknown or ambiguous codec/layout data fails without touching hardware.
- Optional absent routes are omitted; incomplete present routes fail.

### Platform Expert tests

- KeyWest transfer success, NACK, busy, arbitration, and timeout traces.
- Concurrent transfers are serialized and restore controller state.
- GPIO active-state normalization for both polarities.
- Feature-control updates preserve every unrelated bit.
- Every polling loop terminates at its deadline.

### I2S and codec tests

- Exact clock-source and divisor selection for 44.1 kHz and valid firmware
  rates.
- Inexact and conflicting full-duplex rates are rejected.
- TAS3001C/TAS3004 register address, width, reset, and initialization order.
- Volume and gain endpoint, monotonicity, clamp, and mute behavior.
- Input-source encoding and unsupported-source rejection.
- Shadows change only after successful writes.
- Resume replays the complete selected backend state.

### DBDMA tests

- Hardware byte order and command encoding.
- Splitting at physical discontinuities, transfer limits, and block boundaries.
- Correct ring branch and interrupt placement.
- Completion acknowledgement and wraparound.
- Independent input/output state and common-clock enforcement.
- Stop success, stop timeout, reset, and fault recovery.

### Routing and power tests

- Complete headphone/line-out detect truth table.
- Speaker fallback only when neither external route is detected.
- User mute overrides every automatic route.
- Debounce rejects unstable edges.
- Mute-before-switch ordering.
- Failure injection after every initialization and resume step ends fail-muted.
- Sleep and wake traces exactly follow the sequences in this document.

### Build and integration checks

- Cross-build `drvPExpert` and `drvPPCTASAudio` with the supported PPC
  toolchain.
- Verify Platform Expert symbols resolve in the kernel-server build.
- Verify bundle load commands, class registration, `Default.table`,
  `DriverInfo`, and packaging metadata.
- Verify the startup driver list can load the new bundle without displacing
  AWACS or Burgundy.
- Scan for unbounded hardware polling and interrupt-context I2C calls.

## Support tiers

Machine support will be reported in two tiers:

1. **Fixture-covered:** the device-tree profile is represented in deterministic
   tests and the code path builds. This does not imply that audio has been
   heard on the machine.
2. **Hardware-validated:** a named model has passed physical playback,
   capture, routing, repeated start/stop, error recovery, and sleep/wake tests.

OpenBSD's documented Tumbler and Snapper machine lists will seed fixtures, but
will not be presented as RhapsodiOS hardware validation.

## Acceptance criteria

The implementation is ready for its initial code-supported release when:

- both codec fixtures probe through the same driver bundle and select the
  correct backend;
- 44.1 kHz full-duplex 16-bit stereo paths build valid independent DBDMA
  rings sharing one clock;
- all advertised initial controls have passing backend tests;
- the routing truth table and mute-before-switch traces pass;
- every injected initialization, I2C, GPIO, DMA-stop, and resume failure ends
  with all known outputs muted and no published partial device;
- sleep/wake state replay tests pass for both codecs;
- Platform Expert and driver PPC builds and link/export checks pass;
- AWACS and Burgundy source and matching configuration remain unchanged;
- documentation labels the driver hardware-unvalidated until real-machine
  results are recorded.

Physical hardware promotion requires, for each model, clean playback and
capture, correct external routing, repeated stream cycling, volume/mute tests,
and multiple sleep/wake cycles without hangs, stale DMA, or audible routing
pops.
