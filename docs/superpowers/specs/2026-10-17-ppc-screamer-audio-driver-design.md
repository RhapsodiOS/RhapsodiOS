# PPC Screamer Audio Driver Design

**Date:** 2026-10-17

**Status:** Written spec approved by the user on 2026-10-17.

## Intent and success criteria

Create a PowerPC-only RhapsodiOS onboard-audio driver for Screamer, with
Sawtooth as the primary hardware target and other verified Screamer machines
using the same bundle. The user selected full audio support: playback and
recording, volume and mute, input selection and gain, automatic headphone
routing, and suspend/resume restoration.

Success requires a period-toolchain PPC build, deterministic tests, exclusive
device ownership, and recorded physical-machine acceptance results. Building
the bundle or passing simulated register tests does not establish working
analog audio or system sleep/wake. Those results remain explicitly pending
until measured on each machine.

This document specifies the driver. General PPC system sleep implementation
is an external prerequisite for its end-to-end power acceptance, not an
implicit expansion into a system-wide power-management project.

## Scope and approach

Add `src/drivers-ppc/sound/drvPPCScreamer`, containing one DriverKit kernel-server
bundle and one `PPCScreamer : IOAudio` adapter. Set `INCLUDED_ARCHS = ppc` in
the project's architecture selection and package it using the existing
driver-project conventions.

Three approaches were considered:

| Approach | Decision |
| --- | --- |
| Separate Screamer bundle | Selected: isolates Screamer behavior and avoids making legacy AWACS repair part of this task. |
| Extend `drvPPCAwacs` | Rejected: its DMA, discovery, and lifecycle need substantial verification and repair. |
| Common AWACS/Screamer/TAS framework | Rejected: broader interface changes and refactoring are unnecessary. |

The existing AWACS reimplementation contains hard-coded object-offset access,
unfinished cache synchronization, an unbounded codec wait, and Screamer
detection based on an unexplained numeric property identifier. Treat it as
context and reconstruction evidence, not a validated implementation to copy.

Do not add i386 support, other codec families, EQ, bass/treble, SRS controls,
PCMCIA audio, software rate conversion, QEMU audio emulation, or unrelated
audio-framework repairs. Do not alter the public SoundKit or DriverKit audio
ABI.

## Hardware coverage and discovery

| Machine group | Scope and admission rule |
| --- | --- |
| Sawtooth, `PowerMac3,1` | Primary target; requires a verified Screamer firmware/resource fixture and routing profile. |
| `PowerMac3,2` and `PowerMac3,3` | Additional candidates; require Screamer identity, validated resources, and verified routing. Model identity alone does not qualify a machine. |
| Screamer-equipped iMacs | Candidate profiles include `PowerMac2,1`, `PowerMac2,2`, and `PowerMac4,1`; verify codec and each connector's wiring. |
| Screamer-equipped PowerBooks | Lombard and Pismo are candidates; verify firmware identity, inputs, routing, and platform power dependencies independently. |
| Other machines | Admit only when their firmware describes an unambiguous supported configuration or a source-backed profile supplies the missing wiring facts. |

Candidate status is not a hardware support claim. Do not infer Screamer from
the product family, a `davbus` node name, a codec revision alone, or the
presence of three MMIO ranges.

Discovery is read-only until it has validated:

- A single controller/sound relationship with a `model` or `compatible`
  value explicitly identifying Screamer. Parse property lengths, big-endian
  cells, and NUL-separated compatibility lists rather than assuming C strings.
- Controller, output-DBDMA, and input-DBDMA physical ranges, translated through
  the firmware bus hierarchy and delivered consistently by
  `IODeviceDescription`. Validate size, alignment, overflow, and overlap.
- Codec/device, output-DMA, and input-DMA interrupt identities, including the
  mapping from firmware order to local DriverKit interrupt indices. Do not
  inherit AWACS's assumed input/output ordering or fixed Sawtooth IRQ numbers.
- A supported sample-rate description and enough evidence to resolve actual
  inputs, output paths, jack sense polarity, and any amplifier controls.
- The required platform service for controller clocks and shared control bits.

Prefer explicit firmware wiring. Use small immutable machine profiles only
for facts established by pinned reference sources or captured hardware
evidence. A profile records its machine/codec applicability and provenance.
If firmware and a profile conflict, or wiring cannot be resolved, decline
attachment before writes. Missing firmware rates may be supplied only by an
explicit source-backed profile; never manufacture a generic fallback.

The configuration table may nominate `awacs`/`davbus` controller nodes for
probing, but the probe owns the codec decision. Narrow `PPCAwacs` probe handling
so it declines explicitly identified Screamer devices using the same identity
rules, regardless of driver load order. Preserve existing AWACS acceptance;
verify Burgundy and TAS rejection as negative cases. Do not rename existing
drivers or revise their hardware behavior.

## Components and ownership

The Objective-C adapter owns DriverKit registration, resource mappings, locks,
interrupt installation, deferred work, channel buffers, and translation of
legacy audio parameters. Hardware-independent C code owns discovery results,
codec transaction planning, desired/applied control state, stream state, and
power-transition sequencing. Use a small Screamer-specific implementation;
do not introduce a general codec/plugin framework.

Reuse the checked-in `PPCDBDMAAudio.c/.h` implementation and its `TASTime`
deadline helper from `drvPPCTASAudio` as source inputs to the new bundle,
after auditing their contracts for DAVbus use. Each bundle has its own compiled
objects; neither depends on another loaded driver. Do not copy the files or
move TAS sources into a new framework. Keep relative source/include paths
working in both Project Builder metadata and make-based builds. Any necessary
helper correction must be narrowly scoped and pass both TAS and Screamer tests.

Platform Expert owns shared mac-io feature-control registers. Add a narrow,
serialized DAVbus enable/clock/power operation where required, preserving
unrelated bits. The existing `PEI2SSetCellState` service controls I2S and must
not be used as a substitute for DAVbus programming. Every admitted platform
needs an evidenced backend; unsupported clock/power control prevents
attachment. Firmware-provided, fully validated GPIO resources can use existing
Platform Expert GPIO services where applicable. Do not access shared feature
registers directly from the codec layer.

## PCM and DMA data flow

Expose signed 16-bit stereo PCM through the existing `IOAudio` callbacks.
44.1 kHz is required. Additional discrete rates are the intersection of the
verified controller/codec rate model and the resolved machine description.
Do not silently round unsupported rates. State sample-buffer byte order
explicitly in the adapter and test it separately from little-endian register
and descriptor access.

Input and output have independent descriptor rings and completion accounting
but share one active sample clock. The first stream establishes the rate;
starting the other direction at a conflicting rate fails without changing the
running stream. Rate changes require both directions to be stopped.

Build rings only after `IOAudio` supplies the buffer and interrupt period.
Translate physical spans, split at noncontiguous boundaries and transfer-count
limits, and publish canonical 16-byte, little-endian DBDMA descriptors with
16-byte alignment. Reject impossible geometry before starting DMA. Descriptor
storage and audio-buffer addresses must stay representable by the hardware.

Use the kernel's real cache maintenance and ordering operations when handing
descriptors or playback data to DMA and when receiving descriptor/capture
results. An `eieio` barrier alone is not cache synchronization. Completion
handling accounts for all completed periods across ring wraps and preserves
direction-specific state. Stopping one stream must not stop the other or
invalidate its shared clock.

Interrupt handlers acknowledge their documented source exactly once, collect
bounded completion/status information, and arrange normal `IOAudio` service.
They do not sleep, allocate storage, recalibrate the codec, or run jack-routing
transactions. Do not create a second acknowledgement path through the
argument-free `IOAudioInterruptClearFunc` callback.

## Codec, controls, and routing

Use explicit little-endian MMIO and platform ordering primitives. Codec access
waits for Screamer readiness and command completion using finite, wrap-safe
deadlines. Readback and recalibration follow the selected source-backed
sequence. Specify and cite operation-specific timeout and settling values in
the implementation plan before coding; no unbounded hardware loops.

Maintain desired user controls separately from successfully applied register
shadows. Update applied state only after a transaction succeeds. Translate
DriverKit volume/attenuation and input-gain ranges with saturation, correct
channel placement, and documented hardware quantization. Expose only inputs
and outputs actually present in the resolved machine configuration. Reject
unsupported input selection without changing the active input.

Initialize with outputs muted. Program codec state, rate, and supported
inputs, then apply the resolved output route and requested volume. Physical
output enables and amplifier controls follow the machine's wiring; do not
assume all machines use the same headphone sense bit or mute register.

Use validated codec port-change interrupts to schedule jack reevaluation.
Where no usable detection interrupt is delivered, poll only while ready at
250 ms intervals, with a second observation at least 5 ms later before
accepting a changed route. Deferred routing serializes with controls and
power transitions. A route change mutes affected paths before switching,
observes required settling time, and preserves user mute and volume. Advertise
only routes for which detection/control is complete.

## Lifecycle, failures, and power

Use explicit uninitialized, ready, suspended, faulted, and closing states;
stream direction state is tracked independently. Serialize control, stream,
and power transactions. Define lock order and interrupt/deferred-work handoff
in the implementation plan; never hold an interrupt lock across a codec wait.

Probe failure unwinds only resources acquired by this driver. After activation,
a failed control transaction reports failure through the available DriverKit
contract and preserves truthful applied state. If hardware state becomes
uncertain, attempt bounded muting and stop affected DMA; a failure involving
the shared controller faults both streams. Do not claim that a mute write
succeeded when the codec is unresponsive. Recovery requires an explicit
successful reinitialization, not an automatic retry loop in interrupt context.

For `PM_STANDBY`, `PM_SUSPENDED`, and `PM_OFF`, stop accepting starts, quiesce
deferred detection, mute outputs, stop DMA, and confirm inactivity before
releasing clocks. Preserve user controls and logical stream state. On
`PM_READY`, restore platform clocks, codec initialization/calibration, sample
rate, input selection, and routing while muted. Rebuild/rearm rings using
current buffers; never resume a stale hardware command pointer. Resume streams
only if their framework buffers and logical ownership are still valid. A
failed resume remains quiescent/faulted and reports failure.

`IOAudio` currently does not establish safe worker termination in `-free`.
Do not advertise hot unload or driver replacement. After workers can observe
the object, closing must prevent new work and quiesce hardware while retaining
any object, lock, callback context, or DMA storage that cannot be proved
unobservable. Reject reprobe until reboot when necessary. Before worker
publication, normal failure cleanup releases owned resources. This follows the
existing TAS lifecycle constraint without extending this task into a shared
`IOAudio` lifetime rewrite.

PPC `src/kernel-7/machdep/ppc/APM.c` currently returns `PM_R_BAD_STATE` from
`PMSetPowerState` and no events from `PMGetPowerEvent`. Driver callbacks alone
cannot deliver working system sleep/wake. Establish a prerequisite checkpoint
for actual platform sleep entry, driver callback delivery, and resume ordering.
If absent, deliver and test driver-local transitions but record end-to-end
power acceptance as blocked. Do not replace the stub with a success return,
equate manual callback invocation with system sleep, or mark full hardware
acceptance complete. Platform PM implementation requires its own design if
the prerequisite remains unavailable.

## Verification and acceptance

### Deterministic tests

Use scripted firmware, register, time, DMA-translation, cache, and interrupt
fixtures to test externally meaningful behavior:

- Positive Screamer identity and both driver load orders; negative AWACS,
  Burgundy, TAS, ambiguous graphs, malformed properties, conflicting profiles,
  and invalid range/interrupt descriptions. Rejected identity/resource
  configurations perform no writes; initialization failures unwind safely
  after any hardware access.
- Controller range/direction ordering, endian conversions, all supported rate
  selections, conflicting duplex rates, quantized controls, input rejection,
  and user-state preservation across route changes.
- Readiness, busy, readback, calibration, and power timeout paths; applied
  shadows never report a failed write as committed.
- Physically fragmented and boundary-split buffers, ring wraps, multiple
  completions, spurious interrupts, faults, cache-operation order, and
  independent direction stop/start.
- Jack debounce, concurrent control/power requests, suspend/resume ordering,
  failed resume, stale deferred work, and safe close with pending callbacks.

Run existing TAS and affected Platform Expert tests whenever shared code or
services change. Use C89-compatible testable code and the repository's existing
host-test conventions; tests may run in a configured build guest when the
Windows host lacks a compatible compiler.

### Build and packaging

Build the new bundle and changed Platform Expert code with the period PPC
toolchain. Inspect the Mach-O architecture, kernel-server glue, source-path
resolution, installed configuration, exported platform services, and package
contents. Verify the i386 selection excludes the project. Record exact
commands, toolchain identity, artifact hashes, and results; static review does
not replace target compilation. No guest or physical hardware availability is
assumed by this spec.

### Physical acceptance

For Sawtooth and separately for each additional claimed machine/profile:

1. Capture model/firmware/codec identity and the relevant device-tree resources;
   verify exactly one audio driver attaches.
2. Run simultaneous 44.1 kHz stereo playback and recording for ten minutes,
   crossing repeated DMA ring wraps without driver timeouts, descriptor
   faults, or unexplained completion loss. Verify channel order, pitch, output
   audibility, and captured signal integrity with known test signals.
3. Complete 100 stream start/stop cycles, including independent direction
   stops during duplex operation. Check each additionally advertised rate and
   reject mismatched duplex requests without disrupting the active stream.
4. Exercise volume endpoints, left/right balance, mute, input gain and every
   exposed input. Test insertion/removal for each supported output connector
   while idle and streaming; preserve user controls and avoid unintended
   speaker output while headphones are selected.
5. Once platform PM works, complete ten real sleep/wake cycles, covering idle
   and active streams. Verify callback order, codec restoration, routing after
   a jack change during sleep, and resumed playback/capture without stale DMA.

Record code-test, target-build, physical-audio, and physical-power results
separately. Full release acceptance requires all applicable checks; a candidate
machine remains unvalidated until its own results exist. QEMU can provide
build/boot evidence only for devices it actually models. Do not add emulator
hardware to meet this driver project's acceptance criteria.

If a guest is used, follow `AGENTS.md`: use a throwaway image or snapshot,
unique guest name and ports, and confirm `query-name` before QMP shutdown.
Never test by modifying `vm/rhap-i386-bootstrapped-v2.img` directly.

## Sources and provenance

Record register and wiring evidence in the driver's `SOURCES.md` during
implementation, including the exact symbols/sections used and any retained
license notices. References below are pinned for reproducibility:

- Apple `AppleOnboardAudio`, commit
  `46f2f8a643cc36e1332feece6e39dd42a37302ab`:
  [AppleScreamerAudio.cpp](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AppleScreamerAudio/AppleScreamerAudio.cpp)
  and [awacs_hw.h](https://github.com/apple-oss-distributions/AppleOnboardAudio/blob/46f2f8a643cc36e1332feece6e39dd42a37302ab/AppleLegacyAudio/AppleScreamerAudio/awacs_hw.h).
  These supply Screamer protocol and NewWorld firmware behavior. Use behavior
  appropriate to Rhapsody DriverKit; do not transplant IOKit classes or its
  unbounded wait loops. Review associated power and firmware-parser sources
  at the same commit before deriving clock and wiring profiles.
- NetBSD, commit `2622ed57a3e1c4995403c4c4f510bc1722be4f03`:
  [awacs.c](https://github.com/NetBSD/src/blob/2622ed57a3e1c4995403c4c4f510bc1722be4f03/sys/arch/macppc/dev/awacs.c).
  This corroborates register/rate definitions, DBDMA resource order, and
  machine-specific detection/output differences. Its broad match policy is
  not the admission policy of this Screamer-only driver.
- OpenBSD, commit `c30c84965dc47c6c65e75cc3b5dd6eb181819bfa`:
  [awacs.c](https://github.com/openbsd/src/blob/c30c84965dc47c6c65e75cc3b5dd6eb181819bfa/sys/arch/macppc/dev/awacs.c).
  This corroborates compact codec/control and DMA behavior. Retain the
  applicable permissive notices for any adapted source.
- Linux, commit `58161ead29e50d70a317ea26b472e0c7508e69da`:
  [awacs.c](https://github.com/torvalds/linux/blob/58161ead29e50d70a317ea26b472e0c7508e69da/sound/ppc/awacs.c)
  and [pmac.c](https://github.com/torvalds/linux/blob/58161ead29e50d70a317ea26b472e0c7508e69da/sound/ppc/pmac.c).
  Consulted as corroborating hardware behavior only. Do not copy GPL code,
  tables, or comments into this driver.

Repository evidence includes `drvPPCAwacs`, its reconstruction findings,
`drvPPCTASAudio` and its tests/README, DriverKit `IOAudio` and `IODBDMA`,
Platform Expert's KeyLargo services, and PPC `APM.c`. Shipped-binary method
correspondence is not proof that the reconstructed AWACS behavior works.

## Handoff to implementation planning

After the user reviews this written spec, produce a separate implementation
plan with exact file paths, reuse/build wiring, pinned register and platform
sequences, timeouts, tests and expected outcomes, and ordered deliverables.
Start with hardware/resource evidence and exclusivity tests, then codec and
platform control, duplex DMA, routing, lifecycle, target packaging, and
physical acceptance. Make the platform PM prerequisite visible before power
acceptance. Implementation starts only after plan review and selection of its
execution method.
